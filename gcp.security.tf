# Notification Channel for Security Alerts
resource "google_monitoring_notification_channel" "security_alerts" {
  display_name = "${local.base_name}-security-alerts"
  type         = "email"

  labels = {
    email_address = local.settings.security.alerts_email
  }

  description = "Email notification channel for security alerts in ${local.base_name} project"

  # Keep enabled: every alert policy in the repo (security, Cloud Run, LB, NAT)
  # points here, so a disabled channel silently mutes all of them.
  enabled = true
}

module "basic_security" {
  source = "./modules/tf_gcp_basic_project_security_v1.8-202405071510"

  base_name      = local.base_name
  gcp_project_id = local.settings.project.id

  # Audit logging is optional
  audit_logging = {
    admin_read = false
    data_read  = false
    data_write = false
  }

  notification_channels = [
    google_monitoring_notification_channel.security_alerts.name
  ]
}
