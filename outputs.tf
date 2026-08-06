output "ipv4" {
  description = "Put this in your DNS A record."
  value       = hcloud_primary_ip.v4.ip_address
}

output "ipv6" {
  description = "Put this in your DNS AAAA record."
  value       = hcloud_primary_ip.v6.ip_address
}

output "admin_user" {
  description = "Login user. Consumed by deploy.sh."
  value       = var.admin_user
}

output "ssh" {
  description = "Ready-to-paste SSH command."
  value       = "ssh ${var.admin_user}@${hcloud_primary_ip.v4.ip_address}"
}

output "dns_records" {
  description = "The records to create once you own a domain."
  value       = <<-EOT

    A     @      ${hcloud_primary_ip.v4.ip_address}
    AAAA  @      ${hcloud_primary_ip.v6.ip_address}
    A     www    ${hcloud_primary_ip.v4.ip_address}
    AAAA  www    ${hcloud_primary_ip.v6.ip_address}

    These addresses are stable across server rebuilds.
  EOT
}
