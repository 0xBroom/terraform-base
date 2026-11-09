# ===================================================================
# PRIVATE SERVICE CONNECT CONFIGURATION
# ===================================================================
# This file configures Private Service Connect (PSC) to enable Cloud Run services
# to securely connect to an Elastic Cloud deployment without exposing traffic
# to the public internet. The setup creates:
#
# 1. A Private Service Connect endpoint that routes to Elastic Cloud's service attachment
# 2. A DNS zone and record for resolving the Elastic Cloud domain to the private IP
#
# Cloud Run services can then connect to Elastic using the private endpoint address

locals {
  # Enable Elastic PSC resources only if configured in YAML settings
  # Default to false if not present
  enable_elastic_psc = try(local.settings.elastic.psc, false)
}

# Create a Private Service Connect endpoint
resource "google_compute_address" "elastic_psc_address" {
  count = local.enable_elastic_psc ? 1 : 0

  name         = "${local.base_name_medium}-elastic-psc-address"
  region       = local.settings.region_name
  subnetwork   = module.network.subnetworks["services"].self_link
  address_type = "INTERNAL"
  purpose      = "GCE_ENDPOINT"
  description  = "Private Service Connect IP address for Elastic Cloud"

  labels = {
    managed_by = "terraform"
  }
}

resource "google_compute_forwarding_rule" "elastic_psc_endpoint" {
  count = local.enable_elastic_psc ? 1 : 0

  name                  = "${local.base_name_medium}-elastic-psc-endpoint"
  region                = local.settings.region_name
  network               = module.network.network_id
  ip_address            = google_compute_address.elastic_psc_address[0].id
  target                = "projects/cloud-production-168820/regions/europe-west1/serviceAttachments/proxy-psc-production-europe-west1-v1-attachment"
  load_balancing_scheme = ""
  description           = "Private Service Connect endpoint to Elastic Cloud deployment"

  labels = {
    managed_by = "terraform"
  }
}

# Create a private DNS zone for the Elastic Cloud domain
resource "google_dns_managed_zone" "elastic_private_zone" {
  count = local.enable_elastic_psc ? 1 : 0

  name        = "${local.base_name_medium}-elastic-dns-zone"
  dns_name    = "cloud.es.io."
  description = "Private DNS zone for Elastic Cloud domain"

  labels = {
    managed_by = "terraform"
  }

  visibility = "private"

  private_visibility_config {
    networks {
      network_url = module.network.network_id
    }
  }
}

# Create DNS record pointing to PSC endpoint IP address
resource "google_dns_record_set" "elastic_dns_record" {
  count = local.enable_elastic_psc ? 1 : 0

  name         = "cloud.es.io."
  managed_zone = google_dns_managed_zone.elastic_private_zone[0].name
  type         = "A"
  ttl          = 300
  rrdatas      = [google_compute_address.elastic_psc_address[0].address]
}

# Create DNS record for wildcard subdomains
resource "google_dns_record_set" "elastic_wildcard_dns_record" {
  count = local.enable_elastic_psc ? 1 : 0

  name         = "*.cloud.es.io."
  managed_zone = google_dns_managed_zone.elastic_private_zone[0].name
  type         = "A"
  ttl          = 300
  rrdatas      = [google_compute_address.elastic_psc_address[0].address]
} 