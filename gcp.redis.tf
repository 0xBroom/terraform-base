# ===================================================================
# REDIS INSTANCES CONFIGURATION
# ===================================================================
# This file creates Redis instances based on settings configuration
# following the same pattern as Cloud SQL module usage

# Create Redis instances for each configuration in settings
resource "google_redis_instance" "redis_instances" {
  for_each = try(local.settings.redis, {})

  # Basic Configuration
  name        = "${local.base_name_medium}-${each.value.name}"
  project     = local.settings.project.id
  region      = local.settings.region_name
  location_id = local.settings.zones_name[0] # Use first zone from zones_name list

  # Memory and Performance
  memory_size_gb = each.value.memory_size_gb
  tier           = each.value.tier

  # Network Configuration - VPC Integration
  connect_mode       = each.value.connect_mode
  authorized_network = module.network.network_id
  reserved_ip_range  = try(each.value.reserved_ip_range, null)

  # Security Configuration
  auth_enabled            = try(each.value.auth_enabled, true)
  transit_encryption_mode = try(each.value.transit_encryption_mode, "DISABLED")

  # Redis Configuration
  redis_version = try(each.value.redis_version, "REDIS_7_0")
  display_name  = "${local.base_name_medium}-${each.value.name}"

  # Labels for resource management
  labels = merge(
    try(each.value.labels, {}),
    {
      workspace  = terraform.workspace
      client     = local.settings.client.name
      managed_by = "terraform"
    }
  )

  # Redis configuration parameters (optional)
  redis_configs = try(each.value.redis_configs, {})

  # Maintenance policy (optional)
  dynamic "maintenance_policy" {
    for_each = try(each.value.maintenance_policy, null) != null ? [each.value.maintenance_policy] : []
    content {
      weekly_maintenance_window {
        day = maintenance_policy.value.day
        start_time {
          hours   = maintenance_policy.value.start_time.hours
          minutes = try(maintenance_policy.value.start_time.minutes, 0)
          seconds = try(maintenance_policy.value.start_time.seconds, 0)
          nanos   = try(maintenance_policy.value.start_time.nanos, 0)
        }
      }
    }
  }

  # Dependencies
  depends_on = [
    google_project_service.enabled_apis,
    module.network
  ]

  lifecycle {
    prevent_destroy = true # Prevent accidental deletion
  }
}