resource "hcloud_ssh_key" "admin" {
  name       = "${var.server_name}-admin"
  public_key = file(pathexpand(var.ssh_public_key_path))
}

# Inbound is default-deny on Hetzner firewalls; outbound is unrestricted.
# Only what is listed here is reachable.
resource "hcloud_firewall" "web" {
  name = "${var.server_name}-fw"

  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "22"
    source_ips = var.ssh_allowed_ips
  }

  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "80"
    source_ips = ["0.0.0.0/0", "::/0"]
  }

  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "443"
    source_ips = ["0.0.0.0/0", "::/0"]
  }

  # HTTP/3 (QUIC). Caddy advertises it; without this browsers silently fall back.
  rule {
    direction  = "in"
    protocol   = "udp"
    port       = "443"
    source_ips = ["0.0.0.0/0", "::/0"]
  }

  rule {
    direction  = "in"
    protocol   = "icmp"
    source_ips = ["0.0.0.0/0", "::/0"]
  }
}

# Primary IPs are declared separately on purpose. If the server allocated its
# own address, every `terraform destroy` / rebuild would hand you a new IP and
# silently break DNS. These outlive the server (auto_delete = false).
resource "hcloud_primary_ip" "v4" {
  name        = "${var.server_name}-ipv4"
  type        = "ipv4"
  location    = var.location
  auto_delete = false
}

resource "hcloud_primary_ip" "v6" {
  name        = "${var.server_name}-ipv6"
  type        = "ipv6"
  location    = var.location
  auto_delete = false
}

resource "hcloud_server" "web" {
  name        = var.server_name
  image       = var.image
  server_type = var.server_type
  location    = var.location

  ssh_keys     = [hcloud_ssh_key.admin.id]
  firewall_ids = [hcloud_firewall.web.id]

  public_net {
    ipv4_enabled = true
    ipv4         = hcloud_primary_ip.v4.id
    ipv6_enabled = true
    ipv6         = hcloud_primary_ip.v6.id
  }

  # NOTE: editing this template forces the server to be recreated. It runs once,
  # on first boot only. Treat it as bootstrap, not as ongoing config management.
  user_data = templatefile("${path.module}/cloud-init.yaml.tftpl", {
    admin_user     = var.admin_user
    ssh_public_key = trimspace(file(pathexpand(var.ssh_public_key_path)))
    hostname       = var.server_name
    caddyfile      = file("${path.module}/Caddyfile")
  })

  labels = {
    role    = "web"
    managed = "terraform"
  }
}
