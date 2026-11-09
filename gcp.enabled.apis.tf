# Enable APIs on existing project
# `settings` is a SHALLOW merge of default.yaml and the workspace file, so a workspace
# that declares `active-apis` replaces the whole list instead of adding to it — and a
# copied list silently stops inheriting later additions. `extra-apis` is the additive
# door: one workspace needing one extra API says so in one line.
resource "google_project_service" "enabled_apis" {
  for_each = toset(concat(
    local.settings.active-apis,
    try(local.settings.extra-apis, []),
  ))

  project = local.settings.project.id
  service = each.value

  disable_dependent_services = false
  disable_on_destroy         = false
} 