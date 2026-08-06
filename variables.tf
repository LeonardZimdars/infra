variable "hcloud_token" {
  description = "Hetzner Cloud API token with Read & Write permission."
  type        = string
  sensitive   = true
}

variable "server_name" {
  description = "Name of the server in the Hetzner console. Also its hostname."
  type        = string
  default     = "web-01"
}

variable "server_type" {
  description = <<-EOT
    cx23 = 2 vCPU x86 / 4 GB / 40 GB — cheapest type actually available at fsn1.

    Note the generation shift: cx22 and cpx11 are retired names, replaced by
    cx23 and cpx12. ARM (cax11) is preferable on price/performance but was out
    of stock in every datacenter as of Aug 2026 — a server type being
    "supported" at a location does not mean it is "available".

    Check before changing this, since a bad value fails at apply time with
    `resource_unavailable`:
      curl -H "Authorization: Bearer $HCLOUD_TOKEN" \
        https://api.hetzner.cloud/v1/datacenters

    Changing this replaces the server.
  EOT
  type        = string
  default     = "cx23"
}

variable "location" {
  description = <<-EOT
    fsn1 (Falkenstein, DE), nbg1 (Nuremberg, DE), hel1 (Helsinki, FI),
    ash (Ashburn, US), hil (Hillsboro, US), sin (Singapore).
    The Primary IPs and the server must share this.
  EOT
  type        = string
  default     = "fsn1"
}

variable "image" {
  description = "Base OS image. Changing this destroys and recreates the server."
  type        = string
  default     = "ubuntu-24.04"
}

variable "ssh_public_key_path" {
  description = "Public key uploaded to Hetzner and installed for the admin user."
  type        = string
  default     = "~/.ssh/hetzner.pub"
}

variable "admin_user" {
  description = "Non-root sudo user created by cloud-init."
  type        = string
  default     = "leo"
}

variable "ssh_allowed_ips" {
  description = <<-EOT
    CIDRs permitted to reach port 22. Defaults to the whole internet, which is
    acceptable because cloud-init disables password auth entirely — but if you
    have a static IP, narrowing this to ["a.b.c.d/32"] is a free win.
  EOT
  type        = list(string)
  default     = ["0.0.0.0/0", "::/0"]
}
