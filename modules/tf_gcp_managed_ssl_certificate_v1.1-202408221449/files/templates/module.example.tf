module "certificate_main" {
  source         = "./modules/tf_gcp_managed_ssl_certificate_v1.1-202408221449"
  base_name      = format("%s--%s-main", local.base_name, terraform.workspace)
  region_name    = local.settings.region_name
  gcp_project_id = local.settings.project.id
  domain         = local.settings.app.domain
}
