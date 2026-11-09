# _Default retention is written down so a project does not keep Google's
# unspoken default. _Required stays untouched unless the YAML sets it: Google
# rejects a value under 400 days.

check "required_log_retention" {
  assert {
    condition     = try(local.settings.logging.required_retention_days, 400) >= 400
    error_message = "logging.required_retention_days must be at least 400. Omit the key to leave the _Required bucket alone."
  }
}

resource "google_logging_project_bucket_config" "default" {
  project        = local.settings.project.id
  location       = "global"
  bucket_id      = "_Default"
  retention_days = try(local.settings.logging.retention_days, terraform.workspace == "pro" ? 90 : 30)

  depends_on = [google_project_service.enabled_apis]
}

resource "google_logging_project_bucket_config" "required" {
  count          = try(local.settings.logging.required_retention_days, null) == null ? 0 : 1
  project        = local.settings.project.id
  location       = "global"
  bucket_id      = "_Required"
  retention_days = try(local.settings.logging.required_retention_days, 400)

  depends_on = [google_project_service.enabled_apis]
}
