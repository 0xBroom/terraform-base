# Configuration Guide (YAML)

This guide explains how to manage infrastructure using the YAML settings in the `settings/` directory.

## 🚀 Basic Workflow

1. Open `settings/${workspace}.yaml`.
2. Add or modify the desired resource block.
3. Run `terraform plan` to verify the changes.
4. Run `terraform apply` to deploy.

## 🏷️ Labels

Both Google providers set `default_labels` to `local.common_labels`
(`locals.tf`), so every resource with a `labels` field gets the same four:

| Label | Value |
|---|---|
| `workspace` | the Terraform workspace |
| `client` | `client.name` |
| `managed_by` | `terraform` |
| `repo` | `iac.repo` (default `terraform-base`) |

```yaml
client:
  name: "app"
iac:
  repo: "terraform-base"
```

GCP label values take at most 63 lowercase letters, digits, `_` and `-`, so
the values are lowercased, any other character becomes `-` and the result is
cut to 63. A label set on the resource (Redis `labels`, a VM's `labels`) is
merged on top and wins on the same key. Resources without labels (IAM, DNS
records, alert policies) are not affected. Cloud SQL keeps its labels in
`user_labels`, which the provider default does not reach.

The first plan after this change shows an in-place update on every labelled
resource that did not carry the four labels yet (buckets, Cloud Run, Pub/Sub,
secrets, Artifact Registry, addresses and forwarding rules, Redis, VMs, KMS
keys, DNS zones): it adds `terraform_labels` and `effective_labels`, nothing is
replaced. Repositories adopted with `artifact_repos.<key>.adopt` get the four
labels too, next to the ones they already have.

Cloud Run domain mappings use the `google.unlabelled` provider alias, which has
no default labels: their labels are immutable, and adding one would destroy and
recreate the mapping and its certificate.

## 🔌 Enabled APIs

`gcp.enabled.apis.tf` enables one list, the distinct union of three sources:

| Source | Where | What |
|---|---|---|
| `active-apis` | `settings/default.yaml` | The base every workspace needs: Resource Manager, IAM, IAM Credentials, Compute Engine (the security baseline sets OS Login metadata), Cloud Build, Cloud Run, Artifact Registry, Cloud Storage, Secret Manager, Logging, Monitoring |
| `local.feature_apis` | `gcp.enabled.apis.tf` | The APIs of a feature, on only while the feature exists |
| `extra-apis` | workspace file | Anything else the workspace needs, for example `aiplatform.googleapis.com` |

| Feature | Turned on by | APIs |
|---|---|---|
| `database` | a `database` instance | `sqladmin`, `servicenetworking` |
| `cloud_sql_mount` | a service with `cloudrun.cloud_sql_instances_mount` or a job with `job-config.cloud_sql_instances_mount`, also without a `database` section (an instance in another project) | `sqladmin` |
| `redis` | a `redis` instance | `redis`, `servicenetworking` |
| `network` | `network.services_cidr` | `compute`, `servicenetworking`, `vpcaccess` |
| `lb` | an `lb` section | `compute` |
| `compute` | `compute_instances` or `compute_nats` | `compute` |
| `iap` | a service with `cloudrun.iap.enabled` or an IAP load balancer rule | `iap` |
| `dns` | `dns_zones`, or `elastic_psc.dns_domain` | `dns` |
| `firestore` | a `firestore` database | `firestore` |
| `pubsub` | `pubsub.topics` | `pubsub` |
| `cloud_tasks` | `cloud_tasks` queues | `cloudtasks` |
| `scheduler` | `scheduler` or `service_scheduler` jobs | `cloudscheduler` |
| `budget` | a `budget` section | `billingbudgets`, `cloudbilling` |
| `budget_auto_stop` | `budget.enable_auto_stop: true` | `cloudfunctions`, `eventarc`, `pubsub` |
| `artifact_scanning` | `security.artifact_scanning: true` | `containerscanning` |
| `binary_authorization` | `binary_authorization.enabled: true` | `binaryauthorization`, `containeranalysis`, `cloudkms` |
| `sops` | `sops.enabled: true` | `cloudkms` |
| `vpc_connector` | a job with `job-config.vpc_access.connector` | `vpcaccess` |
| `wif` | a `wif.pools` key | `sts`, `iamcredentials` |

Every gate is the expression that creates the feature's resources, so the two
cannot drift apart. A new feature that calls a new API adds a line to both maps.
Direct VPC egress (`vpc_access_enabled`, `enable_vpc_access`, a job's
`vpc_access.network_interfaces`) onto a network this stack does not create needs
Compute Engine only, which is in the base. Secrets read from another project and
Pub/Sub, Cloud Tasks or Cloud Scheduler calls to Cloud Run need no API beyond
their own feature and the base.

```yaml
# settings/<workspace>.yaml
extra-apis:
  - "aiplatform.googleapis.com"
```

Do not set `active-apis` in a workspace file: the settings merge is shallow, so
it would replace the whole base list.

An API that leaves the list is never disabled. `google_project_service` has
`disable_on_destroy = false`, so the plan shows a destroy that only drops the
entry from state, and the project keeps the API on. That is what an existing
workspace sees on the first plan after the base list got shorter, for any API
its sections do not use (Firestore, Cloud Tasks, Cloud Scheduler, DNS, Cloud
Functions and Eventarc when the auto stop is off). A feature it does use keeps
its API under the same `enabled_apis["<api>"]` address, with no change.

The APIs that had their own resource before (`wif_sts`, `binary_authorization`,
`container_analysis`, `binauth_kms`, `container_scanning`) are moved into
`enabled_apis` with `moved` blocks. Cloud KMS had two copies, one for Binary
Authorization (`binauth_kms`) and one for SOPS (`cloudkms`), and only one move
can target `enabled_apis["cloudkms.googleapis.com"]`. The Binary Authorization
copy moves; the SOPS copy (`google_project_service.cloudkms[0]`) leaves state
through a `removed` block with `destroy = false`, so no API call is made. With
Binary Authorization on, the moved entry carries on. With SOPS only,
`enabled_apis` declares the API again: the plan shows a create, and enabling an
API that is already on changes nothing in the project.

## 📦 Cloud Run Services

Services are defined under `app.service`.

### Adding a New Service

```yaml
app:
  service:
    my-new-service:
      name: "my-new-service"
      cloudrun:
        container_port: 8080
        cpu: 1
        ram: "512Mi"
        max_instances: 5
        min_instances: 0
        allow_unauthenticated: true
```

### Environment Variables & Secrets

#### Plain Text Environment Variables
```yaml
        env:
          - name: APP_COLOR
            value: "blue"
```

#### Mounting Secrets as Volumes
```yaml
        existing_secret_volume:
          - name: "config-secret"
            secret_id: "my-secret-id"
            mount_path: "/etc/secrets"
            file_name: "config.json"
```

### Storage Volumes (GCS)

You can mount GCS buckets as volumes. If `create_gcs: true`, the bucket will be created automatically.

```yaml
        gcs_volume:
          - name: "uploads"
            mount_path: "/data/uploads"
            create_gcs: true # Will create a bucket named {client}-{workspace}-{service}-uploads
```

## 🪣 GCS Buckets

Stand-alone buckets are defined under `bucket`.

```yaml
bucket:
  my-data-bucket:
    custom_name: "my-data-bucket"
    class: "STANDARD"
    region: "europe-west1"
    soft_delete_days: 7
```

Lifecycle rules, retention policies (Bucket Lock) and usage logs, and when to
use each, are in [STORAGE.md](STORAGE.md).

## 🖥️ Compute Instances (VMs)

VMs are defined under `compute_instances`.

```yaml
compute_instances:
  my-vm:
    name: "my-vm"
    zone: "us-east1-c"
    machine_type: "e2-micro"
    boot_disk:
      image: "ubuntu-os-cloud/ubuntu-2204-lts"
      size_gb: 20
```

## 🔌 Private Service Connect to Elastic Cloud

`elastic_psc` creates an internal address in the `services` subnet and a PSC
endpoint to the provider's service attachment. Without the key nothing is
created. The attachment must be in `region_name`, and `network` must be set.
`dns_domain` is optional and adds a private zone with apex and wildcard records
pointing at the endpoint.

```yaml
elastic_psc:
  service_attachment: "projects/example-provider-project/regions/europe-west1/serviceAttachments/example-attachment"
  dns_domain: "psc.example-provider.example.com"
```

## 🔐 Security & Access

### Project Operators
Define who has administrative access to the project.

```yaml
project_access:
  operators:
    - "user:admin@example.com"
```

### Security Alerts
```yaml
security:
  alerts_email: "security@example.com"
```

Every alert policy notifies this channel, so the address is required: the plan
stops with a clear error when it is missing or malformed. The settings merge is
shallow, so a workspace that declares `security:` must repeat `alerts_email`.

### Cloud Run ingress
A service without an explicit `cloudrun.ingress` gets
`INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER` when the workspace has an `lb:` section
and `INGRESS_TRAFFIC_ALL` when it has none. Without a load balancer the service
still requires IAM (`allow_unauthenticated` defaults to false).

### External CI without keys
GitHub Actions, GitLab CI or another OIDC issuer authenticate through Workload
Identity Federation (`wif`), never with a service account key. Every provider
needs an `attribute_condition`. See [WIF.md](WIF.md) for the keys and a
`google-github-actions/auth` workflow.
