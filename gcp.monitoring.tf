# Log-based alert policies on Admin Activity audit logs, driven by
# settings.monitoring.log_alerts. Without the key nothing is created.
#
# Each entry of log_alerts is either a preset (a key of
# local.log_alert_presets, with no filter) or a custom alert (any key, with its
# own filter). Every policy notifies the security alerts channel, once per
# matching entry, with the principal and the method in the incident.
#
# The basic security module already counts some of these events in metric
# threshold policies (firewall, custom roles, audit config, Cloud SQL, bucket
# IAM). Those aggregate over ten minutes, cannot skip the identity that runs
# Terraform and say nothing about who made the change. The presets of the same
# name are the per-event version; project IAM changes beyond roles/owner and
# service account keys are only covered here.

locals {
  log_alert_activity = "log_id(\"cloudaudit.googleapis.com/activity\")"

  log_alert_presets = {
    iam_policy_change = {
      severity    = "WARNING"
      description = "The IAM policy of the project changed."
      filter      = "${local.log_alert_activity} AND resource.type=\"project\" AND protoPayload.methodName=\"SetIamPolicy\""
    }
    service_account_key_created = {
      severity    = "ERROR"
      description = "A service account key was created or uploaded. Keys are long-lived credentials."
      filter      = "${local.log_alert_activity} AND protoPayload.methodName=(\"google.iam.admin.v1.CreateServiceAccountKey\" OR \"google.iam.admin.v1.UploadServiceAccountKey\")"
    }
    firewall_change = {
      severity    = "WARNING"
      description = "A VPC firewall rule was created, changed or deleted."
      filter      = "${local.log_alert_activity} AND resource.type=\"gce_firewall_rule\" AND protoPayload.methodName:(\"compute.firewalls.insert\" OR \"compute.firewalls.patch\" OR \"compute.firewalls.update\" OR \"compute.firewalls.delete\")"
    }
    audit_config_change = {
      severity    = "ERROR"
      description = "The audit logging configuration of the project changed."
      filter      = "${local.log_alert_activity} AND protoPayload.methodName=\"SetIamPolicy\" AND protoPayload.serviceData.policyDelta.auditConfigDeltas:*"
    }
    custom_role_change = {
      severity    = "WARNING"
      description = "A custom IAM role was created, changed, deleted or restored."
      filter      = "${local.log_alert_activity} AND resource.type=\"iam_role\" AND protoPayload.methodName=(\"google.iam.admin.v1.CreateRole\" OR \"google.iam.admin.v1.UpdateRole\" OR \"google.iam.admin.v1.DeleteRole\" OR \"google.iam.admin.v1.UndeleteRole\")"
    }
    sql_instance_change = {
      severity    = "WARNING"
      description = "A Cloud SQL instance was created, changed or deleted."
      filter      = "${local.log_alert_activity} AND protoPayload.methodName=(\"cloudsql.instances.create\" OR \"cloudsql.instances.update\" OR \"cloudsql.instances.delete\")"
    }
    bucket_iam_change = {
      severity    = "WARNING"
      description = "The IAM policy of a Cloud Storage bucket changed."
      filter      = "${local.log_alert_activity} AND resource.type=\"gcs_bucket\" AND protoPayload.methodName=\"storage.setIamPermissions\""
    }
  }

  log_alerts_settings           = try(local.settings.monitoring.log_alerts, {})
  log_alert_excluded_principals = try(local.settings.monitoring.excluded_principals, [])

  log_alerts = {
    for name, alert in local.log_alerts_settings : name => {
      filter      = try(alert.filter, local.log_alert_presets[name].filter, null)
      severity    = try(alert.severity, local.log_alert_presets[name].severity, "WARNING")
      description = try(alert.description, local.log_alert_presets[name].description, "Custom log-based alert ${name}.")
      rate_limit  = try(alert.notification_rate_limit, "300s")
      auto_close  = try(alert.auto_close, "1800s")
      excluded    = distinct(concat(local.log_alert_excluded_principals, try(alert.excluded_principals, [])))
    } if try(alert.enabled, true)
  }
}

resource "google_monitoring_alert_policy" "log_alerts" {
  for_each = local.log_alerts

  project      = local.settings.project.id
  display_name = "${local.base_name_medium}-log-${replace(each.key, "_", "-")}"
  combiner     = "OR"
  severity     = each.value.severity
  enabled      = true

  conditions {
    display_name = each.key

    condition_matched_log {
      filter = length(each.value.excluded) == 0 ? each.value.filter : format(
        "(%s) AND NOT protoPayload.authenticationInfo.principalEmail=(%s)",
        each.value.filter,
        join(" OR ", [for principal in each.value.excluded : "\"${principal}\""]),
      )

      label_extractors = {
        principal = "EXTRACT(protoPayload.authenticationInfo.principalEmail)"
        method    = "EXTRACT(protoPayload.methodName)"
        resource  = "EXTRACT(protoPayload.resourceName)"
      }
    }
  }

  # A log match policy is rejected without a notification rate limit.
  alert_strategy {
    auto_close = each.value.auto_close

    notification_rate_limit {
      period = each.value.rate_limit
    }
  }

  documentation {
    mime_type = "text/markdown"
    content   = "${each.value.description}\n\nPrincipal: $${log.extracted_label.principal}\n\nMethod: $${log.extracted_label.method}\n\nResource: $${log.extracted_label.resource}"
  }

  notification_channels = [google_monitoring_notification_channel.security_alerts.name]

  lifecycle {
    precondition {
      condition     = each.value.filter != null
      error_message = "monitoring.log_alerts.${each.key} is not a preset (${join(", ", keys(local.log_alert_presets))}), so it needs a filter."
    }
  }

  depends_on = [google_project_service.enabled_apis]
}
