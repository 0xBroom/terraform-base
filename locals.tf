locals {
  // Loading settings from yml files
  workspace_file = "./settings/${terraform.workspace}.yaml"
  defaults       = file("./settings/default.yaml")
  workspace_data = fileexists(local.workspace_file) ? file(local.workspace_file) : yamlencode({})
  settings = merge(
    yamldecode(local.defaults),
    yamldecode(local.workspace_data)
  )
  base_name        = format("%s", local.settings.client.name)
  base_name_medium = format("%s-%s", local.settings.client.name, terraform.workspace)

  # Standard Artifact Registry host for the project's region
  registry_host        = "${local.settings.region_name}-docker.pkg.dev/${local.settings.project.id}"
  registry_host_python = "${local.settings.region_name}-python.pkg.dev/${local.settings.project.id}"

  # One label set for every resource that accepts labels, applied by the providers
  # (providers.tf). GCP label values allow at most 63 lowercase letters, digits,
  # `_` and `-`, so the values read from YAML are lowercased, every other
  # character becomes `-`, and the result is cut to 63.
  common_labels = {
    for key, value in {
      workspace  = terraform.workspace
      client     = local.settings.client.name
      managed_by = "terraform"
      repo       = try(local.settings.iac.repo, "terraform-base")
    } : key => substr(replace(lower(value), "/[^a-z0-9_-]/", "-"), 0, 63)
  }
}

locals {
  all_firestore = try(local.settings.firestore, {})

  all_firestore_indexes = {
    for item in flatten([
      for db_key, db_config in local.all_firestore : [
        for idx, index_config in try(jsondecode(file(db_config.indexes_file)), []) : {
          key      = "${db_key}/${index_config.collection}/${idx}"
          database = db_config.name
          val      = index_config
        }
      ] if try(db_config.indexes_file, null) != null
    ]) : item.key => item
  }
}
