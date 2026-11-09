# Pre and pro

`settings/pre.yaml` and `settings/pro.yaml` are the reference workspaces. They
describe one service: Cloud Run behind the HTTPS load balancer and IAP, a
private Cloud SQL instance, Redis, one bucket, one shared VPC with Cloud NAT,
a budget, and a GitHub Cloud Build connection. Anything else (Pub/Sub,
Firestore, a VM, Elastic) stays in `settings/example.yaml` until the project
needs it.

Both files are full of placeholders (`example-app-pre`, `example-app-pro`,
`000000-000000-000000`, `replace-me@example.com`, GitHub owner `example-org`,
installation id `1`). Replace those, put the state bucket name in
`versions.tf`, and plan. Applying is a separate decision. Planning this file
unchanged fails at GCP because the project and the billing account do not
exist, which is what we want.

`terraform validate` does succeed. It does not talk to GCP.

## What changes between them

| | pre | pro |
|---|---|---|
| Cloud Run | scale to zero, 1 vCPU, 512Mi, deletion protection off | one warm instance, 2 vCPU, 2Gi, deletion protection on |
| Deploys | a push to `main` | a tag `pro-YYYYMMDDHH` |
| Cloud SQL | zonal, 1 vCPU, 7 backups, insights off | regional, 2 vCPU, 30 backups, insights on |
| Redis | basic, no TLS | standard HA, TLS |
| Bucket soft delete | 7 days | 30 days |
| Budget | 80 EUR | 400 EUR |
| VPC | `10.10.1.0/24` | `10.20.1.0/24` |

Both keep the database private, require SSL, protect the instance from
deletion, put IAP on `/*`, and refuse to disable billing when the budget is
hit. `enable_auto_stop: false` is set on purpose: the Terraform default is
true, and dropping the line deploys a function that turns billing off.

The first Cloud Run revision is the public hello image. Cloud Build replaces
the digest and Terraform leaves it alone. Do not pin a real image in the YAML.

The database name `api-db` and the user `api-app-user` are the default, built
from the service name `api`, because these files omit `databases` and `users`.
Set those lists on the instance (siblings of `sql`) when a service should not
get a database, or when the names should differ.

## What this is not

These files are not a Tools Hub project. There is one VPC, not one per
service. There is no Shieldcode, no CMEK, and no separate system project.
`docs/audit/BACKLOG.md` lists what is still open and what was left out.
