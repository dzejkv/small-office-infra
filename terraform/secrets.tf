# Secrets are generated, never written by hand and never committed.
# They live in Terraform state (local, gitignored) and are copied to .secrets/
# with owner-only permissions so Ansible and the admin can use them.

resource "random_password" "secret" {
  for_each = toset(["lldap-admin", "lldap-jwt", "lldap-key-seed", "grafana-admin", "svc-grafana"])

  length  = 32
  special = false
}

resource "local_sensitive_file" "secret" {
  for_each = random_password.secret

  filename             = "${path.module}/../.secrets/${each.key}"
  content              = each.value.result
  file_permission      = "0600"
  directory_permission = "0700"
}
