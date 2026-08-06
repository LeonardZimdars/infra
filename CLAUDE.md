# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Terraform for a single Hetzner Cloud VPS that hosts personal websites. One server
fronted by Caddy serves many sites by hostname — adding a site is a Caddyfile block
plus a DNS record, **not** a Terraform change. Do not add a server per site.

## Commands

```sh
terraform init                  # after cloning or changing provider versions
terraform fmt                   # run before committing
terraform validate              # no API calls; catches schema errors
terraform plan                  # hits the Hetzner API; needs a valid token
terraform apply
terraform output dns_records    # the A/AAAA records to create
ssh "$(terraform output -raw ssh)"
```

Credentials come from `terraform.tfvars` (gitignored, holds `hcloud_token`).
`HCLOUD_TOKEN` in the environment also works and takes precedence over the file —
but only if `provider "hcloud"` has no explicit `token`, which it currently does.

## State

State lives in HCP Terraform: organization `leonard-zimdars`, workspace `infra`,
declared in the `cloud` block in `versions.tf`. Requires `terraform login` once.

**The workspace's execution mode is set to `local`, and must stay that way.** HCP
defaults new CLI-driven workspaces to `remote`, which runs plans on HashiCorp's
runners — those cannot see the gitignored `terraform.tfvars`, so applies fail on a
missing `hcloud_token`, and the fix people reach for (uploading the config) ships
the token off this machine. Local mode means HCP stores only state; plans and the
token stay here. Execution mode is a UI/API setting with no HCL equivalent, so it
is invisible in this repo — if runs suddenly fail asking for `hcloud_token`, check
that it has not been flipped back.

One workspace covers this whole root module. Adding websites does not add
Terraform resources (they are Caddyfile blocks), so this stays at one workspace.

## Architecture

**Terraform's boundary stops at the machine.** It owns the SSH key, firewall,
Primary IPs, and server. It does not own Caddy config, site content, or TLS.
Those live on the server. Do not add deployment logic here.

**Primary IPs are separate resources on purpose** (`main.tf`). If the server
allocated its own address, any rebuild would issue a new IP and silently break
every DNS record. `auto_delete = false` makes them outlive the server, so the
addresses in `terraform output` are stable and safe to hardcode in DNS.

**`cloud-init.yaml.tftpl` runs once, on first boot only.** Editing it forces
Terraform to destroy and recreate the server — check `plan` output for
`forces replacement` before applying. It is bootstrap, not config management.
To change a running server, SSH in, or move to Ansible if this grows.

**The firewall default-denies inbound**; only 22/80/443-tcp, 443-udp (HTTP/3),
and ICMP are open. Outbound is unrestricted. Port 22 is internet-facing, which
is only acceptable because cloud-init sets `ssh_pwauth: false` and
`disable_root: true` — do not weaken either without narrowing `ssh_allowed_ips`.

## Gotchas

- `hcloud_primary_ip` takes `location` (e.g. `fsn1`), not `datacenter`. The
  provider changed this; older examples online are wrong. Pinned to `~> 1.68`.
- `templatefile` interprets `${...}`. Shell variables inside
  `cloud-init.yaml.tftpl` must be escaped as `$${...}`.
- `example.tfvars` is deliberately un-ignored via a `!` rule so the template is
  version-controlled. Never put a real token in it.
- `.terraform.lock.hcl` is committed intentionally.
- Hetzner blocks outbound port 25 on new accounts. Do not plan on self-hosted mail.
- A server type can be `supported` at a location but not `available`. Apply then
  fails with `resource_unavailable`. Check real capacity before changing
  `server_type` or `location`:
  `curl -H "Authorization: Bearer $TOKEN" https://api.hetzner.cloud/v1/datacenters`
- Rebuilding regenerates SSH host keys while the Primary IP stays the same, so
  SSH reports `REMOTE HOST IDENTIFICATION HAS CHANGED` and refuses to connect.
  Expected, not an attack. Clear it with `ssh-keygen -R <ip>`. Anything holding a
  pinned `known_hosts` entry (e.g. a CI deploy job) must be updated after a rebuild.
- Never pre-create a path in `write_files` that a package ships as a conffile.
  dpkg prompts, finds no stdin, and aborts configuring the package — which is how
  the caddy user once ended up missing and the service dead at `217/USER`. Stage
  such files elsewhere and install them in `runcmd` after the package.

## Patching

`unattended-upgrades` applies security updates automatically. Stock Ubuntu config
covers Ubuntu origins only, so `52unattended-upgrades-local` (written by
cloud-init) adds the Caddy and Docker repos — without it the two internet-facing
packages are never patched. APT list syntax appends, so that file must not
restate the Ubuntu origins.

**The server reboots itself at 04:00 UTC when a kernel or libc update requires
it.** That is deliberate: auto-reboot defaults to off, which silently leaves the
box on an unpatched kernel indefinitely. Revisit if stateful services land here.

Docker *images* are outside all of this — container contents need their own
update path.

## Adding a site (no Terraform involved)

1. Add a block to `./Caddyfile` in this repo — `root`+`file_server` for static,
   `reverse_proxy localhost:PORT` for a container.
2. `./deploy.sh`
3. Point an A/AAAA record at the Primary IPs.

Caddy provisions Let's Encrypt certificates automatically once a block names a
real hostname. There is no certbot and no renewal cron.

**`./Caddyfile` in this repo is the source of truth.** `deploy.sh` rsyncs it,
validates it on the server, then installs and reloads — so a syntax error fails
the deploy instead of taking sites down. cloud-init injects this same file via
`templatefile` on first boot, which is what keeps a rebuilt server current
rather than pinned to whatever routing existed when the template was written.

Never hand-edit `/etc/caddy/Caddyfile` on the server: the next `deploy.sh`
overwrites it, and the change exists nowhere else.
