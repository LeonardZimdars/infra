# DNS lives in the official hetznercloud/hcloud provider (hcloud_zone /
# hcloud_zone_rrset), using the same token as everything else — Hetzner merged
# the old dns.hetzner.com product and its separate API into the main console.
# The retired endpoint now 301s; api.hetzner.cloud/v1/zones is authoritative.
#
# Everything here is inert until var.domain is set. Set it, apply, then read
# `terraform output nameservers` and enter those at your registrar.

locals {
  dns_enabled = var.domain != ""

  # Short TTL while setting up, so mistakes are cheap to correct. Raise to 3600
  # once the records are settled.
  record_ttl = 300

  # Both apex and www, on v4 and v6. Note the "1" suffix on the v6 value: the
  # Primary IP is a /64 network and its base address is not a host.
  #
  # `values` is a LIST because an RRset is keyed on (name, type) and owns every
  # record under it. Anything sharing a name and type must share one entry here
  # — see the apex TXT below, where a second entry would not add a record, it
  # would fight the first one.
  web_records = local.dns_enabled ? {
    "apex-a"    = { name = "@", type = "A", values = [hcloud_primary_ip.v4.ip_address] },
    "apex-aaaa" = { name = "@", type = "AAAA", values = ["${hcloud_primary_ip.v6.ip_address}1"] },
    "www-a"     = { name = "www", type = "A", values = [hcloud_primary_ip.v4.ip_address] },
    "www-aaaa"  = { name = "www", type = "AAAA", values = ["${hcloud_primary_ip.v6.ip_address}1"] },

    # Apex TXT. Every apex TXT record lives in this one list: domain
    # verifications, and SPF when mail is set up. Adding a separate rrset for
    # "@"/TXT would not coexist with this one — the last apply would win and
    # silently drop the other. Quoting is handled below.
    "txt" = { name = "@", type = "TXT", values = [
      "google-site-verification=MSkiNZv_Mh6uv0RXpIAUZpafDWiSAuuUkRGkkPNlbdo",
    ] },
  } : {}
}

resource "hcloud_zone" "main" {
  count = local.dns_enabled ? 1 : 0

  name = var.domain
  mode = "primary"
  ttl  = local.record_ttl
}

resource "hcloud_zone_rrset" "web" {
  for_each = local.web_records

  zone = one(hcloud_zone.main[*].id)
  name = each.value.name
  type = each.value.type
  ttl  = local.record_ttl

  records = [
    for v in each.value.values : {
      # The API rejects an unquoted TXT value outright:
      #   422 invalid_input — "TXT records must be fully escaped with double
      #   quotes" on rrsets[0].records[0].value
      # Quoting here rather than in each declaration means it cannot be
      # forgotten when SPF, DKIM or DMARC are added later.
      #
      # A value that already starts with a quote is passed through untouched,
      # so a DKIM key pre-split into several quoted strings — required above
      # 255 characters, e.g. "v=DKIM1;..." "…continued" — still works.
      value = each.value.type == "TXT" && !startswith(v, "\"") ? "\"${v}\"" : v
    }
  ]
}

# Reverse DNS. Cosmetic for a website — it makes traceroutes and logs readable.
# Only matters functionally if this host ever sends mail.
resource "hcloud_rdns" "v4" {
  count = local.dns_enabled ? 1 : 0

  server_id  = hcloud_server.web.id
  ip_address = hcloud_primary_ip.v4.ip_address
  dns_ptr    = var.domain
}
