output "network_self_link" {
  description = "Network link"
  value       = google_compute_network.net.self_link
}

output "ip_nat" {
  description = "Cloud NAT IPs"
  value       = [for value in google_compute_address.nat_ip : value.address]
}

output "network_id" {
  description = "Network id"
  value       = google_compute_network.net.id
}

output "network_name" {
  description = "Network name"
  value       = google_compute_network.net.name
}

output "subnetworks" {
  description = "Subnetworks data"
  value       = google_compute_subnetwork.subnet
}

output "vpc_connectors" {
  description = "VPC connectors data"
  value       = google_vpc_access_connector.serverless_vpc_connector
}
