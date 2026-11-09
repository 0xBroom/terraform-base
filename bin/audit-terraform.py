#!/usr/bin/env python3
"""Audit this Terraform template against the Tools Hub production pattern.

The baseline is the YAML-driven stack in ms_tool_hub_iac (one settings file per
workspace, generic resources, private data stores, a security baseline). This
template was cut from an older copy of that pattern. The audit lists what is
still missing for a project that has to run in pre and pro, and what must stay
out because it only exists to host many products in one platform project.

    python3 bin/audit-terraform.py            # print the backlog
    python3 bin/audit-terraform.py --write    # refresh docs/audit/BACKLOG.md
    python3 bin/audit-terraform.py --fail-on p0

Exit 0 unless --fail-on is set and an open item is at that severity or above.
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

SEVERITY_RANK = {"p0": 0, "p1": 1, "p2": 2, "p3": 3}


def read(rel: str) -> str:
    path = ROOT / rel
    if not path.is_file():
        return ""
    return path.read_text(encoding="utf-8")


def exists(rel: str) -> bool:
    return (ROOT / rel).is_file()


def network_is_optional() -> bool:
    text = read("gcp.network.tf")
    return "count " in text and "network_enabled" in text


def bucket_is_guarded() -> bool:
    return "try(local.settings.bucket" in read("gcp.storage.tf")


def firewall_uses_settings_cidr() -> bool:
    text = read("gcp.firewall.tf")
    return "10.20.0.0/24" not in text and "services_cidr" in text


def vpc_follows_network() -> bool:
    run = read("gcp.cloudrun.tf")
    jobs = read("gcp.jobs.tf")
    return "local.network_enabled" in run and "local.network_enabled" in jobs


def audit_admin_read_on() -> bool:
    text = read("gcp.security.tf")
    return "security.audit_logging.admin_read" in text


def deletion_protection_from_settings() -> bool:
    return (
        "cloudrun.deletion_protection" in read("gcp.cloudrun.tf")
        and "job-config.deletion_protection" in read("gcp.jobs.tf")
    )


def insights_from_settings() -> bool:
    return "sql.insights" in read("gcp.sql.tf")


def settings_env(name: str, required: tuple[str, ...]) -> bool:
    text = read(f"settings/{name}.yaml")
    return bool(text) and all(piece in text for piece in required)


def pre_settings() -> bool:
    return settings_env(
        "pre",
        ("project:", "security:", "network:", "database:", "app:", "budget:", "lb:"),
    )


def pro_settings() -> bool:
    text = read("settings/pro.yaml")
    return settings_env(
        "pro",
        ("project:", "security:", "network:", "database:", "app:", "budget:", "lb:"),
    ) and 'availability: "REGIONAL"' in text and "min_instances: 1" in text


def lockfile_committed() -> bool:
    ignored = any(
        line.strip() == "*.lock.hcl" for line in read(".gitignore").splitlines()
    )
    return (not ignored) and exists(".terraform.lock.hcl")


def ci_validates() -> bool:
    workflows = ROOT / ".github" / "workflows"
    if not workflows.is_dir():
        return False
    return any(
        "terraform validate" in path.read_text(encoding="utf-8")
        for path in workflows.glob("*.yml")
    )


def sops_provider() -> bool:
    return "carlpett/sops" in read("versions.tf")


def provider_major_7() -> bool:
    versions = read("versions.tf")
    return 'source  = "hashicorp/google"' in versions and "~> 7." in versions


def security_module_current() -> bool:
    text = read("gcp.security.tf")
    return "tf_gcp_basic_project_security_v1.8" not in text


def networking_module_current() -> bool:
    text = read("gcp.network.tf")
    return "tf_gcp_networking_v3.5" not in text


def storage_module_has_pap() -> bool:
    paths = sorted((ROOT / "modules").glob("tf_gcp_storage_*/vars.tf"))
    return any("public_access_prevention" in path.read_text(encoding="utf-8") for path in paths)


def cloudrun_module_current() -> bool:
    return "tf_gcp_cloudrun_v2_v6.5" not in read("gcp.cloudrun.tf")


def common_labels() -> bool:
    return "common_labels" in read("locals.tf")


def sql_databases_from_yaml() -> bool:
    text = read("gcp.sql.tf")
    # Today every Cloud Run service name becomes a database on every instance.
    return "for service in local.service_names" not in text


def pubsub_agent_optional() -> bool:
    text = read("gcp.pubsub.tf")
    return "count " in text.split("google_project_service_identity", 1)[-1][:400]


def binary_auth_can_enforce() -> bool:
    text = read("gcp.binary_auth.tf")
    return "ALWAYS_ALLOW" not in text


def log_retention() -> bool:
    return "google_logging_project_bucket_config" in read("gcp.security.tf") or exists(
        "gcp.logging.tf"
    )


def codeowners() -> bool:
    return exists("CODEOWNERS") or exists(".github/CODEOWNERS")


def agents_guide() -> bool:
    text = read("AGENTS.md")
    return "bin/audit-terraform.py" in text and "BACKLOG.md" in text


# Each item: id, severity, title, why, evidence, change, ok, disposition.
# disposition "fix" flips to done when ok() is true.
# disposition "accepted" is a decision, not a gap. ok is ignored.

ITEMS: list[dict] = [
    {
        "id": "AUD-NET",
        "severity": "p0",
        "title": "The shared VPC is created even when the workspace has no network section",
        "why": (
            "gcp.network.tf reads local.settings.network.* with no guard, and the "
            "firewall, Cloud SQL private IP and Cloud Run VPC attachment all assume "
            "that module exists. A workspace that only needs Cloud Run behind a load "
            "balancer cannot plan. Tools Hub creates networks with for_each and skips "
            "a product that has none. This template needs the same switch, for one VPC, "
            "not one VPC per service."
        ),
        "evidence": "gcp.network.tf module.network has no count. gcp.firewall.tf always binds to it.",
        "change": "Create the VPC only when settings.network.services_cidr is set. Point every consumer at module.network[0] through that flag.",
        "ok": network_is_optional,
        "disposition": "fix",
    },
    {
        "id": "AUD-VPC-DEFAULT",
        "severity": "p0",
        "title": "Cloud Run and jobs attach to the VPC by default",
        "why": (
            "gcp.cloudrun.tf defaults vpc_access_enabled to true, and gcp.jobs.tf "
            "defaults enable_vpc_access to true. With the VPC made optional, those "
            "defaults would still name a network that does not exist. Direct VPC "
            "egress is the right default only when this project actually has the "
            "shared VPC. Tools Hub does the same kind of gating with feature flags."
        ),
        "evidence": "gcp.cloudrun.tf vpc_access_enabled default true. gcp.jobs.tf enable_vpc_access default true.",
        "change": "Default both to local.network_enabled. A service can still opt in or out in YAML.",
        "ok": vpc_follows_network,
        "disposition": "fix",
    },
    {
        "id": "AUD-FW-CIDR",
        "severity": "p1",
        "title": "The internal firewall allows two CIDRs the VPC does not have",
        "why": (
            "allow_internal_vpc permits 10.10.1.0/24, 10.20.0.0/24 and 10.20.1.0/24. "
            "Only the first is the services subnet in settings/example.yaml. The other "
            "two match nothing this stack creates: Cloud SQL and Redis use Private "
            "Service Access, not those ranges. A project that picks a different "
            "services_cidr gets a firewall for the wrong subnet."
        ),
        "evidence": "gcp.firewall.tf source_ranges.",
        "change": "Use settings.network.services_cidr plus an optional extra_internal_cidrs list.",
        "ok": firewall_uses_settings_cidr,
        "disposition": "fix",
    },
    {
        "id": "AUD-BUCKET",
        "severity": "p0",
        "title": "A workspace with no bucket key cannot plan",
        "why": (
            "gcp.storage.tf iterates local.settings.bucket directly. Every other map "
            "in this repo uses try(..., {}). The README says a missing section creates "
            "nothing. Buckets are the exception, so the first plan of a new project fails "
            "before it creates anything."
        ),
        "evidence": "gcp.storage.tf for_each = local.settings.bucket.",
        "change": "Guard the map with try(local.settings.bucket, {}).",
        "ok": bucket_is_guarded,
        "disposition": "fix",
    },
    {
        "id": "AUD-AUDIT",
        "severity": "p0",
        "title": "Admin-read audit logs are off",
        "why": (
            "gcp.security.tf sets admin_read, data_read and data_write to false. "
            "Tools Hub turns admin_read on and leaves data_read and data_write off, "
            "because data access logs are expensive and admin activity is the trail "
            "you need when someone changes IAM or firewalls. A production project "
            "without admin-read logs cannot answer who changed what."
        ),
        "evidence": "gcp.security.tf audit_logging block, all three flags false.",
        "change": "Default admin_read to true. Allow settings.security.audit_logging to override each flag. Keep data_read and data_write off unless a workspace asks.",
        "ok": audit_admin_read_on,
        "disposition": "fix",
    },
    {
        "id": "AUD-DELETE",
        "severity": "p0",
        "title": "Cloud Run services and jobs can be destroyed with deletion_protection left false",
        "why": (
            "gcp.cloudrun.tf and gcp.jobs.tf hardcode deletion_protection = false. "
            "Cloud SQL already defaults it to true inside its module. A pro workspace "
            "should have to opt out of protecting the service and the job, the same "
            "way it has to opt out of protecting the database. Tools Hub still hardcodes "
            "false too; this template should not copy that."
        ),
        "evidence": "gcp.cloudrun.tf line deletion_protection = false. gcp.jobs.tf the same.",
        "change": "Read the YAML key, and default it to true when terraform.workspace is pro.",
        "ok": deletion_protection_from_settings,
        "disposition": "fix",
    },
    {
        "id": "AUD-INSIGHTS",
        "severity": "p1",
        "title": "Cloud SQL Query Insights cannot be turned on",
        "why": (
            "gcp.sql.tf hardcodes query_insights_enabled = false. Pre can live without "
            "it. Pro should be able to record slow queries without a module edit. The "
            "SQL module already accepts an insights_config object."
        ),
        "evidence": "gcp.sql.tf insights_config block.",
        "change": "Map settings.database.<id>.sql.insights over that object. Default stays off.",
        "ok": insights_from_settings,
        "disposition": "fix",
    },
    {
        "id": "AUD-PRE",
        "severity": "p1",
        "title": "There is no pre workspace",
        "why": (
            "settings/ holds default.yaml and a commented example. Tools Hub keeps a "
            "real pre.yaml: smaller machines, zonal SQL, scale-to-zero, backups on, "
            "private IP, a budget. A new project needs that file so pre is a workspace "
            "someone can fill in, not a copy-paste from a 900 line example."
        ),
        "evidence": "settings/ has no pre.yaml.",
        "change": "Add settings/pre.yaml with one service, one database, the shared VPC, the load balancer, the budget and placeholder project ids.",
        "ok": pre_settings,
        "disposition": "fix",
    },
    {
        "id": "AUD-PRO",
        "severity": "p1",
        "title": "There is no pro workspace",
        "why": (
            "Pro is where deletion protection, regional SQL, a warm instance, longer "
            "backups, TLS to Redis and a higher budget stop being comments. Tools Hub "
            "has settings/pro.yaml for this. The file here should be complete and "
            "obviously full of placeholders, so applying it unchanged fails on purpose "
            "until the project ids are real."
        ),
        "evidence": "settings/ has no pro.yaml.",
        "change": "Add settings/pro.yaml. Regional SQL, min_instances 1, deletion protection on, encrypted SQL, HA Redis with in-transit encryption.",
        "ok": pro_settings,
        "disposition": "fix",
    },
    {
        "id": "AUD-LOCK",
        "severity": "p1",
        "title": "The provider lock file is gitignored",
        "why": (
            ".gitignore lists *.lock.hcl. Two applies on different days can pick "
            "different provider builds inside the same pessimistic pin. Tools Hub "
            "commits the lock. A template that others clone should too."
        ),
        "evidence": ".gitignore contains *.lock.hcl. No .terraform.lock.hcl in the tree.",
        "change": "Stop ignoring the lock file, generate it with terraform init -backend=false, and commit it.",
        "ok": lockfile_committed,
        "disposition": "fix",
    },
    {
        "id": "AUD-CI",
        "severity": "p1",
        "title": "Nothing checks fmt or validate on a pull request",
        "why": (
            "There is no .github/workflows. A bad merge reaches main and the next "
            "person finds it at plan time, against a real project. The check is "
            "init -backend=false and validate. It does not need a GCP login."
        ),
        "evidence": "No .github/workflows directory.",
        "change": "Add a workflow that runs fmt on the root files (not the vendored modules), init -backend=false, and validate.",
        "ok": ci_validates,
        "disposition": "fix",
    },
    {
        "id": "AUD-SOPS",
        "severity": "p1",
        "title": "Secret values have no sealed path into the plan",
        "why": (
            "The template creates Secret Manager containers and a placeholder version, "
            "which is the right default, and then stops. Tools Hub also decrypts "
            "secrets/<workspace>/<service>.enc.yaml with SOPS and a Cloud KMS key at "
            "plan time, so a rotation is a commit instead of a console edit. This "
            "repo has no sops provider, no .sops.yaml and no secrets/ tree."
        ),
        "evidence": "versions.tf has no carlpett/sops provider.",
        "change": "Add an optional SOPS path: a KMS key the workspace opts into, .sops.yaml, and secret versions read from an encrypted file when it exists. Keep the placeholder when the file is absent. Do not copy the Tools Hub key ring.",
        "ok": sops_provider,
        "disposition": "fix",
    },
    {
        "id": "AUD-PROVIDER",
        "severity": "p2",
        "title": "The Google provider is pinned to 6.42 while Tools Hub is on 7.42",
        "why": (
            "versions.tf asks for hashicorp/google ~> 6.42.0 and Terraform >= 1.10. "
            "Tools Hub is on ~> 7.42 and Terraform >= 1.14. The vendored modules in "
            "this repo were written against the 6.x provider. A major bump is a "
            "review of those modules, not a one-line edit."
        ),
        "evidence": "versions.tf required_providers.google version ~> 6.42.0.",
        "change": "Open one PR that bumps Terraform and both Google providers, runs validate, and notes every module argument the new provider rejects.",
        "ok": provider_major_7,
        "disposition": "fix",
    },
    {
        "id": "AUD-MOD-SEC",
        "severity": "p2",
        "title": "The security baseline module is the May 2024 snapshot",
        "why": (
            "modules/tf_gcp_basic_project_security_v1.8-202405071510 is what this "
            "repo vendors. A newer snapshot exists in a private registry. Copying "
            "that source into this public repository is not allowed. Upgrade when "
            "a republishable module exists. Until then this is a decision, not an "
            "open task."
        ),
        "evidence": "gcp.security.tf source = ./modules/tf_gcp_basic_project_security_v1.8-202405071510.",
        "change": "Leave the vendored snapshot. Vendor a newer module only if it can be republished.",
        "ok": security_module_current,
        "disposition": "accepted",
    },
    {
        "id": "AUD-MOD-NET",
        "severity": "p2",
        "title": "The networking module is the March 2025 snapshot",
        "why": (
            "modules/tf_gcp_networking_v3.5-202503101237. A newer snapshot exists "
            "in a private registry. Same rule as the security module: do not copy "
            "it into this public repository."
        ),
        "evidence": "gcp.network.tf source path contains tf_gcp_networking_v3.5.",
        "change": "Leave the vendored snapshot. Vendor a newer module only if it can be republished.",
        "ok": networking_module_current,
        "disposition": "accepted",
    },
    {
        "id": "AUD-MOD-RUN",
        "severity": "p2",
        "title": "The Cloud Run module is the February 2025 snapshot",
        "why": (
            "modules/tf_gcp_cloudrun_v2_v6.5-202502191120. A newer snapshot exists "
            "in a private registry and cannot be copied here. Root files already "
            "pass command, args, probes and direct VPC egress, so the YAML is not "
            "missing those features."
        ),
        "evidence": "gcp.cloudrun.tf source path contains tf_gcp_cloudrun_v2_v6.5.",
        "change": "Leave the vendored snapshot. Upgrade when a republishable module is available. Do not fork the copy in place.",
        "ok": cloudrun_module_current,
        "disposition": "accepted",
    },
    {
        "id": "AUD-PAP",
        "severity": "p2",
        "title": "Buckets cannot set public access prevention",
        "why": (
            "The storage module (v2.5, June 2024) exposes uniform_bucket_level_access "
            "and defaults it to true, which Tools Hub also does. It has no "
            "public_access_prevention argument. Uniform access stops ACLs. Public "
            "access prevention stops a later allUsers binding from making the bucket "
            "public. Both belong on a production bucket."
        ),
        "evidence": "modules/tf_gcp_storage_v2.6-202611091700/vars.tf defaults public_access_prevention to enforced.",
        "change": "Add the argument to the vendored module, default it to enforced, and thread a YAML override through gcp.storage.tf. Bump the directory version suffix so the edit is visible.",
        "ok": storage_module_has_pap,
        "disposition": "fix",
    },
    {
        "id": "AUD-LABELS",
        "severity": "p2",
        "title": "Resources do not share an environment label",
        "why": (
            "Redis sets workspace, client and managed_by. Most other resources set "
            "nothing. A bill filtered by environment, or an asset search for this "
            "stack, cannot see the VPC, the database or the service. Tools Hub labels "
            "are not a module-level scheme this repo should copy. One local map is enough."
        ),
        "evidence": "locals.tf defines base_name and the registry host, and no common_labels.",
        "change": "Add local.common_labels (workspace, client, managed_by, repo) and pass it to every resource that accepts labels.",
        "ok": common_labels,
        "disposition": "fix",
    },
    {
        "id": "AUD-SQL-SCHEMA",
        "severity": "p2",
        "title": "Every Cloud Run service gets a database on every SQL instance",
        "why": (
            "gcp.sql.tf builds the database and user lists from keys(local.app_services) "
            "and passes that list to every instance. A second database, or a service "
            "that does not use SQL, still receives a database and a user. Tools Hub "
            "declares databases on the instance entry. This template should too."
        ),
        "evidence": "gcp.sql.tf local.schema.databases is a for over service_names.",
        "change": "Read databases and users from the database YAML. Keep generating one database per service only as a default when the YAML omits the lists.",
        "ok": sql_databases_from_yaml,
        "disposition": "fix",
    },
    {
        "id": "AUD-PUBSUB-AGENT",
        "severity": "p3",
        "title": "The Pub/Sub service identity is created in every workspace",
        "why": (
            "google_project_service_identity.pubsub_agent has no count. A project "
            "with no topics still needs the Pub/Sub API identity, and the API is in "
            "the default list. Low impact. It breaks the rule that a missing section "
            "creates nothing."
        ),
        "evidence": "gcp.pubsub.tf resource google_project_service_identity.pubsub_agent.",
        "change": "Give it a count tied to length(local.topic_config) > 0, and keep the topic resources depending on it.",
        "ok": pubsub_agent_optional,
        "disposition": "fix",
    },
    {
        "id": "AUD-BINAUTH",
        "severity": "p2",
        "title": "Binary Authorization, when turned on, only dry-runs an allow-all rule",
        "why": (
            "gcp.binary_auth.tf sets evaluation_mode ALWAYS_ALLOW and enforcement_mode "
            "DRYRUN_AUDIT_LOG_ONLY. Switching binary_authorization.enabled to true does "
            "not reject an unsigned image. Tools Hub pairs Binary Authorization with "
            "a signer key and a real policy. A dry-run allow-all is a useful first "
            "step and a bad place to stop for pro."
        ),
        "evidence": "gcp.binary_auth.tf default_admission_rule.",
        "change": "Let the YAML choose ALWAYS_ALLOW or REQUIRE_ATTESTATION, and default pro to dry-run only until an attestor exists. Do not pretend the current policy enforces anything.",
        "ok": binary_auth_can_enforce,
        "disposition": "fix",
    },
    {
        "id": "AUD-LOGS",
        "severity": "p3",
        "title": "Log buckets keep the Google default retention",
        "why": (
            "There is no google_logging_project_bucket_config. Admin activity is on "
            "once AUD-AUDIT lands, and then expires on Google's default. A production "
            "project usually wants _Default and _Required retention written down."
        ),
        "evidence": "No gcp.logging.tf. gcp.security.tf creates the notification channel and the security module only.",
        "change": "Add a small logging file driven by settings.logging.retention_days, with a sane default of 30 for pre and 90 for pro.",
        "ok": log_retention,
        "disposition": "fix",
    },
    {
        "id": "AUD-CODEOWNERS",
        "severity": "p3",
        "title": "No CODEOWNERS file",
        "why": (
            "Anyone with write access can change a pro setting and a module in the "
            "same review with nobody named. A one-line CODEOWNERS is enough until "
            "the project has a team."
        ),
        "evidence": "No CODEOWNERS at the repo root or under .github/.",
        "change": "Add CODEOWNERS when the project has a GitHub team or user to name. Do not invent an owner.",
        "ok": codeowners,
        "disposition": "fix",
    },
    {
        "id": "AUD-AGENTS",
        "severity": "p1",
        "title": "A session that opens this repo has no operating rules",
        "why": (
            "The README explains the YAML pattern. It does not tell an agent which "
            "gaps are real, which Tools Hub ideas to leave alone, or that each fix "
            "is its own pull request. Without that, the next session re-introduces "
            "a VPC per service or copies Shieldcode."
        ),
        "evidence": "No AGENTS.md. No skill next to the audit.",
        "change": "Add AGENTS.md and docs/audit/OPERATING.md. Point both at this script.",
        "ok": agents_guide,
        "disposition": "fix",
    },
    {
        "id": "OK-MODULE-VPC",
        "severity": "p1",
        "title": "Do not create one VPC per service or per module",
        "why": (
            "Tools Hub does. network.tf there loops local.all_networks and gives "
            "every product a VPC whose CIDR is an md5 slice of 10.0.0.0/8, plus a "
            "NAT and Private Service Access range each. That isolates products that "
            "share one GCP project. This template is one project and one application. "
            "A second network adds peering and a second NAT for an isolation boundary "
            "the project does not have. One shared VPC, created only when the YAML "
            "asks for it, is the whole network model."
        ),
        "evidence": "Tools Hub network.tf module.network for_each = local.all_networks. This repo has a single module.network.",
        "change": "Leave it. If a later project truly needs a second network, add a map under settings.network and a for_each of one module, still not one network per Cloud Run service.",
        "ok": lambda: True,
        "disposition": "accepted",
    },
    {
        "id": "OK-APP-SHAPE",
        "severity": "p1",
        "title": "Do not nest services under a module map",
        "why": (
            "Tools Hub uses module.<product>.service because one project hosts many "
            "products, and locals.tf flattens that into all_services. This repo uses "
            "app.service and app.job. The flat shape is what a single application "
            "wants. Introducing the module map would make every example and every "
            "IAM shorthand lie."
        ),
        "evidence": "locals in gcp.cloudrun.tf: app_services = try(local.settings.app.service, {}).",
        "change": "Keep app.service. Document the difference in AGENTS.md so nobody ports the hub's module key.",
        "ok": lambda: True,
        "disposition": "accepted",
    },
    {
        "id": "OK-SHIELDCODE",
        "severity": "p2",
        "title": "Do not port Shieldcode, Harbor or the Sonar quality gate",
        "why": (
            "Harbor and SonarQube need a separate instance, with robots, tokens and "
            "a proxy repository. This template does not port them. Scans that run "
            "inside Cloud Build (gitleaks, semgrep, trivy fs) and Artifact Registry "
            "vulnerability scanning are opt-in and do not need that instance."
        ),
        "evidence": "No harbor or sonar resources. cloudbuild.scan and security.artifact_scanning cover the in-build scanners.",
        "change": "Leave Harbor and Sonar out. Turn scanners on with cloudbuild.scan and security.artifact_scanning.",
        "ok": lambda: True,
        "disposition": "accepted",
    },
    {
        "id": "OK-RETENTION",
        "severity": "p3",
        "title": "Do not port the data-retention sweeper",
        "why": (
            "Tools Hub injects a job and a scheduler into one chosen module to delete "
            "expired rows. That is an application job. When this project needs it, "
            "it is an app.job entry, not a hidden merge in locals.tf."
        ),
        "evidence": "Tools Hub data_retention.tf and the merge into module_configs in locals.tf.",
        "change": "Leave it out.",
        "ok": lambda: True,
        "disposition": "accepted",
    },
    {
        "id": "OK-SQL-RESIZER",
        "severity": "p3",
        "title": "Do not port the nightly Cloud SQL stop/start",
        "why": (
            "Tools Hub scales SQL down at night in non-prod with two Cloud Functions. "
            "Pre and pro in this template are meant to stay up. A scale-to-zero "
            "database is a later cost decision, with its own ticket, not part of "
            "becoming production-ready."
        ),
        "evidence": "Tools Hub sql.tf sql_resizer functions and schedulers.",
        "change": "Leave it out.",
        "ok": lambda: True,
        "disposition": "accepted",
    },
    {
        "id": "OK-RENOVATE",
        "severity": "p3",
        "title": "Do not port Renovate or the Docker Hub pull-through proxy",
        "why": (
            "Both are Tools Hub CI hygiene for a fleet of repositories. Dependency "
            "updates for one application live in that application's repository."
        ),
        "evidence": "Tools Hub renovate.tf.",
        "change": "Leave it out.",
        "ok": lambda: True,
        "disposition": "accepted",
    },
    {
        "id": "OK-VPCSC",
        "severity": "p2",
        "title": "Do not add VPC Service Controls in this stack",
        "why": (
            "A service perimeter is an organization policy. Tools Hub has vpc_sc.tf "
            "because the platform sits inside one. This template cannot own the "
            "perimeter. example.yaml already leaves access_policy commented, which "
            "is the right call."
        ),
        "evidence": "settings/example.yaml access_policy block, commented. No vpc_sc.tf here.",
        "change": "Leave it out. If the org later puts the project in a perimeter, document the perimeter id in the workspace file as a comment, do not manage it from here.",
        "ok": lambda: True,
        "disposition": "accepted",
    },
    {
        "id": "OK-MODEL-ARMOR",
        "severity": "p3",
        "title": "Do not enable Model Armor or DLP by default",
        "why": (
            "Tools Hub enables modelarmor.googleapis.com and dlp.googleapis.com "
            "because several products call them. Turning them on in every new "
            "project adds APIs nobody calls. Add the API in the workspace that "
            "needs it, and remember active-apis is replaced wholesale on a shallow merge."
        ),
        "evidence": "settings/default.yaml has those APIs commented or absent. Tools Hub default.yaml lists both.",
        "change": "Leave them commented.",
        "ok": lambda: True,
        "disposition": "accepted",
    },
    {
        "id": "OK-PULUMI",
        "severity": "p3",
        "title": "Do not add the Pulumi KMS key",
        "why": (
            "Tools Hub keeps a key ring some workloads still encrypt with Pulumi. "
            "This repository is Terraform. A KMS key for SOPS is AUD-SOPS. A key "
            "for Pulumi is not."
        ),
        "evidence": "Tools Hub kms.pulumi.tf.",
        "change": "Leave it out.",
        "ok": lambda: True,
        "disposition": "accepted",
    },
    {
        "id": "OK-GROUPS",
        "severity": "p3",
        "title": "Do not create Google groups from Terraform",
        "why": (
            "Tools Hub has cloud_identity.tf for platform groups. Group creation "
            "is an organization process, and the identity API is easy to get wrong "
            "from a project stack. Membership in this template is a list of members "
            "on project_access and iap."
        ),
        "evidence": "No cloud_identity.tf in this repo.",
        "change": "Leave it out.",
        "ok": lambda: True,
        "disposition": "accepted",
    },
    {
        "id": "OK-HUB-IAM",
        "severity": "p2",
        "title": "Do not copy the Tools Hub viewer and admin role matrix",
        "why": (
            "Tools Hub binds toolshub.viewer and toolshub.admin, plus a long custom "
            "role of datastore permissions and external_project_access into other "
            "projects. This template's project_access.viewers and operators lists "
            "match a single team. Operators currently also receive "
            "roles/cloudbuild.connectionAdmin and roles/iam.serviceAccountUser, "
            "which is broad, and tightening that is a separate small review. It is "
            "not a reason to import the hub matrix."
        ),
        "evidence": "gcp.iam.tf viewers and operators. Tools Hub settings/pro.yaml project_access groups.",
        "change": "Keep the two lists. When the project has real groups, put the group emails in settings/pre.yaml and settings/pro.yaml.",
        "ok": lambda: True,
        "disposition": "accepted",
    },
    {
        "id": "OK-BUILD-CHAT",
        "severity": "p3",
        "title": "Do not port the build-failure Chat notifier",
        "why": (
            "Tools Hub posts a card to a Google Chat space for every failed build. "
            "That needs a webhook secret and a space the project does not have yet. "
            "Add it when someone names the space."
        ),
        "evidence": "Tools Hub cloudbuild.notifications.tf.",
        "change": "Leave it out.",
        "ok": lambda: True,
        "disposition": "accepted",
    },
    {
        "id": "OK-SYS-PROJECT",
        "severity": "p2",
        "title": "Do not require a separate system project",
        "why": (
            "Tools Hub sends NAT and SQL monitoring at a shared ms-tool-sys project. "
            "A new stack can set project_sys to the same project as the workspace. "
            "Pre and pro should do that until a shared monitoring project exists."
        ),
        "evidence": "settings/default.yaml project_sys is a placeholder. The network module wants the id for NAT alerts only.",
        "change": "Set project_sys.id to the workspace project in pre and pro. Split it out later if several projects share one monitoring project.",
        "ok": lambda: True,
        "disposition": "accepted",
    },
    {
        "id": "OK-SHALLOW-MERGE",
        "severity": "p1",
        "title": "Keep the shallow settings merge",
        "why": (
            "locals.tf uses merge(), so a map key in the workspace file replaces the "
            "whole map from default.yaml. Tools Hub has the same merge and the same "
            "rule: environment files are complete, and default.yaml holds scalars "
            "plus empty maps. A deep-merge provider would change every existing "
            "workspace in silence. The footgun to document is active-apis: do not "
            "set it in an environment file or you drop the default list."
        ),
        "evidence": "locals.tf settings = merge(yamldecode(defaults), yamldecode(workspace)).",
        "change": "Document it in AGENTS.md. Edit default.yaml when every workspace needs one more API.",
        "ok": lambda: True,
        "disposition": "accepted",
    },
    {
        "id": "OK-CMEK",
        "severity": "p2",
        "title": "Do not encrypt every resource with CMEK yet",
        "why": (
            "Tools Hub has key rings for SQL, secrets, buckets, Pub/Sub, Artifact "
            "Registry, BigQuery and disks, behind a feature flag that is still off "
            "in pro. That programme is compliance work for a platform. A new project "
            "starts on Google-managed encryption. CMEK is the right follow-up when "
            "the data classification says so, and it should land as one resource "
            "family per PR, not as a copy of kms.tf."
        ),
        "evidence": "Tools Hub kms.tf. This repo has no google_kms_key_ring.",
        "change": "Leave it out until the project needs customer-managed keys. AUD-SOPS may add one key for secret files. That key does not have to wrap SQL.",
        "ok": lambda: True,
        "disposition": "accepted",
    },
    {
        "id": "OK-HELLO-IMAGE",
        "severity": "p3",
        "title": "The first Cloud Run image stays the public hello image",
        "why": (
            "gcp.cloudrun.tf deploys us-docker.pkg.dev/cloudrun/container/hello and the "
            "job resource ignores later image changes. The first apply boots a "
            "placeholder. Cloud Build replaces the digest and Terraform leaves it "
            "alone. That is the same idea Tools Hub uses. Do not pin a project image "
            "in Terraform."
        ),
        "evidence": "gcp.cloudrun.tf image = hello. gcp.jobs.tf lifecycle.ignore_changes includes the container image.",
        "change": "Leave it. Document it next to the pre and pro services so nobody 'fixes' the hello image in YAML.",
        "ok": lambda: True,
        "disposition": "accepted",
    },
]


def status_of(item: dict) -> str:
    if item["disposition"] == "accepted":
        return "accepted"
    return "done" if item["ok"]() else "open"


def selected(items: list[dict], fail_on: str | None) -> list[dict]:
    if fail_on is None:
        return []
    ceiling = SEVERITY_RANK[fail_on]
    return [
        item
        for item in items
        if status_of(item) == "open" and SEVERITY_RANK[item["severity"]] <= ceiling
    ]


def render(items: list[dict]) -> str:
    rows = [(item, status_of(item)) for item in items]
    counts = {"open": 0, "done": 0, "accepted": 0}
    for _, status in rows:
        counts[status] += 1

    def section(title: str, status: str) -> str:
        block = [f"## {title}", ""]
        found = [item for item, item_status in rows if item_status == status]
        if not found:
            block.append("None.")
            block.append("")
            return "\n".join(block)
        for item in found:
            block.append(f"### {item['id']} ({item['severity']}) {item['title']}")
            block.append("")
            block.append(item["why"])
            block.append("")
            block.append(f"Evidence: {item['evidence']}")
            block.append("")
            block.append(f"Next change: {item['change']}")
            block.append("")
        return "\n".join(block)

    already = """## Already in place

These match the Tools Hub pattern and are not gaps. Do not reopen them.

- One settings YAML per workspace, loaded in locals.tf and merged over settings/default.yaml.
- google and google-beta set user_project_override and billing_project, so API quota is billed to this project.
- Secret Manager containers with a placeholder version and ignore_changes on the payload. Real values stay out of git.
- A budget, with the billing-shutdown function only when the workspace asks for it.
- One service account per Cloud Run service, ingress defaulting to the load balancer, and direct VPC egress when a VPC exists.
- Private Cloud SQL as the example default, Cloud Armor on the load balancer, and IAP on the paths that opt in.
- A GCS backend. Workspaces share the bucket and Terraform separates them by prefix.
- Provider versions are pinned. The pin is old (see AUD-PROVIDER), but it is a pin.
"""

    header = f"""# Audit backlog

Compared on 2026-11-09 with a production YAML-driven GCP stack (its
settings, locals, network, security, SQL, KMS and provider pins). This
repository is that template: root files `gcp.*.tf`, vendored `tf_gcp_*`
modules, one workspace file per environment.

Open: {counts['open']}. Done: {counts['done']}. Accepted, do not port: {counts['accepted']}.

Regenerate this file with `python3 bin/audit-terraform.py --write` in the same
pull request that closes an item. The status comes from the code, not from
this prose. How a session picks the next item: `docs/audit/OPERATING.md`.

"""
    parts = [
        header,
        section("Open", "open"),
        section("Done", "done"),
        section("Accepted, do not port", "accepted"),
        already,
    ]
    return "\n".join(parts).rstrip() + "\n"


def print_summary(items: list[dict]) -> None:
    for item in items:
        status = status_of(item)
        print(f"{status:8} {item['severity']:3} {item['id']:16} {item['title']}")


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--write",
        action="store_true",
        help="write docs/audit/BACKLOG.md",
    )
    parser.add_argument(
        "--fail-on",
        choices=("p0", "p1", "p2", "p3"),
        help="exit 1 when an open item is at this severity or above",
    )
    parser.add_argument("--id", help="print one item and exit 0 if it is done or accepted")
    args = parser.parse_args(argv)

    items = ITEMS
    if args.id:
        match = [item for item in items if item["id"] == args.id]
        if not match:
            print(f"unknown id {args.id}", file=sys.stderr)
            return 2
        item = match[0]
        print(f"{status_of(item)} {item['id']} {item['title']}")
        print(item["why"])
        return 0 if status_of(item) != "open" else 1

    print_summary(items)
    text = render(items)
    if args.write:
        destination = ROOT / "docs" / "audit" / "BACKLOG.md"
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_text(text, encoding="utf-8")
        print(f"wrote {destination.relative_to(ROOT)}")

    failing = selected(items, args.fail_on)
    if failing:
        print(f"{len(failing)} open item(s) at or above {args.fail_on}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
