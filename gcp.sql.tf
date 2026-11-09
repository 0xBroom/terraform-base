
locals {
  # Extract service names dynamically from app configuration
  service_names = keys(local.app_services)

  schema = {
    # Database names for each service - dynamically generated from app services
    databases = [
      for service in local.service_names : "${service}-db"
    ]
    # Database users for each service - dynamically generated from app services
    users = [
      for service in local.service_names : { name = "${service}-app-user", host = "" }
    ]
  }
}

check "private_sql_needs_shared_vpc" {
  assert {
    condition = alltrue([
      for db in try(values(local.settings.database), []) :
      try(db.sql.ipv4_enabled, false) || local.network_enabled
    ])
    error_message = "A database with ipv4_enabled false needs network.services_cidr so it can take a private IP on the shared VPC."
  }
}

# Create Cloud SQL instances for each database configuration
module "cloud_sql" {
  source = "./modules/tf_gcp_cloudsql_v7.4-202506180832"

  # Loop through each database configuration in the sql section
  for_each = try(local.settings.database, {})

  gcp_project_id     = local.settings.project.id
  gcp_project_sys_id = local.settings.project_sys.id
  base_name          = "${local.base_name}-${each.value.name}" # Include database key in name
  region_name        = local.settings.region_name

  ## All the below options are optional and if not provided, the default settings will be used
  dbe                     = try(each.value.sql, null)         # Pass the specific database configuration
  databases               = try(local.schema.databases, null) # All services get databases in each instance
  users                   = try(local.schema.users, null)     # All service users in each instance
  backup_configuration    = try(each.value.sql.backup, null)
  maintenance_window      = try(each.value.sql.maintenance, null)
  deny_maintenance_period = try(each.value.sql.deny_maintenance_period, null)
  zones_name              = try(local.settings.zones_name, [])
  special_characters_pass = try(each.value.sql.special_password, null)
  secrets_locations       = [local.settings.region_name] # Use regional location for secrets
  net_id                  = try(each.value.sql.ipv4_enabled, false) ? null : try(module.network[0].network_id, null)
  insights_config = {
    query_insights_enabled  = false
    query_plans_per_minute  = 0
    query_string_length     = 2048
    record_application_tags = false
    record_client_address   = false
  }
  monitoring                        = try(each.value.sql.monitoring, {})
  flags                             = try(each.value.sql.flags, {})
  notification_channels             = [google_monitoring_notification_channel.security_alerts.id]
  notification_channels_not_on_call = [google_monitoring_notification_channel.security_alerts.id]

  depends_on = [module.network]
} 