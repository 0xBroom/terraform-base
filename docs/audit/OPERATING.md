# How to change this Terraform

The backlog in `BACKLOG.md` is the list of work. `bin/audit-terraform.py`
decides which items are still open by reading the code. Edit the script when
you add a check. Do not tick a box by hand.

## The audit loop

The backlog is worked by a loop with three separate roles. One person or agent
can play several roles, but never worker and verifier for the same item.

1. **Auditor.** Reads the whole repository (Terraform, YAML, file and module
   names, docs, every comment) and looks for gaps against the two goals: dev
   and stg cheap, pro ready for a security, backup and data-retention audit.
   Every finding becomes an `Item` in `bin/audit-terraform.py` with a check
   that fails today. A finding that is a deliberate choice becomes an
   `accepted` item instead, with the reason.
2. **Worker.** Takes the item `python3 bin/audit-terraform.py --next` prints,
   changes only what that item needs, and opens one pull request.
3. **Verifier.** Reads the diff against the item text, not the worker's
   summary, runs the checks below, and sends the item back when the check
   passes for the wrong reason (a string added to a comment, a setting nobody
   reads).

When `--next` prints `nothing left`, the auditor runs again. The loop stops
when a full audit adds no new item.

## One item, one pull request

1. Run `python3 bin/audit-terraform.py --next`.
2. Branch: `<type>/<id-lower>-<short-slug>`, for example
   `fix/aud-sql-pitr-wire-backup`.
3. Change only that item. A drive-by edit belongs in its own item.
4. Run the auditor again. The item you took must say `done`
   (`python3 bin/audit-terraform.py --id <ID>` exits 0). Then
   `python3 bin/audit-terraform.py --write` and commit the refreshed
   `docs/audit/BACKLOG.md` in the same pull request.
5. If you touched `.tf` files: `terraform fmt` on those files,
   `terraform init -backend=false`, `terraform validate`, and the same
   validate in the `dev`, `stg` and `pro` workspaces (a local backend
   override, `*_override.tf`, is gitignored).
6. CI repeats part of this on the pull request: `terraform fmt -check`,
   `terraform validate` in `default`, `dev`, `stg`, `pre` and `pro`,
   `python3 bin/cloudbuild-render-test.py` and
   `python3 bin/audit-terraform.py --fail-on p0`. It does not run
   `--id <ID>` or `--leaks`; run those yourself.
7. Open the pull request with a Summary, the list of changes, how you
   validated, and how to roll it back. Do not apply.

`terraform apply` and `terraform destroy` wait for an explicit yes for that
plan, in that workspace. A pull request is not that yes.

## The two profiles

`settings/dev.yaml`, `settings/stg.yaml` and `settings/pro.yaml` are the
reference workspaces. `settings/pre.yaml` is the older name for the stg shape
and stays. Dev and stg are small, zonal and scale to zero. Pro is regional,
warm, protected against an accidental delete, and keeps the logs and backups
an audit asks for. They use placeholders (`example-app-dev`,
`example-app-stg`, `example-app-pro`, `replace-me@example.com`). Planning
them against a real project comes after those values are replaced. Applying
them is a separate decision. The difference is `docs/ENVIRONMENTS.md`.

Secret values never go in YAML or in HCL. The stack creates the secret and a
placeholder version. The payload is added with `gcloud secrets versions add`,
or through the SOPS path in `docs/SOPS.md`.

## Generic by design

This repository is public. Tracked files name no company, client, product or
person, and carry no real email, project id or billing id. `AUD-PUB-LEAKS`
scans for real-looking emails, and for any extra terms listed one regular
expression per line in a gitignored `.audit-denylist` (or the file named by
`AUDIT_DENYLIST`). A fork that was cut from a private stack lists that
stack's names there.

## Settings merge

`locals.tf` merges the workspace file over `settings/default.yaml` with
`merge()`. A map in the workspace file replaces the whole map. Do not set
`active-apis` in an environment file. Add an API to `default.yaml` when
every workspace needs it.

## Vendored modules

`modules/*` are snapshots. Do not edit a module in place without giving the
directory a new version suffix. The one exception is a comment or documentation fix
(a translation, a typo) that changes no argument, default or expression: it may be
made in place, because a new directory would only churn every `source` for nothing.
