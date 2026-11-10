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
