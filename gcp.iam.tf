locals {
  # Access lists read from the settings YAML files
  viewers   = try(local.settings.project_access.viewers, [])
  operators = try(local.settings.project_access.operators, [])

  # IAP (Identity-Aware Proxy) admin members
  iap_admin_members = try(local.settings.iap.admin_access.members, [])

  # Viewers and operators merged for the basic viewer role
  all_viewers_list = setunion(local.viewers, local.operators)
}

resource "google_project_iam_member" "viewers" {
  for_each = toset(local.all_viewers_list)

  project = local.settings.project.id
  role    = "roles/viewer"
  member  = each.value
}

resource "google_project_iam_member" "run_invokers" {
  for_each = toset(local.operators)

  project = local.settings.project.id
  role    = "roles/run.invoker"
  member  = each.value
}

resource "google_project_iam_member" "sa_users" {
  for_each = toset(local.operators)

  project = local.settings.project.id
  role    = "roles/iam.serviceAccountUser"
  member  = each.value
}

resource "google_project_iam_custom_role" "job_operator_overrides" {
  count = length(local.operators) > 0 ? 1 : 0

  role_id     = "CloudRunJobOperatorWithOverrides"
  title       = "Cloud Run Job Operator (With Overrides)"
  description = "Runs Cloud Run Jobs with overrides."

  permissions = [
    "run.jobs.run",
    "run.jobs.runWithOverrides",
    "run.executions.get",
    "run.executions.list",
    "run.locations.list"
  ]
}

resource "google_project_iam_member" "job_operators_binding" {
  for_each = toset(local.operators)

  project = local.settings.project.id
  role    = google_project_iam_custom_role.job_operator_overrides[0].id
  member  = each.value
}

resource "google_project_iam_member" "cloudbuild_editors" {
  for_each = toset(local.operators)

  project = local.settings.project.id
  role    = "roles/cloudbuild.builds.editor"
  member  = each.value
}

resource "google_project_iam_member" "cloudbuild_connection_admins" {
  for_each = toset(local.operators)

  project = local.settings.project.id
  role    = "roles/cloudbuild.connectionAdmin"
  member  = each.value
}


# 1. Service identity (the IAP service agent)
resource "google_project_service_identity" "iap_sa" {
  count    = 1
  provider = google-beta
  project  = local.settings.project.id
  service  = "iap.googleapis.com"
}

# 2. Safety wait (60s for the service agent to propagate)
resource "time_sleep" "wait_for_iap_sa" {
  count           = 1
  create_duration = "60s"
  depends_on      = [google_project_service_identity.iap_sa]
}

# 3. Invoker permission PER SERVICE (only services with IAP enabled)

resource "google_cloud_run_service_iam_member" "iap_invoker_services" {
  # Only services with IAP enabled (directly or through the load balancer)
  for_each = {
    for k, v in local.app_services : k => v
    if try(v.cloudrun.iap.enabled, false) == true || length([
      for rule in try(v.loadbalancer.rules, []) : rule
      if try(rule.iap.enabled, false) == true
    ]) > 0
  }

  project  = local.settings.project.id
  location = try(each.value.cloudrun.region, local.settings.region_name)
  service  = try(each.value.custom_name, null) != null ? each.value.custom_name : "${local.base_name}-${try(each.value.name, each.key)}"

  role   = "roles/run.invoker"
  member = "serviceAccount:${google_project_service_identity.iap_sa[0].email}"

  depends_on = [time_sleep.wait_for_iap_sa, module.cloud_run_services]
}

# 4. ACCESS permission (IAP-Secured Web App User)
# Lets specific users and groups reach the application through IAP
resource "google_iap_web_cloud_run_service_iam_member" "iap_access_members" {
  for_each = {
    for pair in flatten([
      for service_key, service in local.app_services : [
        for member in try(service.cloudrun.iap.members, []) : {
          key         = "${service_key}-${member}"
          service_key = service_key
          member      = member
        }
      ]
    ]) : pair.key => pair
  }

  project                = local.settings.project.id
  location               = try(local.app_services[each.value.service_key].cloudrun.region, local.settings.region_name)
  cloud_run_service_name = try(local.app_services[each.value.service_key].custom_name, null) != null ? local.app_services[each.value.service_key].custom_name : "${local.base_name}-${try(local.app_services[each.value.service_key].name, each.value.service_key)}"
  role                   = "roles/iap.httpsResourceAccessor"
  member                 = each.value.member

  depends_on = [module.cloud_run_services]
}
