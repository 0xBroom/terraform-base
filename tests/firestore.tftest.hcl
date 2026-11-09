# No reference file has a firestore section, so each run adds one with
# settings_override (locals.tf). Pro defaults to point-in-time recovery and
# delete protection, every other workspace to neither, and the YAML wins.

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

run "pro_firestore_is_protected" {
  command = plan

  variables {
    settings_workspace = "pro"
    settings_override = {
      firestore = {
        default = { name = "(default)", type = "FIRESTORE_NATIVE" }
      }
    }
  }

  expect_failures = [check.settings_workspace_unset]

  assert {
    condition = (
      google_firestore_database.databases["default"].point_in_time_recovery_enablement == "POINT_IN_TIME_RECOVERY_ENABLED"
      && google_firestore_database.databases["default"].delete_protection_state == "DELETE_PROTECTION_ENABLED"
    )
    error_message = "A pro Firestore database without the keys gets point-in-time recovery and delete protection."
  }
}

run "dev_firestore_is_disposable" {
  command = plan

  variables {
    settings_workspace = "dev"
    settings_override = {
      firestore = {
        default = { name = "(default)", type = "FIRESTORE_NATIVE" }
      }
    }
  }

  expect_failures = [check.settings_workspace_unset]

  assert {
    condition = (
      google_firestore_database.databases["default"].point_in_time_recovery_enablement == "POINT_IN_TIME_RECOVERY_DISABLED"
      && google_firestore_database.databases["default"].delete_protection_state == "DELETE_PROTECTION_DISABLED"
    )
    error_message = "A dev Firestore database without the keys has neither point-in-time recovery nor delete protection."
  }
}

run "pro_yaml_overrides_the_defaults" {
  command = plan

  variables {
    settings_workspace = "pro"
    settings_override = {
      firestore = {
        default = {
          name                    = "(default)"
          type                    = "FIRESTORE_NATIVE"
          point_in_time_recovery  = false
          delete_protection_state = "DELETE_PROTECTION_DISABLED"
          deletion_policy         = "DELETE"
        }
      }
    }
  }

  expect_failures = [check.settings_workspace_unset]

  assert {
    condition = (
      google_firestore_database.databases["default"].point_in_time_recovery_enablement == "POINT_IN_TIME_RECOVERY_DISABLED"
      && google_firestore_database.databases["default"].delete_protection_state == "DELETE_PROTECTION_DISABLED"
      && google_firestore_database.databases["default"].deletion_policy == "DELETE"
    )
    error_message = "Values set in the YAML win over the pro defaults."
  }
}
