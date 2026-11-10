
# Resources created when you define a new Cloud Run service

This document lists the Google Cloud resources that are provisioned automatically when you define a new Cloud Run service in the project's YAML settings (`settings/*.yaml`). The central configuration builds a complete, secure stack from a minimal definition.

Adding an entry under `app.service` in an environment's YAML file (for example `pre.yaml`) creates the following resources.

---

## 1. Cloud Run service and service account

Each Cloud Run service you define creates:

*   **Cloud Run service**: the serverless container service that runs your application, with the CPU, memory, concurrency and `timeout` set in the YAML.
    ```yaml
    app:
      service:
        my-service:
          cloudrun:
            min_instances: 0
            max_instances: 2
            container_port: 8080
            cpu: 1
            ram: "512Mi"
    ```

*   **Dedicated service account**: one service account per Cloud Run service, used to authenticate and authorise it, following least privilege. Its name follows the pattern `{client.name}-{service.name}-sa@{project.id}.iam.gserviceaccount.com` (for example `example-app-my-service-sa@example-app-pre.iam.gserviceaccount.com`). Set `cloudrun.external_sa` to use an existing account instead.

*   **VPC access**: the service is attached to the VPC so it can talk privately to other resources in the network (databases, Redis, and so on). By default all outbound traffic (`egress: "ALL_TRAFFIC"`) is routed through the VPC.

*   **Additional IAM roles (optional)**: roles listed in `additional_roles` are granted to the service account (for example `roles/aiplatform.user` for AI workloads).

---

## 2. Secret Manager

For each environment secret (`secret_env`) or secret volume (`secret_volume`) declared on the service:

*   **Secret Manager secret**: a secret is created. Its name is either the plain `name` (with `raw_name: true`) or follows the pattern `{client.name}-{service.name}-{secret.name}`.
    ```yaml
    app:
      service:
        my-service:
          cloudrun:
            secret_env:
              - name: MY_API_KEY
                var_name: API_KEY
                version: latest
              - name: my-db-password # with raw_name: true
                var_name: DB_PASS
                raw_name: true
            secret_volume:
              - name: my-credentials
                file_name: credentials.json
                mount_path: "/etc/secrets"
    ```

*   **Secret version**: a first version is created with the value `PLACEHOLDER_VALUE_TO_BE_REPLACED`. Replace it by hand after the deployment. Terraform ignores changes to `secret_data` on these versions so the value can be managed outside Terraform.

*   **IAM access to the secret**: the service account of the Cloud Run service (or job) gets `roles/secretmanager.secretAccessor` on the secret, so it can read it at runtime. Only authorised services can read the secret values.

---

## 3. Cloud Build (CI/CD)

Each Cloud Run service with a `cloudbuild` block gets:

*   **Cloud Build trigger**: a trigger linked to the connected repository (`repo_name`, Bitbucket or GitHub) that automates CI/CD. By default it fires on tags matching `<workspace>-[0-9]{8}[0-9]{2}` (for example `pre-2025010112`).
    ```yaml
    app:
      service:
        my-service:
          cloudbuild:
            repo_name: "my-service-repo"
            inline: true
            cloudbuild_file_path: "cloudbuild.yaml"
            dockerfile_path: "Dockerfile"
    ```

*   **Build configuration**: the build is either `inline` (read from a file under `cloudbuild_files/` and stored in the trigger) or reads a `cloudbuild.yaml` from the application repository. Substitutions are generated to pass values such as the region, the service name, the Dockerfile path and the build context. See `docs/cloudbuild-pipeline.md`.

*   **Cloud Build service account**: one shared account (`run-cloudbuild-sa`) runs every trigger. It holds `roles/cloudbuild.builds.builder`, `roles/run.admin`, `roles/iam.serviceAccountUser`, `roles/artifactregistry.writer` and `roles/logging.logWriter`, so it can build and push images and deploy services.

---

## 4. Cloud SQL (PostgreSQL)

The Cloud SQL instance is usually shared. When an instance omits its own `databases` and `users` lists, every Cloud Run service gets the following *inside that instance*:

*   **Dedicated database**: a database for the service (for example `my-service-db`).
    ```yaml
    app:
      service:
        my-service:
          cloudrun:
            env:
              - name: DATABASE_NAME
                value: my-service-db
              - name: DATABASE_USER
                value: my-service-app-user
    ```

*   **Database user**: a user for the service (for example `my-service-app-user`) with a generated password stored in Secret Manager. The service account of the Cloud Run service can read that secret.

*   **Cloud SQL connection**: `cloud_sql_instances_mount` on the service mounts the instance through a UNIX socket, the connection method GCP recommends.

---

## 5. Cloud Storage (buckets)

If the service needs Cloud Storage buckets (for example for assets, thumbnails or processing files):

*   **Permissions on buckets**: IAM roles (for example `roles/storage.objectAdmin`, `roles/storage.objectViewer`) are granted to the service account on the buckets declared in the `bucket` section of the YAML. Members written as `cloudrun:my-service` are turned into the email of that service account.
    ```yaml
    bucket:
      assets:
        permissions:
          creator:
            members: ["cloudrun:my-service"]
            roles: ["roles/storage.objectAdmin"]
    ```

---

## 6. Load balancer and IAP

If the service must be reachable from the internet and has `loadbalancer` rules in the YAML:

*   **Network endpoint group (NEG)**: a serverless NEG that points at the Cloud Run service, so the load balancer can send traffic straight to it.

*   **Backend service**: a backend service that uses the NEG. This is the backend the load balancer's URL map points at.

*   **URL map rules**: rules added to the load balancer's URL map route traffic to the service by the `path` and `rewrite` values in `loadbalancer.rules`.
    ```yaml
    app:
      service:
        my-service:
          loadbalancer:
            rules:
              - path: "/my-service/*"
                rewrite: "/"
                iap:
                  enabled: false
    ```

*   **IAP (Identity-Aware Proxy)**: when a rule enables IAP (`iap.enabled: true`):
    *   the backend service is configured to use IAP;
    *   the listed `members` (or the shared members under `iap.admin_access` when `use_default_members: true`) get `roles/iap.httpsResourceAccessor`, which allows authenticated and authorised access to the service.

---

## 7. Cloud DNS

No DNS resource is created per service. Public zones are declared once per workspace under `dns_zones` (see `gcp.dns.tf`) and serve every service behind the load balancer.

---
