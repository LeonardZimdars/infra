# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Terraform for a single Hetzner Cloud VPS hosting personal websites. One server
fronted by Caddy serves many sites by hostname. **Do not add a server per site** —
capacity is not the constraint and never will be at this scale.

Live: `https://leonardzimdars.com` (apex canonical, `www` 301s to it).

## Commands

```sh
terraform init                  # after cloning or changing provider versions
terraform fmt                   # run before committing
terraform validate              # no API calls; catches schema and type errors
terraform plan                  # hits the Hetzner API; needs a valid token
terraform apply
./deploy.sh                     # push ./Caddyfile to the server and reload
terraform output nameservers    # values to enter at the registrar
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

**Terraform owns infrastructure, not what runs on the box.** It owns the SSH key,
firewall, Primary IPs, server, and — since DNS moved in-provider — the zone,
records, and rDNS. It does **not** own Caddy config, site content, or TLS. Those
live on the server and are pushed with `deploy.sh`. Do not add deployment logic
to Terraform.

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
  SSH reports `REMOTE HOST IDENTIFICATION HAS CHANGED`. Expected, not an attack.
  `terraform_data.clear_known_hosts` runs `ssh-keygen -R` locally on every server
  replacement, so this is handled — but only on the machine running Terraform.
  Anything else holding a pinned host key (a CI deploy job's `KNOWN_HOSTS`
  secret) still needs updating by hand, and fails with an identical-looking error.
  Do NOT "fix" this by pinning host keys via cloud-init's `ssh_keys` module: that
  puts a private host key into user_data, readable from the metadata service.
- `hcloud_zone.authoritative_nameservers` is a single nested OBJECT, not a list —
  the hostnames are in its `.assigned` field. Reading the object directly is a
  type error. Provider attribute shapes are worth checking rather than guessing:
  `terraform providers schema -json` works offline and is authoritative.
- **Caddy issues one certificate per hostname**, regardless of how site blocks
  group names. `leonardzimdars.com.crt` and `www.leonardzimdars.com.crt` are
  separate, each with a single SAN. Grouping names in one block does not merge
  them into a multi-SAN cert. Harmless — both renew automatically.
- `cloud-init.yaml.tftpl` ends with `power_state: reboot`, conditional on
  `/var/run/reboot-required`. Without it every fresh build sits on the base
  image's older kernel until the 04:00 job reboots it, since `package_upgrade`
  installs a newer one during bootstrap.
- Never pre-create a path in `write_files` that a package ships as a conffile.
  dpkg prompts, finds no stdin, and aborts configuring the package — which is how
  the caddy user once ended up missing and the service dead at `217/USER`. Stage
  such files elsewhere and install them in `runcmd` after the package.

## DNS

In `dns.tf`, via `hcloud_zone` / `hcloud_zone_rrset` in the **official** provider —
Hetzner folded the old dns.hetzner.com product and its separate API/token into the
main console, so DNS uses the same provider, token, and state as everything else.
The old `dns.hetzner.com/api/v1` endpoint 301s; `api.hetzner.cloud/v1/zones` is
current. Ignore any guidance about a community DNS provider or a second token.

`var.domain` is `leonardzimdars.com`, registered at Porkbun and delegated to
Hetzner's nameservers. Everything in `dns.tf` is inert if that is set back to `""`.

Terraform **cannot** delegate a domain — `terraform output nameservers` has to be
entered at the registrar by hand, and propagation takes minutes to 48h. Stale
caches during a delegation change are normal; check the authoritative servers
(`dig @hydrogen.ns.hetzner.com <name>`) rather than a local resolver.

`local.record_ttl` is 300, chosen for fast iteration during setup. Raise it to
3600 now that records are stable.

AAAA values carry a `1` suffix (`${...v6.ip_address}1`). An IPv6 Primary IP is a
/64 and `ip_address` returns the network base, which is not a host and will not
answer. The host is `…::1`.

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

## Adding a site

Never a new server. Two files change:

1. **`dns.tf`** — add the subdomain to `local.web_records`, then `terraform apply`.
2. **`./Caddyfile`** — add a site block: `root`+`file_server` for static,
   `reverse_proxy localhost:PORT` for a container. Then `./deploy.sh`.

**Order matters.** DNS must resolve to this server *before* the hostname appears
in the Caddyfile. Caddy requests a certificate the moment it reloads, using an
HTTP-01 challenge that requires working DNS, and Let's Encrypt rate-limits failed
validations to **5 per hostname per hour**. Confirm with `dig +short <name> A`
before deploying. This is the one mistake here that costs real time.

Caddy provisions and renews Let's Encrypt certificates automatically. There is no
certbot and no renewal cron.

**`./Caddyfile` in this repo is the source of truth.** `deploy.sh` rsyncs it,
validates it on the server, then installs and reloads — so a syntax error fails
the deploy instead of taking sites down. cloud-init injects this same file via
`templatefile` on first boot, which is what keeps a rebuilt server current
rather than pinned to whatever routing existed when the template was written.

Never hand-edit `/etc/caddy/Caddyfile` on the server: the next `deploy.sh`
overwrites it, and the change exists nowhere else.
