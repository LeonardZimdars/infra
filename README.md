# infra

Terraform for the single Hetzner Cloud VPS that serves
**[leonardzimdars.com](https://leonardzimdars.com)** — and whatever I put next to
it. One server, one Caddy config, sites added by hostname.

```
                         leonardzimdars.com
                                 │
                    Hetzner DNS  ·  zone + records in dns.tf
                                 │
                    A / AAAA  →  Primary IPs (stable across rebuilds)
                                 │
   ┌─────────────────────────────▼──────────────────────────────┐
   │  Hetzner VPS · cx23 · Falkenstein · Ubuntu 24.04           │
   │                                                            │
   │  Caddy  :80 :443            automatic Let's Encrypt, HTTP/3│
   │    └─ leonardzimdars.com  → /var/www/site                  │
   │       www.…               → 301 to apex                    │
   │                                                            │
   │  Docker                     for whatever comes next        │
   │  unattended-upgrades        security patches + auto-reboot │
   │  fail2ban, key-only SSH, default-deny firewall             │
   └────────────────────────────────────────────────────────────┘
```

Cost is about €7/month. The machine is reproducible from an empty Hetzner
account in roughly three minutes.

## What Terraform owns

The SSH key, firewall, Primary IPs, server, DNS zone, records, and reverse DNS.

It does **not** own the Caddy config, the TLS certificates, or the site content.
Those live on the server: Caddy obtains and renews its own certificates, routing
ships with `./deploy.sh`, and page content comes from a separate repository. The
boundary is deliberate — a routing change should not rebuild a machine, and a
content change should not touch either.

## Layout

| File | |
|---|---|
| `main.tf` | SSH key, firewall, Primary IPs, server |
| `dns.tf` | zone, A/AAAA records, reverse DNS |
| `variables.tf` | every input, all with defaults except the API token |
| `outputs.tf` | IPs, SSH command, nameservers for the registrar |
| `cloud-init.yaml.tftpl` | first-boot bootstrap — users, hardening, packages |
| `Caddyfile` | routing. Source of truth, not a copy of what's on the server |
| `deploy.sh` | validates the Caddyfile **on the server**, then installs and reloads |
| `CLAUDE.md` | the long-form notes, including what broke and why |

## Use

```sh
terraform init
terraform plan
terraform apply
./deploy.sh                              # push routing changes, no rebuild
terraform apply -replace=hcloud_server.web   # deliberate rebuild
```

State lives in HCP Terraform. The API token comes from a gitignored
`terraform.tfvars`; nothing secret is in this repository, and nothing secret has
ever been committed.

## Decisions worth a look

**Primary IPs are separate resources.** If the server allocated its own address,
every rebuild would issue a new one and silently break DNS. Declared separately
with `auto_delete = false`, the addresses outlive the machine — so a rebuild is a
routine operation rather than a DNS incident.

**`ignore_changes = [user_data]` on the server.** The bootstrap template
interpolates `./Caddyfile`, so without it every routing edit would change the
`user_data` hash and destroy the machine — a website change deleting the web
server. Hetzner only reads `user_data` at first boot anyway, so a diff there could
never mean anything except "rebuild".

**One Caddyfile, two consumers.** cloud-init bakes it in at build time and
`deploy.sh` pushes it at runtime. That is what stops a rebuilt server coming back
with whatever routing existed the day the template was written.

**Adding a site is a DNS record and a Caddyfile block.** Never another server.
Capacity is not the constraint here and never will be.

## The interesting part is `CLAUDE.md`

The Terraform is ordinary. The notes are where the actual work is — the failure
modes that cost time and are not obvious from the code:

- a `write_files` entry pre-creating a path that a package ships as a conffile,
  so `dpkg` prompted, found no stdin, aborted mid-configure, and left no `caddy`
  user and a service dead at `217/USER`
- Hetzner reporting a server type as `supported` at a location but not
  `available`, which only surfaces at apply time as `resource_unavailable`
- an RRset owning *every* record under a `(name, type)` pair, so a second one for
  the same pair does not add a record — it fights the first, and the last apply
  wins silently
- an IPv6 Primary IP being a `/64` whose base address is not a host, so the
  obvious AAAA value points at nothing

## Not here, on purpose

No Kubernetes, no config management, no CI. One box serving static sites does not
need an orchestrator, and Ansible earns its place at the second server or the
first piece of config that drifts. Adding either now would be resume-driven rather
than useful.

---

Built with [Claude Code](https://claude.com/claude-code).
