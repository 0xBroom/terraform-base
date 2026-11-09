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

`settings/pre.yaml` and `settings/pro.yaml` are the reference workspaces once
they exist. Pre is smaller and zonal. Pro is regional, warm, and protected
against an accidental delete. Both are full of placeholders (`REPLACE_ME` and
`example.com`). Planning them against a real project comes after those values
are replaced. Applying them is a separate decision.

Secret values never go in YAML or in HCL. The stack creates the secret and a
placeholder version. The payload is added with `gcloud secrets versions add`,
or later through the SOPS path in `AUD-SOPS`.

## Settings merge

`locals.tf` merges the workspace file over `settings/default.yaml` with
`merge()`. A map in the workspace file replaces the whole map. Do not set
`active-apis` in `pre.yaml` or `pro.yaml`. Add an API to `default.yaml` when
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
