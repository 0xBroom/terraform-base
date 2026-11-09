module "iam_member_permission_sys" {
  source     = "./modules/tf_gcp_project_iam_permissions_v2.0-202405091017"
  project_id = local.settings.project.id
  permissions = [
    {
      members = ["group:name@.domain.com", "user:pepe@domain.net"]
      roles = [
        "roles/cloudkms.cryptoKeyEncrypterDecrypter",
      ]
    },
    {
      members = ["domain:user@domain.com"],
      roles = [
        "roles/viewer"
      ],
    }
  ]
}
