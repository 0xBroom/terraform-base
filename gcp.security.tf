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
    # A module block takes no precondition, so the metric_alerts shape is
    # checked here, on the channel those alerts notify.
    precondition {
      condition = can(tobool(local.security_metric_alerts_setting)) || (
        can(keys(local.security_metric_alerts_setting))
        && length(setsubtract(try(keys(local.security_metric_alerts_setting), []), local.security_metric_alert_families)) == 0
        && alltrue([for value in try(values(local.security_metric_alerts_setting), []) : can(tobool(value))])
      )
      error_message = "security.metric_alerts is true, false or a map of ${join(", ", local.security_metric_alert_families)} to true or false."
    }
  }
}

# security.metric_alerts switches the threshold alerts of the basic security
# module: true or false for all of them, or a map of family => bool where an
# omitted family stays on. Five families report the same events as a
# monitoring.log_alerts preset, which also names the principal and skips the
# Terraform identity; pro turns those five off. Network, routes and owner have
# no preset.
locals {
  security_metric_alert_families = ["audit_config", "cloud_sql", "custom_roles", "firewall", "network", "owner", "routes", "storage_permissions"]

  security_metric_alert_presets = {
    audit_config        = "audit_config_change"
    cloud_sql           = "sql_instance_change"
    custom_roles        = "custom_role_change"
    firewall            = "firewall_change"
    storage_permissions = "bucket_iam_change"
  }

  security_metric_alerts_setting = try(local.settings.security.metric_alerts, true)

  security_metric_alerts = {
    for family in local.security_metric_alert_families : family => try(
      tobool(local.security_metric_alerts_setting),
      tobool(local.security_metric_alerts_setting[family]),
      true,
    )
  }

  # Families switched off with no log alert on the same events left.
  security_metric_alerts_uncovered = [
    for family, enabled in local.security_metric_alerts : family
    if !enabled && !contains(keys(local.log_alerts), try(local.security_metric_alert_presets[family], ""))
  ]
}

check "security_metric_alerts_covered" {
  assert {
    condition     = length(local.security_metric_alerts_uncovered) == 0
    error_message = "security.metric_alerts turns off ${join(", ", local.security_metric_alerts_uncovered)} with no monitoring.log_alerts preset on the same events, so nothing alerts on them."
  }
}

module "basic_security" {
  source = "./modules/gcp_basic_project_security_v1.9"

  base_name      = local.base_name
  gcp_project_id = local.settings.project.id

  # Admin activity is the trail you need after an IAM or firewall change.
  # Data access logs are expensive, so they stay off unless a workspace asks.
  audit_logging = {
    admin_read = try(local.settings.security.audit_logging.admin_read, true)
    data_read  = try(local.settings.security.audit_logging.data_read, false)
    data_write = try(local.settings.security.audit_logging.data_write, false)
  }

  metric_alerts = local.security_metric_alerts

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
