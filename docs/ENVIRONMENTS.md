# Environments

`AGENTS.md` names the workspaces `dev`, `stg` and `pro`, and each has its own
cost profile: dev is the cheapest that still runs the app, stg is one step up
with the shape of pro, pro is highly available. `settings/pre.yaml` is the stg
profile under the older name, with project id `example-app-pre`. It stays so
the auditor still finds a pre workspace. Use `stg` for a new project.

They describe one service: Cloud Run behind the HTTPS load balancer and IAP, a
private Cloud SQL instance, one bucket, one shared VPC, a budget, and a GitHub
Cloud Build connection. Stg and pro add Redis and Cloud NAT; dev has neither. Anything else (Pub/Sub,
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

| | dev | stg (and pre) | pro |
|---|---|---|---|
| Cloud Run | scale to zero, 1 vCPU, 512Mi, deletion protection off | same as dev | one warm instance, 2 vCPU, 2Gi, deletion protection on |
| Cloud Run CPU (`cpu_idle` default) | only during requests (`true`) | only during requests (`true`) | always allocated (`false`) |
| Cloud Run VPC egress | `PRIVATE_RANGES_ONLY`: public traffic leaves directly | `ALL_TRAFFIC` through Cloud NAT | `ALL_TRAFFIC` through Cloud NAT |
| Cloud NAT | none | one NAT, one static address | one NAT, one static address |
| Deploys | a push to `main` | a push to `main` | a tag `pro-YYYYMMDDHH` |
| Cloud SQL tier | `db-f1-micro` (shared core, 0.6 GB, no SLA), zonal | `db-custom-1-3840` (1 vCPU, 3.75 GB), zonal | `db-custom-2-7680` (2 vCPU, 7.5 GB), regional |
| Cloud SQL disk | 10 GB SSD | 10 GB SSD | 20 GB SSD |
| Cloud SQL `max_connections` | 25 | 100 | 200 |
| Cloud SQL backups | 7, no point-in-time recovery | 7, no point-in-time recovery | 30, 7 days of WAL |
| Cloud SQL insights | off | off | on |
| Cloud SQL audit flags | none | none | connections, disconnections, statements over 1 s, lock waits, pgAudit `ddl,role` |
| Generated database passwords | letters and digits | letters and digits | letters, digits and `-_.~` |
| Redis | none | basic, 1 GB, no TLS | standard HA, 1 GB, TLS |
| Redis deletion protection | no Redis | off | on |
| Redis RDB snapshots | no Redis | off | every 12 hours |
| Bucket soft delete | 7 days (the shortest above off) | 7 days | 30 days |
| Bucket noncurrent versions | kept | kept | deleted after 30 days (`docs/STORAGE.md`) |
| Budget | 40 | 80 | 400 |
| _Default log retention | 30 days | 30 days | 90 days |
| Audit log archive | none | none | locked log bucket, 365 days |
| Log-based security alerts | none | none | seven presets, one email per event |
| Load balancer alerts (`monitoring.lb`) | none | none | 5xx, p99 latency, Cloud Armor 403 |
| Uptime check (`monitoring.uptime`) | none | none | the first `lb.domain` every 5 minutes from 3 regions |
| Binary Authorization | off | off | dry-run, attestation required |
| External CI federation (`wif`) | none | none | none, a commented example (`docs/WIF.md`) |
| VPC | `10.8.1.0/24` | `10.10.1.0/24` | `10.20.1.0/24` |
| Monthly cost, estimate | about 45 to 60 USD | about 130 to 160 USD | about 420 to 500 USD |

The cost row is a ballpark from Google Cloud list prices in `europe-west1`
(USD, on-demand, no free tier, no committed-use discounts), for an idle
project with little traffic. It is not a quote: requests, egress, log volume,
build minutes and storage growth come on top. Run the
[pricing calculator](https://cloud.google.com/products/calculator) before
committing to a figure. What drives it:

- Every workspace pays the HTTPS load balancer forwarding rule (about 18 USD)
  and the Cloud Armor policy with its 11 rules (about 16 USD) before anything
  else, so about 34 USD is the floor.
- Dev adds the shared-core instance and its disk (about 10 to 12 USD).
- Stg adds the dedicated-core instance (about 55 USD), Redis BASIC (about 35
  to 40 USD) and Cloud NAT with its address (about 5 to 10 USD).
- Pro adds the regional instance, which bills both zones (about 220 to 240
  USD), Redis STANDARD_HA (about 50 USD), one always-allocated Cloud Run
  instance (about 95 to 105 USD), Cloud NAT and the audit archive.

The `budget.amount` values are placeholders in the billing account currency.
Set each one above the estimate for that workspace, or its alerts fire every
month.

Dev has no Redis, so the app must start without a cache; no service in
`settings/dev.yaml` references one. Dev has no Cloud NAT either: the service
sets `cloudrun.vpc.egress: "PRIVATE_RANGES_ONLY"`, so only private addresses
(the Cloud SQL private IP) go through the VPC and calls to public hosts leave
Cloud Run directly. Those calls come from a Google-owned address, not a
static one. When a third party must allowlist the egress IP, copy the
`network.nats` block from stg and drop the `vpc.egress` override.

Redis `deletion_protection` defaults to `true` in pro and `false` elsewhere,
so stg can be torn down and pro cannot: `terraform destroy`, or a change that
would replace the instance, fails while it is `true`. The flag lives in
Terraform state only. Turning it off is an in-place update with no API call,
applied before the destroy. Pro also sets `persistence`: an RDB snapshot every
12 hours. A STANDARD_HA instance fails over to its replica first and loads the
snapshot only when the replica is lost too; a BASIC instance reloads it after
every restart, scale or version upgrade. Only the last snapshot is kept and it
cannot be restored by hand, so it is not a backup: use `gcloud redis instances
export` for that. Snapshots need Redis 5.0 or later and add no charge to the
instance. Stg leaves them off because its cache can be rebuilt, not to save
money.

All of them keep the database private, require SSL, protect the instance from
deletion, put IAP on `/*`, and refuse to disable billing when the budget is
hit. `enable_auto_stop: false` matches the Terraform default and is written
out so nobody turns it on by accident: `true` deploys a function that turns
billing off, and every service in the project with it.

`cloudrun.cpu_idle` defaults to `true` in every workspace but pro: a service
gets CPU only while it serves a request and is billed per request. Work that
keeps running after the response (a thread, a queue consumer, a flush on a
timer) is throttled and may never finish. A service that needs it sets
`cpu_idle: false`, which bills the CPU for as long as an instance is up. Pro
defaults to `false`, so its warm instance keeps its CPU.

The pro audit flags write to Cloud Logging, so dev and stg leave them out.
`db-f1-micro` and `db-g1-small` share a CPU and are not covered by the Cloud
SQL SLA, which is fine for dev and the reason stg uses a dedicated core.
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

Pro also sets `monitoring.lb`, read by the load balancer monitoring module in
`gcp.lb.tf`: more than 25 responses with a 5xx code in 3 minutes (ERROR), a
p99 latency above 3000 ms for 5 minutes (WARNING), and more than 150 requests
blocked by Cloud Armor in 3 minutes (WARNING). Each key needs all five fields
(`duration`, `threshold_value`, `alignment_period`, `severity`, `enabled`).
The Cloud Armor alert counts a log-based metric the module creates on the
load balancer request logs, which the backends already write. Tune the
thresholds to the real traffic after the first weeks.

`monitoring.uptime` adds one HTTPS uptime check per entry in
`gcp.monitoring.tf` and an alert policy that emails the same channel when the
check fails from `failing_regions` regions (2 by default) in the same window.
The host defaults to the first `lb.domain`. Pro probes `/` every 5 minutes
from three regions with a 10 second timeout. Two things to know:

- **IAP answers first.** Pro puts IAP on `/*`, so an anonymous probe gets a
  302 to the sign-in page (401 for some clients) and never reaches the app.
  Pro accepts `2xx`, `302` and `401`: the check proves that DNS, the
  certificate, the load balancer and IAP answer, not that the backend is
  healthy. To cover the backend, add a load balancer rule without IAP for a
  health path that returns no data, point `path` at it and accept `2xx` only.
- **It fails until the domain is real.** `app.example.com` is a placeholder,
  so the check fails and the alert fires from the first apply until
  `lb.domain` holds the real name and its certificate is active.

Each regional execution of an uptime check is billed at 0.30 USD per 1,000
past the free 1 million per project and month; three regions every 5 minutes
make about 26,000. Alert policies on uptime metrics are not billed. Cloud
Monitoring has announced a charge for metric alert policies from September
2027 at the earliest; the load balancer alerts fall under it, the uptime and
log-based ones do not. Dev and stg leave both keys out.

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
