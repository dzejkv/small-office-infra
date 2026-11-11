# How this would look on AWS

The lab runs on Docker so anyone can build it for free. The design maps directly
onto a cloud deployment. This is how I'd build it on AWS.

| Lab | AWS | Notes |
|---|---|---|
| Docker network per zone | VPC with one **subnet per zone** | Private subnets for servers, backup and mgmt |
| Firewall container (nftables) | **Security groups** + **network ACLs**, or **AWS Network Firewall** for central inspection | Security groups give the per-flow rules; Network Firewall adds logging like ulogd |
| NAT on the firewall | **NAT gateway** in a public subnet | Only staff, guest and mgmt route tables point to it; servers get none |
| Published Grafana on 127.0.0.1 | **Client VPN** or **SSM Session Manager** port forwarding | No public IPs on anything in mgmt |
| Admin jump host + SSH key | **SSM Session Manager** | No SSH port open at all; every session logged to CloudTrail |
| lldap directory | **IAM Identity Center** with groups, or AWS Managed Microsoft AD for Windows clients | Same idea: groups decide access |
| restic + append-only rest-server | **S3 with Object Lock** (compliance mode) + lifecycle rules, or **AWS Backup** with a vault lock | Object Lock is the cloud version of "append-only" |
| Prometheus + Grafana | **CloudWatch** metrics and alarms, or Amazon Managed Prometheus/Grafana | |
| Wazuh over syslog | **Security Hub** + **GuardDuty** + CloudWatch Logs, or Wazuh on EC2 fed by VPC Flow Logs | GuardDuty covers port scans and brute force out of the box |
| Generated secrets in `.secrets/` | **Secrets Manager** | |
| Terraform with local state | Terraform with **S3 backend + DynamoDB lock** | Shared, locked state for a team |
