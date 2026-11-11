# Ansible inventory, generated from the same policy file Terraform used.
resource "local_file" "inventory" {
  filename        = "${path.module}/../ansible/inventory/hosts.yml"
  file_permission = "0644"
  content = templatefile("${path.module}/templates/inventory.yml.tftpl", {
    prefix      = var.name_prefix
    zones       = keys(local.zones)
    hosts       = local.hosts
    enable_siem = var.enable_siem
  })
}

output "grafana_url" {
  value = "http://127.0.0.1:3000"
}

output "prometheus_url" {
  value = "http://127.0.0.1:9090"
}

output "containers" {
  value = concat(
    [docker_container.firewall.name],
    [for h in docker_container.host : h.name],
  )
}
