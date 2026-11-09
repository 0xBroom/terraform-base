locals {
  enable_binary_auth  = try(local.settings.binary_authorization.enabled, false)
  binauth_evaluation  = try(local.settings.binary_authorization.evaluation_mode, "REQUIRE_ATTESTATION")
  binauth_enforcement = try(local.settings.binary_authorization.enforcement_mode, "DRYRUN_AUDIT_LOG_ONLY")
}

resource "google_project_service" "binary_authorization" {
  count   = local.enable_binary_auth ? 1 : 0
  project = local.settings.project.id
  service = "binaryauthorization.googleapis.com"

  disable_on_destroy = false

  depends_on = [google_project_service.enabled_apis]
}

resource "google_project_service" "container_analysis" {
  count   = local.enable_binary_auth ? 1 : 0
  project = local.settings.project.id
  service = "containeranalysis.googleapis.com"

  disable_on_destroy = false

  depends_on = [google_project_service.enabled_apis]
}

resource "google_container_analysis_note" "binauth" {
  count   = local.enable_binary_auth ? 1 : 0
  project = local.settings.project.id
  name    = "${local.base_name_medium}-attestor"

  attestation_authority {
    hint {
      human_readable_name = "${local.base_name_medium} attestor"
    }
  }

  depends_on = [google_project_service.container_analysis]
}

resource "google_binary_authorization_attestor" "binauth" {
  count   = local.enable_binary_auth ? 1 : 0
  project = local.settings.project.id
  name    = "${local.base_name_medium}-attestor"

  attestation_authority_note {
    note_reference = google_container_analysis_note.binauth[0].id
  }

  depends_on = [google_project_service.container_analysis]
}

resource "google_binary_authorization_policy" "policy" {
  count   = local.enable_binary_auth ? 1 : 0
  project = local.settings.project.id

  global_policy_evaluation_mode = "ENABLE"

  default_admission_rule {
    evaluation_mode         = local.binauth_evaluation
    enforcement_mode        = local.binauth_enforcement
    require_attestations_by = google_binary_authorization_attestor.binauth[*].name
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
    google_project_service.binary_authorization,
    google_binary_authorization_attestor.binauth,
  ]
}
