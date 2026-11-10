# settings/pro.yaml: the hardened shape an audit samples. A test cannot read
# the resources inside a module of the stack, so pro_cloud_sql.tftest.hcl plans
# the Cloud SQL module itself with the pro instance settings.

mock_provider "google" {}
mock_provider "google" {
  alias = "unlabelled"
}
mock_provider "google-beta" {}
mock_provider "random" {}
mock_provider "time" {}
mock_provider "sops" {}
mock_provider "archive" {}
mock_provider "oci" {}

variables {
  settings_workspace = "pro"
}

run "pro_shape_is_hardened" {
  command = plan

  # The override warns on purpose outside terraform test.
  expect_failures = [check.settings_workspace_unset]

  assert {
    condition     = local.workspace == "pro" && local.settings.project.id == "example-app-pro"
    error_message = "settings_workspace = pro must read settings/pro.yaml."
  }

  assert {
    condition     = length(local.service_deletion_protection) > 0 && alltrue(values(local.service_deletion_protection))
    error_message = "Every pro Cloud Run service has deletion protection."
  }

  assert {
    condition = (
      local.private_service_access_needed
      && length(module.network) == 1
      && keys(module.network[0].services_ip_range_names) == ["private"]
      && local.services_ip_ranges.private.address == "10.21.0.0" && local.services_ip_ranges.private.prefix_length == 16
    )
    error_message = "pro reserves its Private Service Access range for the private Cloud SQL and Memorystore (pro_network.tftest.hcl checks the connection)."
  }

  assert {
    condition = length(google_redis_instance.redis_instances) > 0 && alltrue([
      for instance in values(google_redis_instance.redis_instances) : instance.deletion_protection
    ])
    error_message = "Every pro Memorystore instance has deletion protection."
  }

  assert {
    condition = length(module.cloud_sql) > 0 && alltrue([
      for db in values(local.settings.database) :
      db.sql.availability == "REGIONAL" && db.sql.deletion_protection && db.sql.backup.point_in_time_recovery_enabled
    ])
    error_message = "Every pro Cloud SQL instance is regional, protected and has point-in-time recovery."
  }

  assert {
    condition = (
      length(google_logging_project_bucket_config.audit_archive) == 1
      && google_logging_project_bucket_config.audit_archive[0].locked == true
      && google_logging_project_bucket_config.audit_archive[0].retention_days >= 365
      && length(google_logging_project_sink.audit_archive) == 1
    )
    error_message = "pro archives the audit logs in a locked bucket for at least 365 days."
  }

  assert {
    condition     = google_logging_project_bucket_config.default.retention_days == 90
    error_message = "pro keeps 90 days in _Default."
  }

  assert {
    condition = (
      length(google_binary_authorization_policy.policy) == 1
      && google_binary_authorization_policy.policy[0].default_admission_rule[0].enforcement_mode == "ENFORCED_BLOCK_AND_AUDIT_LOG"
      && google_binary_authorization_policy.policy[0].default_admission_rule[0].evaluation_mode == "REQUIRE_ATTESTATION"
    )
    error_message = "pro enforces Binary Authorization with a required attestation."
  }

  assert {
    condition = alltrue([
      for name in ["iam_policy_change", "service_account_key_created", "firewall_change", "audit_config_change", "custom_role_change", "sql_instance_change", "bucket_iam_change"] :
      contains(keys(google_monitoring_alert_policy.log_alerts), name)
    ])
    error_message = "pro has every log-based alert preset."
  }

  assert {
    condition     = contains(keys(google_monitoring_alert_policy.log_alerts), "secret_access") && length(google_monitoring_uptime_check_config.uptime) > 0
    error_message = "pro alerts on unexpected secret reads and probes the public domain."
  }

  assert {
    condition = (
      local.lb_enabled
      && length(google_compute_url_map.load_balancer) == 1
      && length(google_compute_security_policy.cloud_armor_waf) == 1
      && length(google_project_service_identity.iap_sa) == 1
    )
    error_message = "pro keeps the load balancer, Cloud Armor and IAP (positive control for the dev check)."
  }
}
