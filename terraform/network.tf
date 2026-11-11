# Network segments: one Docker bridge per zone. Hosts route everything outside
# their own subnet through the firewall container (see images/node/entrypoint.sh).
# Why not Docker "internal" networks: their host rules drop any packet addressed
# outside the subnet, even one handed to a router on the same bridge, so routing
# through the firewall is impossible. Details: docs/adr/0002-docker-networking.md.

locals {
  policy = yamldecode(file("${path.module}/../policy/network.yml"))

  # "internet" is not a network we create; it's whatever lies beyond the firewall's WAN side.
  zones = { for name, z in local.policy.zones : name => z if name != "internet" }

  # Every host except the firewall, which is defined separately.
  hosts = { for name, h in local.policy.hosts : name => h if try(h.role, "") != "firewall" }

  # The firewall is .254 in every zone; clients use it as their default gateway.
  fw_ip  = { for name, z in local.zones : name => cidrhost(z.subnet, 254) }
  wan_fw = cidrhost(var.wan_subnet, 2)

  labels = { project = var.name_prefix, managed-by = "terraform" }
}

resource "docker_network" "zone" {
  for_each = local.zones

  name   = "${var.name_prefix}-${each.key}"
  driver = "bridge"

  ipam_config {
    subnet  = each.value.subnet
    gateway = cidrhost(each.value.subnet, 1)
  }

  dynamic "labels" {
    for_each = merge(local.labels, { zone = each.key })
    content {
      label = labels.key
      value = labels.value
    }
  }
}

# Uplink: only the firewall is attached, and it NATs office traffic out.
resource "docker_network" "wan" {
  name   = "${var.name_prefix}-wan"
  driver = "bridge"

  ipam_config {
    subnet  = var.wan_subnet
    gateway = cidrhost(var.wan_subnet, 1)
  }

  dynamic "labels" {
    for_each = local.labels
    content {
      label = labels.key
      value = labels.value
    }
  }
}

# Lets the admin's own machine open Grafana/Prometheus (bound to 127.0.0.1 only).
# Stands in for an admin VPN into the management segment.
resource "docker_network" "access" {
  name   = "${var.name_prefix}-access"
  driver = "bridge"

  ipam_config {
    subnet  = var.access_subnet
    gateway = cidrhost(var.access_subnet, 1)
  }

  dynamic "labels" {
    for_each = local.labels
    content {
      label = labels.key
      value = labels.value
    }
  }
}
