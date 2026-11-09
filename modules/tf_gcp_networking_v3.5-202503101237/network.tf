resource "google_compute_network" "net" {
  project                 = var.gcp_project_id
  name                    = local.m_base_name
  auto_create_subnetworks = false
  depends_on              = [google_project_service.servicenetworking]
}

resource "google_compute_subnetwork" "subnet" {
  for_each                 = var.subnets
  project                  = var.gcp_project_id
  name                     = format("%s%s%s", local.m_base_name, each.value.single_dash ? "-" : "--", each.key)
  private_ip_google_access = each.value.private_google_access
  network                  = google_compute_network.net.self_link
  ip_cidr_range            = each.value.cidr
  region                   = each.value.region
  purpose                  = each.value.purpose
  role                     = each.value.role
}


