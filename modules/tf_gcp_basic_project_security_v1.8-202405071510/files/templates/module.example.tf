module "basic_security" {
  source = "./modules/tf_gcp_basic_project_security_v1.8-202405071510"

  base_name      = local.settings.project_name
  gcp_project_id = local.settings.project_id

  # Audit logging is optional
  audit_logging = {
    admin_read = true
    data_read  = false
    data_write = false
  }

  notification_channels = [
    "notification_channel"
  ]
}

