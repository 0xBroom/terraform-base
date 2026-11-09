# How to change this Terraform

The backlog in `BACKLOG.md` is the list of work. `bin/audit-terraform.py` decides
which items are still open by reading the code. Edit the script when you add a
check. Do not tick a box by hand.

## One item, one pull request

1. Run `python3 bin/audit-terraform.py`.
2. Take the first open `p0`, then the first open `p1`. Leave anything under
   "Accepted, do not port" alone. Those are Tools Hub features this project
   does not need, including a VPC per module.
3. Branch from `main`: `<type>/<id-lower>-<short-slug>`, for example
   `fix/aud-net-optional-vpc`.
4. Change only that item. A drive-by edit belongs in its own item.
5. Run the auditor again. The item you took must say `done`. Then
   `python3 bin/audit-terraform.py --write` and commit the refreshed
   `docs/audit/BACKLOG.md` in the same pull request.
6. If you touched `.tf` files: `terraform fmt` on those files,
   `terraform init -backend=false`, `terraform validate`.
7. Open the pull request with a Summary, the list of changes, how you
   validated, and how to roll it back. Do not apply.

`terraform apply` and `terraform destroy` wait for an explicit yes for that
plan, in that workspace. A pull request is not that yes.

## What "production" means here

`settings/dev.yaml`, `settings/stg.yaml` and `settings/pro.yaml` are the
reference workspaces. `settings/pre.yaml` is the older name for the stg shape
and stays. Dev and stg are smaller and zonal. Pro is regional, warm, and
protected against an accidental delete. They use placeholders
(`example-app-dev`, `example-app-stg`, `example-app-pro`,
`replace-me@example.com`). Planning them against a real project comes after
those values are replaced. Applying them is a separate decision. The
difference is `docs/ENVIRONMENTS.md`.

Pull requests run the same fmt and validate on the default workspace
(`.github/workflows/terraform.yml`). A green local validate is still the
check you run before opening the pull request.

Secret values never go in YAML or in HCL. The stack creates the secret and a
placeholder version. The payload is added with `gcloud secrets versions add`,
or through the SOPS path in `docs/SOPS.md`.

## Settings merge

`locals.tf` merges the workspace file over `settings/default.yaml` with
`merge()`. A map in the workspace file replaces the whole map. Do not set
`active-apis` in an environment file. Add an API to `default.yaml` when
every workspace needs it.

## Vendored modules

`modules/tf_gcp_*` are snapshots. The directory name is the version. Do not
edit a module in place without giving the directory a new version suffix, and
do not copy a newer module out of a private registry into this repo. The
backlog items `AUD-MOD-*` say when an upgrade is allowed.

## Comparison baseline

The gap list was taken against a production YAML-driven GCP stack on
2026-11-09. That stack is the pattern for one project. It is not a
dependency, and its per-product network, Shieldcode, Harbor, SonarQube, group
matrix and CMEK programme stay on the accepted list.
