variable "docker_host" {
  description = "Docker daemon address. Leave null to use DOCKER_HOST or the default socket."
  type        = string
  default     = null
}

variable "enable_siem" {
  description = "Run the Wazuh SIEM (about 1 GB of RAM). Everything else works without it."
  type        = bool
  default     = true
}

variable "name_prefix" {
  description = "Prefix for every Docker object, so the lab is easy to find and remove."
  type        = string
  default     = "kestrel"
}

variable "wan_subnet" {
  description = "Docker bridge the firewall uses to reach the internet (NAT)."
  type        = string
  default     = "10.20.0.0/24"
}

variable "access_subnet" {
  description = "Bridge used only to publish Grafana and Prometheus on 127.0.0.1 of your machine."
  type        = string
  default     = "10.20.99.0/24"
}

variable "images" {
  description = "Pinned third-party images."
  type        = map(string)
  default = {
    lldap       = "lldap/lldap:v0.6.3"
    rest_server = "restic/rest-server:0.14.0"
    prometheus  = "prom/prometheus:v3.13.5"
    grafana     = "grafana/grafana:12.4.15"
    blackbox    = "prom/blackbox-exporter:v0.28.0"
    pushgateway = "prom/pushgateway:v1.11.3"
    wazuh       = "wazuh/wazuh-manager:4.14.8"
  }
}
