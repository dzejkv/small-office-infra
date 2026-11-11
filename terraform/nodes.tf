# "Machines": the firewall, workstations, servers, and the hosts that
# third-party services run on (services share their host's network namespace).

resource "docker_image" "node" {
  name = "${var.name_prefix}/node:local"
  build {
    context = abspath("${path.module}/../images/node")
  }
  triggers = {
    src = sha1(join("", [for f in sort(fileset("${path.module}/../images/node", "*")) : filesha1("${path.module}/../images/node/${f}")]))
  }
  keep_locally = true
}

resource "docker_volume" "data" {
  for_each = toset(["lldap", "files", "backup-repo", "prometheus", "pushgateway", "grafana"])
  name     = "${var.name_prefix}-${each.key}"
}

locals {
  # Extra storage per host: name => list of {volume, path, read_only}
  host_volumes = {
    directory = [{ volume = "lldap", path = "/backup-src/lldap", read_only = true }]
    files     = [{ volume = "files", path = "/srv/files", read_only = false }]
    backup    = [{ volume = "backup-repo", path = "/data", read_only = false }]
  }
  # Ports published on the admin's machine (127.0.0.1 only).
  host_ports = {
    monitoring = [3000, 9090]
  }
}

resource "docker_container" "firewall" {
  name     = "${var.name_prefix}-fw"
  hostname = "fw"
  image    = docker_image.node.image_id
  restart  = "unless-stopped"

  env = ["NODE_ROLE=firewall"]
  capabilities {
    add = ["CAP_NET_ADMIN"]
  }
  sysctls = {
    "net.ipv4.ip_forward" = "1"
  }

  networks_advanced {
    name         = docker_network.wan.name
    ipv4_address = local.wan_fw
  }
  dynamic "networks_advanced" {
    for_each = local.zones
    content {
      name         = docker_network.zone[networks_advanced.key].name
      ipv4_address = local.fw_ip[networks_advanced.key]
    }
  }

  dynamic "labels" {
    for_each = merge(local.labels, { role = "firewall" })
    content {
      label = labels.key
      value = labels.value
    }
  }
}

resource "docker_container" "host" {
  for_each = local.hosts

  name     = "${var.name_prefix}-${each.key}"
  hostname = each.key
  image    = docker_image.node.image_id
  restart  = "unless-stopped"

  env = ["FW_GATEWAY=${local.fw_ip[each.value.zone]}", "NODE_ROLE=${each.key}"]
  # Needed only to point the default route at the firewall at start-up.
  capabilities {
    add = ["CAP_NET_ADMIN"]
  }

  networks_advanced {
    name         = docker_network.zone[each.value.zone].name
    ipv4_address = each.value.ip
  }
  dynamic "networks_advanced" {
    for_each = contains(keys(local.host_ports), each.key) ? [1] : []
    content {
      name = docker_network.access.name
    }
  }

  dynamic "ports" {
    for_each = lookup(local.host_ports, each.key, [])
    content {
      internal = ports.value
      external = ports.value
      ip       = "127.0.0.1"
    }
  }

  dynamic "volumes" {
    for_each = lookup(local.host_volumes, each.key, [])
    content {
      volume_name    = docker_volume.data[volumes.value.volume].name
      container_path = volumes.value.path
      read_only      = volumes.value.read_only
    }
  }

  dynamic "labels" {
    for_each = merge(local.labels, { zone = each.value.zone })
    content {
      label = labels.key
      value = labels.value
    }
  }

  depends_on = [docker_container.firewall]
}
