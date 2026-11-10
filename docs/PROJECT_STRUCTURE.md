# Project Structure Guide

This document describes how the files in this repository fit together.

## Root directory

- `README.md`: overview and getting started.
- `locals.tf`: loads `settings/default.yaml`, merges `settings/<workspace>.yaml` on top, and exposes the result as `local.settings`.
- `providers.tf` and `versions.tf`: provider configuration, version pins and the remote state backend.
- `gcp.<type>.tf`: one root file per GCP resource type. Each one reads its section of `local.settings` and creates nothing when that section is absent.
  - `gcp.cloudrun.tf`: Cloud Run services, their service accounts, IAM and volumes.
  - `gcp.jobs.tf`: Cloud Run jobs.
  - `gcp.cloudbuild.tf`: Cloud Build triggers that build and deploy every image through `cloudbuild_files/cloudbuild.yaml`.
  - `gcp.network.tf`: VPC, subnets, serverless connector and Cloud NAT.
  - `gcp.lb.tf` and `gcp.waf.tf`: global HTTPS load balancer, backends, URL map, Cloud Armor.
  - `gcp.sql.tf`, `gcp.redis.tf`, `gcp.firestore.tf`: data stores.
  - `gcp.storage.tf`, `gcp.secrets*.tf`, `gcp.artifact*.tf`: buckets, secrets, registries.
  - `gcp.iam.tf`, `gcp.service.permissions.tf`, `gcp.security.tf`: project IAM and the security baseline.
  - `gcp.wif.tf`: Workload Identity Federation for external CI (`docs/WIF.md`).
  - `gcp.billing.tf`: budget with optional automatic billing shutdown.
  - `gcp.dns.tf`, `gcp.pubsub.tf`, `gcp.cloudtasks.tf`, `gcp.scheduler.tf`, `gcp.compute*.tf`, `gcp.firewall.tf`, `gcp.elastic.psc.tf`, `gcp.binary_auth.tf`, `gcp.repository.*.tf`: the rest, same pattern.
- `oracle.compute.tf`, `oracle.network.tf`, `oracle.security.tf`: the optional Oracle Cloud side (VMs, VCN, security lists), driven by the `oracle:` section.

## Subdirectories

### `settings/`

YAML files that define the infrastructure, one per workspace.

- `default.yaml`: baseline shared by every workspace (region, client prefix, enabled APIs).
- `example.yaml`: commented reference of every supported key.
- `pre.yaml` and `pro.yaml`: a complete small service, sized for each environment. See `docs/ENVIRONMENTS.md`. Replace the placeholders before planning.
- `<workspace>.yaml`: any further project. One file per workspace.

### `modules/`

Vendored, version-stamped Terraform modules. Each one covers a single component (Cloud Run v2, Cloud SQL, networking, storage, IAM, LB monitoring, Artifact Registry, managed SSL, project security). The version is in the directory name, so upgrading a module is an explicit, reviewable change.

### `docs/`

Guides for the YAML schema, the Cloud Build pipeline, tag patterns, Cloud Run resources and billing control.

### `bin/`

Helper scripts: render the effective Cloud Build pipeline of a service from the YAML, and audit Artifact Registry cleanup policies.

### `cloudbuild_files/`

The single shared Cloud Build pipeline. Per-service differences are substitutions generated from the YAML, never edits to this file.

### `cloud_function_source/`

Source of the Cloud Function that disables billing when the budget is exceeded.
