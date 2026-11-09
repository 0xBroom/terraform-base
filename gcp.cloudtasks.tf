# ===================================================================
# CLOUD TASKS CONFIGURATION
# ===================================================================
# Manages Cloud Tasks queues and their IAM bindings using YAML config.
#
# Each queue entry supports:
#   - Queue creation with rate limits and retry config
#   - Enqueuer permissions for the service that creates tasks
#   - Run invoker permissions for OIDC-authenticated task dispatch
#   - Token creator permissions for the Cloud Tasks service agent
#
# YAML structure (in settings/{workspace}.yaml):
#   cloud_tasks:
#     <queue-key>:
#       custom_name: "queue-name"
#       location: "europe-west1"
#       max_concurrent: 1
#       max_rate: 5
#       max_retry_attempts: 3
#       max_retry_duration: "3600s"
#       min_backoff: "5s"
#       max_backoff: "300s"
#       target_service: "service-key"       # Cloud Run service invoked by tasks
#       enqueuer_service: "service-key"     # Service SA used as OIDC identity

locals {
  cloud_tasks_configs = try(local.settings.cloud_tasks, {})

  # Resolve SA emails for enqueuer services (the SA that creates tasks and
  # is referenced in the OIDC token for authenticated Cloud Run invocation)
  cloud_tasks_enqueuer_sa = {
    for key, config in local.cloud_tasks_configs : key => (
      try(local.app_services[config.enqueuer_service].cloudrun.external_sa, null) != null
      ? local.app_services[config.enqueuer_service].cloudrun.external_sa
      : format("%s-%s-sa@%s.iam.gserviceaccount.com",
        local.base_name,
        try(local.app_services[config.enqueuer_service].name, config.enqueuer_service),
        local.settings.project.id
      )
    )
    if try(config.enqueuer_service, null) != null
  }
}

# ===================================================================
# CLOUD TASKS QUEUES
# ===================================================================

resource "google_cloud_tasks_queue" "queues" {
  for_each = local.cloud_tasks_configs

  project  = local.settings.project.id
  name     = try(each.value.custom_name, format("%s-%s", local.base_name, each.key))
  location = try(each.value.location, local.settings.region_name)

  rate_limits {
    max_concurrent_dispatches = try(each.value.max_concurrent, 1)
    max_dispatches_per_second = try(each.value.max_rate, 5)
  }

  retry_config {
    max_attempts       = try(each.value.max_retry_attempts, 3)
    max_retry_duration = try(each.value.max_retry_duration, "3600s")
    min_backoff        = try(each.value.min_backoff, "5s")
    max_backoff        = try(each.value.max_backoff, "300s")
  }

  depends_on = [google_project_service.enabled_apis]
}

# ===================================================================
# IAM: ENQUEUER PERMISSIONS
# ===================================================================
# Grant the enqueuer service SA the ability to create tasks in the queue.

resource "google_project_iam_member" "cloud_tasks_enqueuer" {
  for_each = local.cloud_tasks_enqueuer_sa

  project = local.settings.project.id
  role    = "roles/cloudtasks.enqueuer"
  member  = "serviceAccount:${each.value}"

  depends_on = [module.cloud_run_services]
}

# ===================================================================
# IAM: CLOUD RUN INVOKER FOR OIDC DISPATCH
# ===================================================================
# The enqueuer SA is also used in the OIDC token when Cloud Tasks
# dispatches the HTTP request. It needs roles/run.invoker on the
# target Cloud Run service.

resource "google_cloud_run_service_iam_member" "cloud_tasks_run_invoker" {
  for_each = {
    for key, config in local.cloud_tasks_configs : key => config
    if try(config.target_service, null) != null && try(config.enqueuer_service, null) != null
  }

  project  = local.settings.project.id
  location = try(local.app_services[each.value.target_service].cloudrun.region, local.settings.region_name)
  service = (
    try(local.app_services[each.value.target_service].custom_name, null) != null
    ? local.app_services[each.value.target_service].custom_name
    : "${local.base_name}-${try(local.app_services[each.value.target_service].name, each.value.target_service)}"
  )
  role   = "roles/run.invoker"
  member = "serviceAccount:${local.cloud_tasks_enqueuer_sa[each.key]}"

  depends_on = [module.cloud_run_services]
}

# ===================================================================
# IAM: TOKEN CREATOR FOR CLOUD TASKS SERVICE AGENT
# ===================================================================
# Cloud Tasks service agent needs roles/iam.serviceAccountTokenCreator
# on the enqueuer SA to generate OIDC tokens when dispatching tasks.

resource "google_project_service_identity" "cloud_tasks_agent" {
  count    = length(local.cloud_tasks_configs) > 0 ? 1 : 0
  provider = google-beta
  project  = local.settings.project.id
  service  = "cloudtasks.googleapis.com"

  depends_on = [google_project_service.enabled_apis]
}

resource "google_service_account_iam_member" "cloud_tasks_token_creator" {
  for_each = local.cloud_tasks_enqueuer_sa

  service_account_id = "projects/${local.settings.project.id}/serviceAccounts/${each.value}"
  role               = "roles/iam.serviceAccountTokenCreator"
  member             = "serviceAccount:${google_project_service_identity.cloud_tasks_agent[0].email}"

  depends_on = [
    module.cloud_run_services,
    google_project_service_identity.cloud_tasks_agent
  ]
}

# ===================================================================
# IAM: ACT-AS PERMISSION FOR OIDC TOKEN IN CLOUD TASKS
# ===================================================================
# When the enqueuer SA creates a task with an OIDC token referencing
# itself, it needs iam.serviceAccounts.actAs on its own SA.

resource "google_service_account_iam_member" "cloud_tasks_act_as" {
  for_each = local.cloud_tasks_enqueuer_sa

  service_account_id = "projects/${local.settings.project.id}/serviceAccounts/${each.value}"
  role               = "roles/iam.serviceAccountUser"
  member             = "serviceAccount:${each.value}"

  depends_on = [module.cloud_run_services]
}
