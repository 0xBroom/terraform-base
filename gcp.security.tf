# Notification Channel for Security Alerts
resource "google_monitoring_notification_channel" "security_alerts" {
  display_name = "${local.base_name}-security-alerts"
  type         = "email"

  labels = {
    email_address = try(local.settings.security.alerts_email, "")
  }

  description = "Email notification channel for security alerts in ${local.base_name} project"

  # Keep enabled: every alert policy in the repo (security, Cloud Run, LB, NAT)
  # points here, so a disabled channel silently mutes all of them.
  enabled = true

  lifecycle {
    # merge() in locals.tf is shallow: a workspace that sets any security key
    # replaces the whole map and must repeat alerts_email.
    precondition {
      condition     = can(regex("^[^@[:space:]]+@[^@[:space:]]+\\.[^@[:space:]]+$", try(local.settings.security.alerts_email, "")))
      error_message = "Set security.alerts_email to a valid address in settings/default.yaml or the workspace file. A workspace that declares security: must repeat it, because the merge is shallow."
    }
  }
}

module "basic_security" {
  source = "./modules/gcp_basic_project_security_v1.8"

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

# Data Access logs for Secret Manager only, so the secret_access alert in
# gcp.monitoring.tf has entries to match. The module above owns the
# allServices audit config; a config per service is a separate entry in the
# project IAM policy, and no resource here manages the policy as a whole.
resource "google_project_iam_audit_config" "secret_manager_data_read" {
  count   = local.secret_access_enabled ? 1 : 0
  project = local.settings.project.id
  service = "secretmanager.googleapis.com"

  audit_log_config {
    log_type = "DATA_READ"
  }
}

# security.artifact_scanning turns on Artifact Registry automatic scanning through
# the Container Scanning API (feature_apis in gcp.enabled.apis.tf). It is not a
# registry product that has to be installed beside the project.
