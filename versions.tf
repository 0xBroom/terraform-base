terraform {
  required_version = ">= 1.14.0"

  # Remote state. Create the bucket once, by hand or with a tiny bootstrap
  # configuration, then set its name here before the first `terraform init`.
  # Workspaces share this bucket: each one gets its own prefix automatically.
  backend "gcs" {
    bucket = "CHANGE-ME-tfstate-bucket"
  }

  required_providers {
    oci = {
      source  = "oracle/oci"
      version = "~> 6.27.0"
    }
    google = {
      source  = "hashicorp/google"
      version = "~> 7.42.0"
    }
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 7.42.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.7.0"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.13.0"
    }
    sops = {
      source  = "carlpett/sops"
      version = "~> 1.1"
    }
  }
}
