# ===================================================================
# CLOUD DNS MANAGED ZONES
# ===================================================================
# DNS zones hosted in this project. Driven by `dns_zones` in
# settings/${workspace}.yaml, like every other resource here. A zone with
# `visibility: private` is attached to the shared VPC, so it needs
# network.services_cidr.
#
# A zone created here is NOT reachable until its parent domain delegates to it:
# take the name servers from the `dns_zone_name_servers` output and create the
# matching NS records at the registrar. Until that is done the zone exists,
# answers nothing, and costs the base zone fee.
#
# IMPORT AN EXISTING ZONE:
#   terraform import 'google_dns_managed_zone.zone["<key>"]' \
#     projects/<project>/managedZones/<zone-name>

locals {
  dns_zones = try(local.settings.dns_zones, {})
}

resource "google_dns_managed_zone" "zone" {
  for_each = local.dns_zones

  name        = each.key
  project     = local.settings.project.id
  description = try(each.value.description, "Managed by Terraform")

  # Cloud DNS requires the trailing dot. Accept the YAML with or without it
  # rather than making every future entry remember.
  dns_name = "${trimsuffix(each.value.dns_name, ".")}."

  visibility = try(each.value.visibility, "public")

  # Cloud DNS refuses a private zone with no network. The shared VPC is the
  # only network this template creates.
  dynamic "private_visibility_config" {
    for_each = try(each.value.visibility, "public") == "private" ? [1] : []
    content {
      networks {
        network_url = module.network[0].network_id
      }
    }
  }

  # DNSSEC is for public zones only.
  dynamic "dnssec_config" {
    for_each = try(each.value.visibility, "public") == "private" ? [] : [1]
    content {
      state = try(each.value.dnssec, "off")
    }
  }

  lifecycle {
    precondition {
      condition     = contains(["public", "private"], try(each.value.visibility, "public"))
      error_message = "dns_zones.${each.key}.visibility must be public or private."
    }
    precondition {
      condition     = try(each.value.visibility, "public") != "private" || local.network_enabled
      error_message = "dns_zones.${each.key} is private and needs network.services_cidr: a private zone is attached to the shared VPC."
    }
  }
}

# ===================================================================
# RECORDS
# ===================================================================
# Records live under their zone in settings, so a zone and its contents are read
# and reviewed as one thing.
#
# NOT DECLARED HERE, ON PURPOSE: the zone's own apex NS and SOA. Cloud DNS creates
# and owns both. Declaring apex NS from a registrar export would point a freshly
# migrated zone straight back at the provider it was migrated away from.

locals {
  dns_records = merge([
    for zone_key, zone in local.dns_zones : {
      # Key on name+type because that is exactly what an rrset is: one resource per
      # (name, type), holding every value for it.
      for r in try(zone.records, []) :
      "${zone_key}|${lower(r.name)}|${upper(r.type)}" => {
        zone = zone_key
        # Cloud DNS insists on the trailing dot. Accept the export's form rather
        # than making every future entry remember.
        name    = "${trimsuffix(r.name, ".")}."
        type    = upper(r.type)
        ttl     = try(r.ttl, try(zone.default_ttl, 300))
        rrdatas = r.values
      }
    }
  ]...)
}

resource "google_dns_record_set" "record" {
  for_each = local.dns_records

  project      = local.settings.project.id
  managed_zone = google_dns_managed_zone.zone[each.value.zone].name
  name         = each.value.name
  type         = each.value.type
  ttl          = each.value.ttl
  rrdatas      = each.value.rrdatas
}

# The four name servers Google assigns. They are the whole point of creating the
# zone: without them nobody can perform the registrar-side delegation, and they
# are not predictable before the zone exists.
output "dns_zone_name_servers" {
  description = "Name servers per managed zone. Set these at the registrar of the parent domain."
  value       = { for k, z in google_dns_managed_zone.zone : k => z.name_servers }
}

# A migration is only safe if the new zone answers like the old one. This is the
# checklist to compare against the old zone before touching the delegation.
output "dns_record_names" {
  description = "Every name declared per zone. Compare with the old zone before switching name servers."
  value       = { for k, z in local.dns_zones : k => sort(distinct([for r in try(z.records, []) : r.name])) }
}
