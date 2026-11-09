# Agent instructions

Read `README.md` and `docs/PROJECT_STRUCTURE.md` before changing anything. This file adds
the conventions an agent must follow when it sets up or extends a project from this
template.

## GCP resource hierarchy

Every new project uses this layout. Create it with `gcloud` or the console before the first
`terraform init`. The template consumes existing projects; it does not create folders or
projects.

```
<org-domain>                         organization
├── dev      (folder)  → <App> Dev       <org>-<app>-dev-<suffix>
├── stg      (folder)  → <App> Staging   <org>-<app>-stg-<suffix>
├── pro      (folder)  → <App> Pro       <org>-<app>-pro-<suffix>
└── common   (folder)  → <App> Ops       <org>-ops-<suffix>
```

Folders group environments, not resource types. IAM and organization policies are set on
the folder once and every project inside inherits them, including projects for other apps
added later. Never create one folder per resource type (a "cloudrun" folder, a "databases"
folder): one app would then span several projects and lose private networking and a single
IAM boundary.

### Naming rules

| Item | Rule | Example |
|---|---|---|
| Folder | `dev`, `stg`, `pro`, `common` | `stg` |
| Project ID | `<org>-<app>-<env>-<suffix>`, all lowercase | `acme-shopapp-stg-48213` |
| Ops project ID | `<org>-ops-<suffix>` | `acme-ops-48213` |
| Display name | `<App> Dev`, `<App> Staging`, `<App> Pro`, `<App> Ops` | `ShopApp Staging` |
| Terraform workspace | same as the folder: `dev`, `stg`, `pro` | `stg` |
| `client.name` | 2 or 3 letter prefix for resource names | `sa` |

- Use the same numeric suffix in every project of one app. Project IDs are global and a
  deleted ID can never be reused, so the suffix avoids collisions and lets you recreate a
  project.
- Project IDs must be 6 to 30 characters: lowercase letters, digits and hyphens, starting
  with a letter. Check the length of the longest one (`stg` and `pro` are the same length
  as `dev`) before creating anything.
- Project IDs and the organization are immutable. Display names and folders can change
  later.
- Set the project ID by hand in the console ("Edit" under the name). Do not let GCP derive
  it from the display name.
- Use title case for every display name, including `Pro`.

### What lives in the ops project

The `common` folder holds the ops project. It is the `project_sys` in
`settings/default.yaml` and it owns:

- the Terraform state bucket, `<org>-ops-<suffix>-tfstate`, referenced in `versions.tf`;
- anything shared by all environments, such as base images or monitoring.

Never put the state bucket inside an environment project. A mistake in `dev` must not be
able to delete the state for `pro`.

### Creating the hierarchy

```bash
ORG_ID=<organization-number>
APP=<app>          # e.g. shopapp
ORG=<org>          # e.g. acme
SUFFIX=<5-digits>  # e.g. 48213

for env in dev stg pro common; do
  gcloud resource-manager folders create --display-name="$env" --organization="$ORG_ID"
done

# Look up each folder ID, then create one project per folder:
gcloud projects create "$ORG-$APP-dev-$SUFFIX" --name="<App> Dev" --folder=<dev-folder-id> \
  --labels=environment=dev,app=$APP,managed-by=terraform
gcloud projects create "$ORG-ops-$SUFFIX" --name="<App> Ops" --folder=<common-folder-id> \
  --labels=environment=common,app=$APP,managed-by=terraform
# Repeat for stg and pro, then link billing:
gcloud billing projects link "$ORG-$APP-dev-$SUFFIX" --billing-account=<billing-account-id>
```

### Mapping to this template

- `settings/default.yaml`: `project_sys` points to the ops project, and `client.name` is the
  app prefix.
- One file per environment: `settings/dev.yaml`, `settings/stg.yaml`, `settings/pro.yaml`,
  each with its own `project.id`, `project.name` and `project.number`.
- One workspace per environment, with the same name: `terraform workspace new stg`.
- Cloud Build tag patterns default to `^<workspace>-...`, so release tags look like
  `pro-2026010101`.

## Working rules

- Never run `terraform apply` without the owner's explicit approval of a plan they have
  read.
- Never use `-target`. Run a full plan.
- Never create resources in the console. Add them to the YAML, or import them.
- Validate with a real workspace, for example `TF_WORKSPACE=dev terraform validate`. The
  `default` workspace has no `project` key and does not validate by design.
