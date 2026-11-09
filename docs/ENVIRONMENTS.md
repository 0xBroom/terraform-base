# Environments

`AGENTS.md` names the workspaces `dev`, `stg` and `pro`. `settings/dev.yaml`
and `settings/stg.yaml` are that shape. `settings/pre.yaml` is that same shape under the older name, with project id
`example-app-pre`. It stays so the auditor still finds a pre workspace. Use
`stg` for a new project.

They describe one service: Cloud Run behind the HTTPS load balancer and IAP, a
private Cloud SQL instance, Redis, one bucket, one shared VPC with Cloud NAT,
a budget, and a GitHub Cloud Build connection. Anything else (Pub/Sub,
Firestore, a VM, Elastic) stays in `settings/example.yaml` until the project
needs it.

The files are full of placeholders (`example-app-dev`, `example-app-stg`, `example-app-pro`,
`000000-000000-000000`, `replace-me@example.com`, GitHub owner `example-org`,
installation id `1`). Replace those, put the state bucket name in
`versions.tf`, and plan. Applying is a separate decision. Planning this file
unchanged fails at GCP because the project and the billing account do not
exist, which is what we want.

`terraform validate` does succeed. It does not talk to GCP.

## What changes between them

| | dev and stg | pro |
|---|---|---|
| Cloud Run | scale to zero, 1 vCPU, 512Mi, deletion protection off | one warm instance, 2 vCPU, 2Gi, deletion protection on |
| Deploys | a push to `main` | a tag `pro-YYYYMMDDHH` |
| Cloud SQL | zonal, 1 vCPU, 7 backups, insights off | regional, 2 vCPU, 30 backups, insights on |
| Cloud SQL point-in-time recovery | off, the nightly backup only | 7 days of WAL |
| Cloud SQL audit flags | none | connections, disconnections, statements over 1 s, lock waits, pgAudit `ddl,role` |
| Generated database passwords | letters and digits | letters, digits and `-_.~` |
| Redis | basic, no TLS | standard HA, TLS |
| Bucket soft delete | 7 days | 30 days |
| Budget | 40 EUR on dev, 80 EUR on stg | 400 EUR |
| _Default log retention | 30 days | 90 days |
| Audit log archive | none | locked log bucket, 365 days |
| Log-based security alerts | none | seven presets, one email per event |
| Binary Authorization | off | dry-run, attestation required |
| External CI federation (`wif`) | none | none, a commented example (`docs/WIF.md`) |
| VPC | dev `10.8.1.0/24`, stg and pre `10.10.1.0/24` | `10.20.1.0/24` |

Both keep the database private, require SSL, protect the instance from
deletion, put IAP on `/*`, and refuse to disable billing when the budget is
hit. `enable_auto_stop: false` is set on purpose: the Terraform default is
true, and dropping the line deploys a function that turns billing off.

The pro audit flags write to Cloud Logging, so dev and stg leave them out.
`cloudsql.enable_pgaudit` only loads pgAudit: the application's migration
must run `CREATE EXTENSION pgaudit;` once in each database before
`pgaudit.log` records anything. This stack has no PostgreSQL provider and
does not run SQL. `pgaudit.log` stays at `ddl,role` because `write` logs the
text of every data change, literal values included. Add it only when the
retention and access rules of those logs allow it.

Pro sets `logging.audit_archive`: a log bucket `audit-archive` and a sink that
copies every Cloud Audit Log (admin activity, data access, system event,
policy denied) into it for 365 days. A project owner can shorten or empty
`_Default`; the archive is locked so nobody can. Two things to know before the
first apply:

- **A locked bucket is permanent for its retention.** It cannot be unlocked,
  its `retention_days` can only grow, and it cannot be deleted, by Terraform or
  by hand, until every entry in it is older than 365 days. `terraform destroy`
  of pro fails on it. To try the archive first, apply with `locked: false`,
  check the logs arrive, then lock it.
- **It is billed.** Logs routed to the archive count as ingestion (billed past
  the free monthly allotment), and log bucket storage beyond 30 days is billed
  per GiB-month. Audit volume grows with `security.audit_logging` data reads
  and writes. Dev and stg leave the key out and get neither the bucket nor the
  sink.

The bucket is in the same project as the sink, so no IAM grant is needed for
the sink's writer identity.

Pro sets `monitoring.log_alerts`: `gcp.monitoring.tf` turns each enabled entry
into an alert policy that matches Admin Activity audit log entries and emails
the `security.alerts_email` channel once per event, with the principal, the
method and the resource in the incident. The presets are:

| Preset | Fires on |
|---|---|
| `iam_policy_change` | `SetIamPolicy` on the project |
| `service_account_key_created` | a service account key created or uploaded |
| `firewall_change` | a VPC firewall rule inserted, patched, updated or deleted |
| `audit_config_change` | a `SetIamPolicy` that changes the audit log configuration |
| `custom_role_change` | a custom role created, updated, deleted or restored |
| `sql_instance_change` | a Cloud SQL instance created, updated or deleted |
| `bucket_iam_change` | `storage.setIamPermissions` on a bucket |

Any other key is a custom alert and needs its own `filter`. Entries take
`enabled`, `severity`, `notification_rate_limit` (one email per period, 5
minutes by default) and `excluded_principals`. `monitoring.excluded_principals`
applies to every alert: put the identity that runs `terraform apply` there,
or each apply that touches IAM or a firewall pages the channel. Pro lists a
placeholder Terraform service account; replace it.

The basic security module still keeps its own threshold alerts on firewall,
custom role, audit config, Cloud SQL and bucket IAM changes, so a manual
change can reach the channel twice. The log-based ones are the ones to read:
they arrive per event, name who did it and skip the Terraform identity. A
change to an audit config also matches `iam_policy_change`, since both are a
`SetIamPolicy`.

Log-based alert policies are not billed, and they read logs Cloud Logging
already keeps. Dev and stg still leave the key out, so their channel only
gets the module's alerts.

The first Cloud Run revision is the public hello image. Cloud Build replaces
the digest and Terraform leaves it alone. Do not pin a real image in the YAML.

The database name `api-db` and the user `api-app-user` are the default, built
from the service name `api`, because these files omit `databases` and `users`.
Set those lists on the instance (siblings of `sql`) when a service should not
get a database, or when the names should differ.

## What this is not

These files describe one application in one project per environment. There
is one VPC, not one per service. There is no external scanner instance, no
CMEK programme, and no separate monitoring project. `docs/audit/BACKLOG.md`
lists what is still open and what was left out on purpose.
