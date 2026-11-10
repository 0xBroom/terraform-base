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

  # Admin activity is the trail you need after an IAM or firewall change.
  # Data access logs are expensive, so they stay off unless a workspace asks.
  audit_logging = {
    admin_read = try(local.settings.security.audit_logging.admin_read, true)
    data_read  = try(local.settings.security.audit_logging.data_read, false)
    data_write = try(local.settings.security.audit_logging.data_write, false)
  }

  notification_channels = [
    google_monitoring_notification_channel.security_alerts.name
  ]
}

# Artifact Registry automatic scanning. This is the Container Scanning API,
# not a registry product that has to be installed beside the project.
resource "google_project_service" "container_scanning" {
  count   = try(local.settings.security.artifact_scanning, false) ? 1 : 0
  project = local.settings.project.id
  service = "containerscanning.googleapis.com"

  disable_on_destroy = false

  depends_on = [google_project_service.enabled_apis]
}
