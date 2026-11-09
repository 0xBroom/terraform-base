# Firewall Rules

# IAP SSH Access Rule
resource "google_compute_firewall" "allow_iap_ssh" {
  name    = format("%s-allow-iap-ssh", local.base_name)
  network = module.network.network_name
  project = local.settings.project.id

  description = "Allow SSH access from Google Cloud IAP"
  direction   = "INGRESS"
  priority    = 1000

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = ["35.235.240.0/20"]
  target_tags   = []

  log_config {
    metadata = "INCLUDE_ALL_METADATA"
  }
}

# Internal VPC Communication Rule
resource "google_compute_firewall" "allow_internal_vpc" {
  name    = format("%s-allow-internal-vpc", local.base_name)
  network = module.network.network_name
  project = local.settings.project.id

  description = "Allow internal communication within VPC subnets"
  direction   = "INGRESS"
  priority    = 1000

  allow {
    protocol = "tcp"
  }

  allow {
    protocol = "udp"
  }

  allow {
    protocol = "icmp"
  }

  source_ranges = [
    "10.10.1.0/24", # Services subnet
    "10.20.0.0/24", # Database subnet range
    "10.20.1.0/24"  # Redis subnet range
  ]
  target_tags = []

  log_config {
    metadata = "INCLUDE_ALL_METADATA"
  }
}

# HTTP Ingress Rule
resource "google_compute_firewall" "allow_http" {
  name    = format("%s-vpc-allow-http", local.base_name)
  network = module.network.network_name
  project = local.settings.project.id

  description = "Allow HTTP traffic from internet"
  direction   = "INGRESS"
  priority    = 1000

  allow {
    protocol = "tcp"
    ports    = ["80"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["http-server"]

  log_config {
    metadata = "INCLUDE_ALL_METADATA"
  }
}

# HTTPS Ingress Rule
resource "google_compute_firewall" "allow_https" {
  name    = format("%s-vpc-allow-https", local.base_name)
  network = module.network.network_name
  project = local.settings.project.id

  description = "Allow HTTPS traffic from internet"
  direction   = "INGRESS"
  priority    = 1000

  allow {
    protocol = "tcp"
    ports    = ["443"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["httpsserver"]

  log_config {
    metadata = "INCLUDE_ALL_METADATA"
  }
} 