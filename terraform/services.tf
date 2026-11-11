# Third-party services. Each runs inside a lab host's network namespace
# (network_mode = "container:<host>"), so it has that host's address and is
# subject to the same firewall policy.

locals {
  cfg = abspath("${path.module}/../config")
}

resource "docker_image" "svc" {
  for_each     = var.images
  name         = each.value
  keep_locally = true
}

# ---- Directory (servers zone) ------------------------------------------------

resource "docker_container" "lldap" {
  name         = "${var.name_prefix}-lldap"
  image        = docker_image.svc["lldap"].image_id
  restart      = "unless-stopped"
  network_mode = "container:${docker_container.host["directory"].id}"

  env = [
    "LLDAP_LDAP_BASE_DN=dc=kestrel,dc=test",
    "LLDAP_JWT_SECRET=${random_password.secret["lldap-jwt"].result}",
    "LLDAP_KEY_SEED=${random_password.secret["lldap-key-seed"].result}",
    "LLDAP_LDAP_USER_PASS=${random_password.secret["lldap-admin"].result}",
    "TZ=UTC",
  ]
  volumes {
    volume_name    = docker_volume.data["lldap"].name
    container_path = "/data"
  }
}

# ---- Backup server (backup zone) ----------------------------------------------

resource "docker_container" "rest_server" {
  name         = "${var.name_prefix}-rest-server"
  image        = docker_image.svc["rest_server"].image_id
  restart      = "unless-stopped"
  network_mode = "container:${docker_container.host["backup"].id}"

  # append-only: clients can add backups but never delete or overwrite them.
  # private-repos: each client can only see its own repository.
  env = ["OPTIONS=--append-only --private-repos"]
  volumes {
    volume_name    = docker_volume.data["backup-repo"].name
    container_path = "/data"
  }
}

# ---- Monitoring (mgmt zone) ----------------------------------------------------

resource "docker_container" "prometheus" {
  name         = "${var.name_prefix}-prometheus"
  image        = docker_image.svc["prometheus"].image_id
  restart      = "unless-stopped"
  network_mode = "container:${docker_container.host["monitoring"].id}"

  command = [
    "--config.file=/etc/prometheus/prometheus.yml",
    "--storage.tsdb.path=/prometheus",
    "--storage.tsdb.retention.time=15d",
    "--web.enable-lifecycle",
  ]
  volumes {
    host_path      = "${local.cfg}/monitoring/prometheus.yml"
    container_path = "/etc/prometheus/prometheus.yml"
    read_only      = true
  }
  volumes {
    host_path      = "${local.cfg}/monitoring/alerts.yml"
    container_path = "/etc/prometheus/alerts.yml"
    read_only      = true
  }
  volumes {
    volume_name    = docker_volume.data["prometheus"].name
    container_path = "/prometheus"
  }
}

resource "docker_container" "blackbox" {
  name         = "${var.name_prefix}-blackbox"
  image        = docker_image.svc["blackbox"].image_id
  restart      = "unless-stopped"
  network_mode = "container:${docker_container.host["monitoring"].id}"

  command = ["--config.file=/etc/blackbox/blackbox.yml"]
  volumes {
    host_path      = "${local.cfg}/monitoring/blackbox.yml"
    container_path = "/etc/blackbox/blackbox.yml"
    read_only      = true
  }
}

resource "docker_container" "pushgateway" {
  name         = "${var.name_prefix}-pushgateway"
  image        = docker_image.svc["pushgateway"].image_id
  restart      = "unless-stopped"
  network_mode = "container:${docker_container.host["monitoring"].id}"

  command = ["--persistence.file=/data/metrics", "--persistence.interval=1m"]
  volumes {
    volume_name    = docker_volume.data["pushgateway"].name
    container_path = "/data"
  }
}

resource "docker_container" "grafana" {
  name         = "${var.name_prefix}-grafana"
  image        = docker_image.svc["grafana"].image_id
  restart      = "unless-stopped"
  network_mode = "container:${docker_container.host["monitoring"].id}"

  env = [
    "GF_SECURITY_ADMIN_PASSWORD=${random_password.secret["grafana-admin"].result}",
    "GF_AUTH_LDAP_ENABLED=true",
    "GF_AUTH_LDAP_CONFIG_FILE=/etc/grafana/ldap.toml",
    "GF_AUTH_LDAP_ALLOW_SIGN_UP=true",
    "GF_AUTH_ANONYMOUS_ENABLED=false",
    "GF_USERS_ALLOW_SIGN_UP=false",
    "GF_ANALYTICS_REPORTING_ENABLED=false",
    "GF_ANALYTICS_CHECK_FOR_UPDATES=false",
    "GF_NEWS_NEWS_FEED_ENABLED=false",
    "LDAP_BIND_PASSWORD=${random_password.secret["svc-grafana"].result}",
  ]
  volumes {
    host_path      = "${local.cfg}/monitoring/grafana/ldap.toml"
    container_path = "/etc/grafana/ldap.toml"
    read_only      = true
  }
  volumes {
    host_path      = "${local.cfg}/monitoring/grafana/provisioning"
    container_path = "/etc/grafana/provisioning"
    read_only      = true
  }
  volumes {
    host_path      = "${local.cfg}/monitoring/grafana/dashboards"
    container_path = "/etc/grafana/dashboards"
    read_only      = true
  }
  volumes {
    volume_name    = docker_volume.data["grafana"].name
    container_path = "/var/lib/grafana"
  }
}

# ---- SIEM (mgmt zone) ------------------------------------------------------------

resource "docker_container" "wazuh" {
  count = var.enable_siem ? 1 : 0

  name         = "${var.name_prefix}-wazuh"
  image        = docker_image.svc["wazuh"].image_id
  restart      = "unless-stopped"
  network_mode = "container:${docker_container.host["siem"].id}"

  ulimit {
    name = "nofile"
    soft = 655360
    hard = 655360
  }

  # Recreate the container when detection content changes (bind mounts are
  # otherwise invisible to Terraform).
  labels {
    label = "siem-config-sha1"
    value = sha1(join("", [for f in ["ossec.conf", "local_rules.xml", "local_decoder.xml"] : filesha1("${local.cfg}/siem/${f}")]))
  }

  # No indexer in this lab, so the bundled Filebeat shipper has nowhere to send.
  # An s6 "down" file stops it starting.
  volumes {
    host_path      = "${local.cfg}/siem/filebeat-down"
    container_path = "/etc/services.d/filebeat/down"
    read_only      = true
  }
  volumes {
    host_path      = "${local.cfg}/siem/ossec.conf"
    container_path = "/wazuh-config-mount/etc/ossec.conf"
    read_only      = true
  }
  volumes {
    host_path      = "${local.cfg}/siem/local_rules.xml"
    container_path = "/wazuh-config-mount/etc/rules/local_rules.xml"
    read_only      = true
  }
  volumes {
    host_path      = "${local.cfg}/siem/local_decoder.xml"
    container_path = "/wazuh-config-mount/etc/decoders/local_decoder.xml"
    read_only      = true
  }
}
