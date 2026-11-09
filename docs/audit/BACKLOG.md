# Audit backlog

Compared on 2026-11-09 with a production YAML-driven GCP stack (its
settings, locals, network, security, SQL, KMS and provider pins). This
repository is that template: root files `gcp.*.tf`, vendored `tf_gcp_*`
modules, one workspace file per environment.

Open: 8. Done: 16. Accepted, do not port: 16.

Regenerate this file with `python3 bin/audit-terraform.py --write` in the same
pull request that closes an item. The status comes from the code, not from
this prose. How a session picks the next item: `docs/audit/OPERATING.md`.


## Open

### AUD-PROVIDER (p2) The Google provider is pinned to 6.42 while Tools Hub is on 7.42

versions.tf asks for hashicorp/google ~> 6.42.0 and Terraform >= 1.10. Tools Hub is on ~> 7.42 and Terraform >= 1.14. The vendored modules in this repo were written against the 6.x provider. A major bump is a review of those modules, not a one-line edit.

Evidence: versions.tf required_providers.google version ~> 6.42.0.

Next change: Open one PR that bumps Terraform and both Google providers, runs validate, and notes every module argument the new provider rejects.

### AUD-MOD-SEC (p2) The security baseline module is the May 2024 snapshot

modules/tf_gcp_basic_project_security_v1.8-202405071510 is what this repo vendors. Tools Hub calls v2.6-202604231625 from Bitbucket. The newer module is private. Do not copy it into this repository. Record the gap so an upgrade is a deliberate import of a module this project is allowed to republish.

Evidence: gcp.security.tf source = ./modules/tf_gcp_basic_project_security_v1.8-202405071510.

Next change: When a republishable v2 module is available, vendor it under a new directory name and switch the source in one PR.

### AUD-MOD-NET (p2) The networking module is the March 2025 snapshot

modules/tf_gcp_networking_v3.5-202503101237. Tools Hub is on v3.8-202605270915. Same rule as the security module: the newer source is private, so this item waits for a module we can vendor.

Evidence: gcp.network.tf source path contains tf_gcp_networking_v3.5.

Next change: Vendor a newer networking module only if it can be republished, then switch gcp.network.tf.

### AUD-MOD-RUN (p2) The Cloud Run module is the February 2025 snapshot

modules/tf_gcp_cloudrun_v2_v6.5-202502191120. Tools Hub has moved on. Root files already pass command, args, probes and direct VPC egress, so the gap is the module's own defaults and monitoring, not a missing feature in the YAML.

Evidence: gcp.cloudrun.tf source path contains tf_gcp_cloudrun_v2_v6.5.

Next change: Upgrade in one PR when a republishable module is available. Do not fork the vendored copy in place.

### AUD-PAP (p2) Buckets cannot set public access prevention

The storage module (v2.5, June 2024) exposes uniform_bucket_level_access and defaults it to true, which Tools Hub also does. It has no public_access_prevention argument. Uniform access stops ACLs. Public access prevention stops a later allUsers binding from making the bucket public. Both belong on a production bucket.

Evidence: modules/tf_gcp_storage_v2.5-202406121124/vars.tf has no public_access_prevention.

Next change: Add the argument to the vendored module, default it to enforced, and thread a YAML override through gcp.storage.tf. Bump the directory version suffix so the edit is visible.

### AUD-BINAUTH (p2) Binary Authorization, when turned on, only dry-runs an allow-all rule

gcp.binary_auth.tf sets evaluation_mode ALWAYS_ALLOW and enforcement_mode DRYRUN_AUDIT_LOG_ONLY. Switching binary_authorization.enabled to true does not reject an unsigned image. Tools Hub pairs Binary Authorization with a signer key and a real policy. A dry-run allow-all is a useful first step and a bad place to stop for pro.

Evidence: gcp.binary_auth.tf default_admission_rule.

Next change: Let the YAML choose ALWAYS_ALLOW or REQUIRE_ATTESTATION, and default pro to dry-run only until an attestor exists. Do not pretend the current policy enforces anything.

### AUD-LOGS (p3) Log buckets keep the Google default retention

There is no google_logging_project_bucket_config. Admin activity is on once AUD-AUDIT lands, and then expires on Google's default. A production project usually wants _Default and _Required retention written down.

Evidence: No gcp.logging.tf. gcp.security.tf creates the notification channel and the security module only.

Next change: Add a small logging file driven by settings.logging.retention_days, with a sane default of 30 for pre and 90 for pro.

### AUD-CODEOWNERS (p3) No CODEOWNERS file

Anyone with write access can change a pro setting and a module in the same review with nobody named. A one-line CODEOWNERS is enough until the project has a team.

Evidence: No CODEOWNERS at the repo root or under .github/.

Next change: Add CODEOWNERS when the project has a GitHub team or user to name. Do not invent an owner.

## Done

### AUD-NET (p0) The shared VPC is created even when the workspace has no network section

gcp.network.tf reads local.settings.network.* with no guard, and the firewall, Cloud SQL private IP and Cloud Run VPC attachment all assume that module exists. A workspace that only needs Cloud Run behind a load balancer cannot plan. Tools Hub creates networks with for_each and skips a product that has none. This template needs the same switch, for one VPC, not one VPC per service.

Evidence: gcp.network.tf module.network has no count. gcp.firewall.tf always binds to it.

Next change: Create the VPC only when settings.network.services_cidr is set. Point every consumer at module.network[0] through that flag.

### AUD-VPC-DEFAULT (p0) Cloud Run and jobs attach to the VPC by default

gcp.cloudrun.tf defaults vpc_access_enabled to true, and gcp.jobs.tf defaults enable_vpc_access to true. With the VPC made optional, those defaults would still name a network that does not exist. Direct VPC egress is the right default only when this project actually has the shared VPC. Tools Hub does the same kind of gating with feature flags.

Evidence: gcp.cloudrun.tf vpc_access_enabled default true. gcp.jobs.tf enable_vpc_access default true.

Next change: Default both to local.network_enabled. A service can still opt in or out in YAML.

### AUD-FW-CIDR (p1) The internal firewall allows two CIDRs the VPC does not have

allow_internal_vpc permits 10.10.1.0/24, 10.20.0.0/24 and 10.20.1.0/24. Only the first is the services subnet in settings/example.yaml. The other two match nothing this stack creates: Cloud SQL and Redis use Private Service Access, not those ranges. A project that picks a different services_cidr gets a firewall for the wrong subnet.

Evidence: gcp.firewall.tf source_ranges.

Next change: Use settings.network.services_cidr plus an optional extra_internal_cidrs list.

### AUD-BUCKET (p0) A workspace with no bucket key cannot plan

gcp.storage.tf iterates local.settings.bucket directly. Every other map in this repo uses try(..., {}). The README says a missing section creates nothing. Buckets are the exception, so the first plan of a new project fails before it creates anything.

Evidence: gcp.storage.tf for_each = local.settings.bucket.

Next change: Guard the map with try(local.settings.bucket, {}).

### AUD-AUDIT (p0) Admin-read audit logs are off

gcp.security.tf sets admin_read, data_read and data_write to false. Tools Hub turns admin_read on and leaves data_read and data_write off, because data access logs are expensive and admin activity is the trail you need when someone changes IAM or firewalls. A production project without admin-read logs cannot answer who changed what.

Evidence: gcp.security.tf audit_logging block, all three flags false.

Next change: Default admin_read to true. Allow settings.security.audit_logging to override each flag. Keep data_read and data_write off unless a workspace asks.

### AUD-DELETE (p0) Cloud Run services and jobs can be destroyed with deletion_protection left false

gcp.cloudrun.tf and gcp.jobs.tf hardcode deletion_protection = false. Cloud SQL already defaults it to true inside its module. A pro workspace should have to opt out of protecting the service and the job, the same way it has to opt out of protecting the database. Tools Hub still hardcodes false too; this template should not copy that.

Evidence: gcp.cloudrun.tf line deletion_protection = false. gcp.jobs.tf the same.

Next change: Read the YAML key, and default it to true when terraform.workspace is pro.

### AUD-INSIGHTS (p1) Cloud SQL Query Insights cannot be turned on

gcp.sql.tf hardcodes query_insights_enabled = false. Pre can live without it. Pro should be able to record slow queries without a module edit. The SQL module already accepts an insights_config object.

Evidence: gcp.sql.tf insights_config block.

Next change: Map settings.database.<id>.sql.insights over that object. Default stays off.

### AUD-PRE (p1) There is no pre workspace

settings/ holds default.yaml and a commented example. Tools Hub keeps a real pre.yaml: smaller machines, zonal SQL, scale-to-zero, backups on, private IP, a budget. A new project needs that file so pre is a workspace someone can fill in, not a copy-paste from a 900 line example.

Evidence: settings/ has no pre.yaml.

Next change: Add settings/pre.yaml with one service, one database, the shared VPC, the load balancer, the budget and placeholder project ids.

### AUD-PRO (p1) There is no pro workspace

Pro is where deletion protection, regional SQL, a warm instance, longer backups, TLS to Redis and a higher budget stop being comments. Tools Hub has settings/pro.yaml for this. The file here should be complete and obviously full of placeholders, so applying it unchanged fails on purpose until the project ids are real.

Evidence: settings/ has no pro.yaml.

Next change: Add settings/pro.yaml. Regional SQL, min_instances 1, deletion protection on, encrypted SQL, HA Redis with in-transit encryption.

### AUD-LOCK (p1) The provider lock file is gitignored

.gitignore lists *.lock.hcl. Two applies on different days can pick different provider builds inside the same pessimistic pin. Tools Hub commits the lock. A template that others clone should too.

Evidence: .gitignore contains *.lock.hcl. No .terraform.lock.hcl in the tree.

Next change: Stop ignoring the lock file, generate it with terraform init -backend=false, and commit it.

### AUD-CI (p1) Nothing checks fmt or validate on a pull request

There is no .github/workflows. A bad merge reaches main and the next person finds it at plan time, against a real project. The check is init -backend=false and validate. It does not need a GCP login.

Evidence: No .github/workflows directory.

Next change: Add a workflow that runs fmt on the root files (not the vendored modules), init -backend=false, and validate.

### AUD-SOPS (p1) Secret values have no sealed path into the plan

The template creates Secret Manager containers and a placeholder version, which is the right default, and then stops. Tools Hub also decrypts secrets/<workspace>/<service>.enc.yaml with SOPS and a Cloud KMS key at plan time, so a rotation is a commit instead of a console edit. This repo has no sops provider, no .sops.yaml and no secrets/ tree.

Evidence: versions.tf has no carlpett/sops provider.

Next change: Add an optional SOPS path: a KMS key the workspace opts into, .sops.yaml, and secret versions read from an encrypted file when it exists. Keep the placeholder when the file is absent. Do not copy the Tools Hub key ring.

### AUD-LABELS (p2) Resources do not share an environment label

Redis sets workspace, client and managed_by. Most other resources set nothing. A bill filtered by environment, or an asset search for this stack, cannot see the VPC, the database or the service. Tools Hub labels are not a module-level scheme this repo should copy. One local map is enough.

Evidence: locals.tf defines base_name and the registry host, and no common_labels.

Next change: Add local.common_labels (workspace, client, managed_by, repo) and pass it to every resource that accepts labels.

### AUD-SQL-SCHEMA (p2) Every Cloud Run service gets a database on every SQL instance

gcp.sql.tf builds the database and user lists from keys(local.app_services) and passes that list to every instance. A second database, or a service that does not use SQL, still receives a database and a user. Tools Hub declares databases on the instance entry. This template should too.

Evidence: gcp.sql.tf local.schema.databases is a for over service_names.

Next change: Read databases and users from the database YAML. Keep generating one database per service only as a default when the YAML omits the lists.

### AUD-PUBSUB-AGENT (p3) The Pub/Sub service identity is created in every workspace

google_project_service_identity.pubsub_agent has no count. A project with no topics still needs the Pub/Sub API identity, and the API is in the default list. Low impact. It breaks the rule that a missing section creates nothing.

Evidence: gcp.pubsub.tf resource google_project_service_identity.pubsub_agent.

Next change: Give it a count tied to length(local.topic_config) > 0, and keep the topic resources depending on it.

### AUD-AGENTS (p1) A session that opens this repo has no operating rules

The README explains the YAML pattern. It does not tell an agent which gaps are real, which Tools Hub ideas to leave alone, or that each fix is its own pull request. Without that, the next session re-introduces a VPC per service or copies Shieldcode.

Evidence: No AGENTS.md. No skill next to the audit.

Next change: Add AGENTS.md and docs/audit/OPERATING.md. Point both at this script.

## Accepted, do not port

### OK-MODULE-VPC (p1) Do not create one VPC per service or per module

Tools Hub does. network.tf there loops local.all_networks and gives every product a VPC whose CIDR is an md5 slice of 10.0.0.0/8, plus a NAT and Private Service Access range each. That isolates products that share one GCP project. This template is one project and one application. A second network adds peering and a second NAT for an isolation boundary the project does not have. One shared VPC, created only when the YAML asks for it, is the whole network model.

Evidence: Tools Hub network.tf module.network for_each = local.all_networks. This repo has a single module.network.

Next change: Leave it. If a later project truly needs a second network, add a map under settings.network and a for_each of one module, still not one network per Cloud Run service.

### OK-APP-SHAPE (p1) Do not nest services under a module map

Tools Hub uses module.<product>.service because one project hosts many products, and locals.tf flattens that into all_services. This repo uses app.service and app.job. The flat shape is what a single application wants. Introducing the module map would make every example and every IAM shorthand lie.

Evidence: locals in gcp.cloudrun.tf: app_services = try(local.settings.app.service, {}).

Next change: Keep app.service. Document the difference in AGENTS.md so nobody ports the hub's module key.

### OK-SHIELDCODE (p2) Do not port Shieldcode, Harbor or the Sonar quality gate

Tools Hub builds images through a Harbor proxy and fails the build on a Sonar gate. That stack is a platform service with its own robots, tokens and proxy repository. A new project does not have it. Binary Authorization, once it can require an attestation, is the control that belongs in this template.

Evidence: Tools Hub shieldcode.tf. This repo has no harbor or sonar resources.

Next change: Leave it out. Track image policy under AUD-BINAUTH.

### OK-RETENTION (p3) Do not port the data-retention sweeper

Tools Hub injects a job and a scheduler into one chosen module to delete expired rows. That is an application job. When this project needs it, it is an app.job entry, not a hidden merge in locals.tf.

Evidence: Tools Hub data_retention.tf and the merge into module_configs in locals.tf.

Next change: Leave it out.

### OK-SQL-RESIZER (p3) Do not port the nightly Cloud SQL stop/start

Tools Hub scales SQL down at night in non-prod with two Cloud Functions. Pre and pro in this template are meant to stay up. A scale-to-zero database is a later cost decision, with its own ticket, not part of becoming production-ready.

Evidence: Tools Hub sql.tf sql_resizer functions and schedulers.

Next change: Leave it out.

### OK-RENOVATE (p3) Do not port Renovate or the Docker Hub pull-through proxy

Both are Tools Hub CI hygiene for a fleet of repositories. Dependency updates for one application live in that application's repository.

Evidence: Tools Hub renovate.tf.

Next change: Leave it out.

### OK-VPCSC (p2) Do not add VPC Service Controls in this stack

A service perimeter is an organization policy. Tools Hub has vpc_sc.tf because the platform sits inside one. This template cannot own the perimeter. example.yaml already leaves access_policy commented, which is the right call.

Evidence: settings/example.yaml access_policy block, commented. No vpc_sc.tf here.

Next change: Leave it out. If the org later puts the project in a perimeter, document the perimeter id in the workspace file as a comment, do not manage it from here.

### OK-MODEL-ARMOR (p3) Do not enable Model Armor or DLP by default

Tools Hub enables modelarmor.googleapis.com and dlp.googleapis.com because several products call them. Turning them on in every new project adds APIs nobody calls. Add the API in the workspace that needs it, and remember active-apis is replaced wholesale on a shallow merge.

Evidence: settings/default.yaml has those APIs commented or absent. Tools Hub default.yaml lists both.

Next change: Leave them commented.

### OK-PULUMI (p3) Do not add the Pulumi KMS key

Tools Hub keeps a key ring some workloads still encrypt with Pulumi. This repository is Terraform. A KMS key for SOPS is AUD-SOPS. A key for Pulumi is not.

Evidence: Tools Hub kms.pulumi.tf.

Next change: Leave it out.

### OK-GROUPS (p3) Do not create Google groups from Terraform

Tools Hub has cloud_identity.tf for platform groups. Group creation is an organization process, and the identity API is easy to get wrong from a project stack. Membership in this template is a list of members on project_access and iap.

Evidence: No cloud_identity.tf in this repo.

Next change: Leave it out.

### OK-HUB-IAM (p2) Do not copy the Tools Hub viewer and admin role matrix

Tools Hub binds toolshub.viewer and toolshub.admin, plus a long custom role of datastore permissions and external_project_access into other projects. This template's project_access.viewers and operators lists match a single team. Operators currently also receive roles/cloudbuild.connectionAdmin and roles/iam.serviceAccountUser, which is broad, and tightening that is a separate small review. It is not a reason to import the hub matrix.

Evidence: gcp.iam.tf viewers and operators. Tools Hub settings/pro.yaml project_access groups.

Next change: Keep the two lists. When the project has real groups, put the group emails in settings/pre.yaml and settings/pro.yaml.

### OK-BUILD-CHAT (p3) Do not port the build-failure Chat notifier

Tools Hub posts a card to a Google Chat space for every failed build. That needs a webhook secret and a space the project does not have yet. Add it when someone names the space.

Evidence: Tools Hub cloudbuild.notifications.tf.

Next change: Leave it out.

### OK-SYS-PROJECT (p2) Do not require a separate system project

Tools Hub sends NAT and SQL monitoring at a shared ms-tool-sys project. A new stack can set project_sys to the same project as the workspace. Pre and pro should do that until a shared monitoring project exists.

Evidence: settings/default.yaml project_sys is a placeholder. The network module wants the id for NAT alerts only.

Next change: Set project_sys.id to the workspace project in pre and pro. Split it out later if several projects share one monitoring project.

### OK-SHALLOW-MERGE (p1) Keep the shallow settings merge

locals.tf uses merge(), so a map key in the workspace file replaces the whole map from default.yaml. Tools Hub has the same merge and the same rule: environment files are complete, and default.yaml holds scalars plus empty maps. A deep-merge provider would change every existing workspace in silence. The footgun to document is active-apis: do not set it in an environment file or you drop the default list.

Evidence: locals.tf settings = merge(yamldecode(defaults), yamldecode(workspace)).

Next change: Document it in AGENTS.md. Edit default.yaml when every workspace needs one more API.

### OK-CMEK (p2) Do not encrypt every resource with CMEK yet

Tools Hub has key rings for SQL, secrets, buckets, Pub/Sub, Artifact Registry, BigQuery and disks, behind a feature flag that is still off in pro. That programme is compliance work for a platform. A new project starts on Google-managed encryption. CMEK is the right follow-up when the data classification says so, and it should land as one resource family per PR, not as a copy of kms.tf.

Evidence: Tools Hub kms.tf. This repo has no google_kms_key_ring.

Next change: Leave it out until the project needs customer-managed keys. AUD-SOPS may add one key for secret files. That key does not have to wrap SQL.

### OK-HELLO-IMAGE (p3) The first Cloud Run image stays the public hello image

gcp.cloudrun.tf deploys us-docker.pkg.dev/cloudrun/container/hello and the job resource ignores later image changes. The first apply boots a placeholder. Cloud Build replaces the digest and Terraform leaves it alone. That is the same idea Tools Hub uses. Do not pin a project image in Terraform.

Evidence: gcp.cloudrun.tf image = hello. gcp.jobs.tf lifecycle.ignore_changes includes the container image.

Next change: Leave it. Document it next to the pre and pro services so nobody 'fixes' the hello image in YAML.

## Already in place

These match the Tools Hub pattern and are not gaps. Do not reopen them.

- One settings YAML per workspace, loaded in locals.tf and merged over settings/default.yaml.
- google and google-beta set user_project_override and billing_project, so API quota is billed to this project.
- Secret Manager containers with a placeholder version and ignore_changes on the payload. Real values stay out of git.
- A budget, with the billing-shutdown function only when the workspace asks for it.
- One service account per Cloud Run service, ingress defaulting to the load balancer, and direct VPC egress when a VPC exists.
- Private Cloud SQL as the example default, Cloud Armor on the load balancer, and IAP on the paths that opt in.
- A GCS backend. Workspaces share the bucket and Terraform separates them by prefix.
- Provider versions are pinned. The pin is old (see AUD-PROVIDER), but it is a pin.
