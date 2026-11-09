locals {
  enable_binary_auth = try(local.settings.binary_authorization.enabled, false)
}

resource "google_binary_authorization_policy" "policy" {
  count   = local.enable_binary_auth ? 1 : 0
  project = local.settings.project.id

  global_policy_evaluation_mode = "ENABLE"


  default_admission_rule {
    evaluation_mode  = "ALWAYS_ALLOW"
    enforcement_mode = "DRYRUN_AUDIT_LOG_ONLY"
  }


  admission_whitelist_patterns {
    name_pattern = "gcr.io/google_containers/*"
  }
  admission_whitelist_patterns {
    name_pattern = "gcr.io/google-containers/*"
  }
  admission_whitelist_patterns {
    name_pattern = "gcr.io/cloud-builders/*"
  }
  admission_whitelist_patterns {
    name_pattern = "us-docker.pkg.dev/cloudrun/container/*"
  }
  admission_whitelist_patterns {
    name_pattern = "gcr.io/gae-runtimes/*"
  }
  depends_on = [
    google_project_service.enabled_apis
  ]
}
