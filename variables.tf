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
    Hetzner server type. cx22 = 2 vCPU Intel / 4 GB (x86, safest default).
    cax11 = 2 vCPU Ampere / 4 GB (ARM, same price) — only if every container
    image you plan to run publishes an arm64 build.
  EOT
  type        = string
  default     = "cx22"
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
