output "ipv4" {
  description = "Put this in your DNS A record."
  value       = hcloud_primary_ip.v4.ip_address
}

# An IPv6 Primary IP is a /64 NETWORK, and ip_address returns its base
# (…:7af2::). That is the subnet address, not a host — an AAAA record pointing
# at it does not reach the server. Hetzner's images configure …::1 on the
# interface, so that is the host address DNS must carry.
output "ipv6" {
  description = "Put this in your DNS AAAA record (host address, not the /64 base)."
  value       = "${hcloud_primary_ip.v6.ip_address}1"
}

output "ipv6_network" {
  description = "The full /64 assigned to this server. Not a DNS target."
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

# authoritative_nameservers is a single nested OBJECT, not a list — the hostnames
# live in its `assigned` field. Reading the object directly yields a type error
# against the empty-list fallback.
output "nameservers" {
  description = "Enter these at your registrar to delegate the domain. Empty until var.domain is set."
  value       = local.dns_enabled ? one(hcloud_zone.main[*].authoritative_nameservers).assigned : []
}

output "dns_records" {
  description = "The records to create once you own a domain."
  value       = <<-EOT

    A     @      ${hcloud_primary_ip.v4.ip_address}
    AAAA  @      ${hcloud_primary_ip.v6.ip_address}1
    A     www    ${hcloud_primary_ip.v4.ip_address}
    AAAA  www    ${hcloud_primary_ip.v6.ip_address}1

    These addresses are stable across server rebuilds.
  EOT
}
