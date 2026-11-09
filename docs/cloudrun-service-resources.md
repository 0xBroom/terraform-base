
# Recursos Creados al Definir un Nuevo Servicio Cloud Run

Este documento explica los recursos de Google Cloud Platform (GCP) que se aprovisionan automáticamente al definir un nuevo servicio Cloud Run en los archivos de configuración YAML del proyecto (`settings/*.yaml`). La configuración centralizada permite la creación dinámica de una infraestructura completa y segura con una definición mínima.

Al añadir una entrada bajo `app.service` en el archivo YAML de entorno (ej. `pre.yaml`), se desencadena la creación de los siguientes recursos:

---

## 1. Servicio Cloud Run y Cuenta de Servicio

Cada servicio Cloud Run definido genera:

*   **Servicio Cloud Run**: El servicio de contenedores serverless que ejecuta tu aplicación, configurado con las especificaciones de CPU, RAM, concurrencia, y tiempo de espera (`timeout`) definidas en el YAML.
    ```yaml
    app:
      my-service:
        cloudrun:
          min_instances: 0
          max_instances: 2
          container_port: 8080
          cpu: 1
          ram: "512Mi"
    ```

*   **Cuenta de Servicio Dedicada**: Se crea una cuenta de servicio específica para cada instancia de Cloud Run. Esta cuenta se utiliza para la autenticación y autorización del servicio, siguiendo el principio de mínimos privilegios. Su nombre sigue el patrón `{client.name}-{service.name}-sa@{project.id}.iam.gserviceaccount.com` (ej. `my-service-sa@proyect-name.iam.gserviceaccount.com`).

*   **Acceso a VPC**: El servicio Cloud Run se configura para utilizar un conector VPC, permitiendo la comunicación privada con otros recursos dentro de la red VPC (bases de datos, Redis, etc.), con todo el tráfico saliente (`egress: "ALL_TRAFFIC"`) enrutado a través de la VPC.

*   **Roles IAM Adicionales (Opcional)**: Si se especifican roles adicionales en el YAML (`additional_roles`), estos se otorgan a la cuenta de servicio de Cloud Run (ej. `roles/aiplatform.user` para servicios de IA).

---

## 2. Secret Manager

Para cada secreto de entorno (`secret_env`) o volumen (`secret_volume`) definido en la configuración del servicio Cloud Run:

*   **Secreto en Secret Manager**: Se crea un secreto en Google Secret Manager. Su nombre puede ser `raw_name` (sin prefijo) o seguir el patrón `{client.name}-{service.name}-{secret.name}`.
    ```yaml
    app:
      my-service:
        cloudrun:
          secret_env:
            - name: MY_API_KEY
              var_name: API_KEY
              version: latest
            - name: my-db-password # Con raw_name: true
              var_name: DB_PASS
              raw_name: true
          secret_volume:
            - name: my-credentials
              file_name: credentials.json
              mount_path: "/etc/secrets"
    ```

*   **Versión del Secreto**: Se crea una versión inicial del secreto con un valor `PLACEHOLDER_VALUE_TO_BE_REPLACED`. Este valor debe ser actualizado manualmente después del despliegue. Terraform está configurado para ignorar los cambios en el `secret_data` de las versiones para permitir la gestión externa.

*   **Acceso IAM al Secreto**: Se otorga el rol `roles/secretmanager.secretAccessor` a la cuenta de servicio del Cloud Run (o del Job) para que pueda acceder al secreto en tiempo de ejecución. Esto garantiza que solo los servicios autorizados puedan recuperar los valores de los secretos.

---

## 3. Cloud Build (CI/CD)

Cada servicio Cloud Run con una configuración `cloudbuild` definida automáticamente obtiene:

*   **Cloud Build Trigger**: Un disparador de Cloud Build se crea y se vincula al repositorio de Bitbucket especificado (`repo_name`) para automatizar el proceso de CI/CD. Este disparador se activa en push a tags que coinciden con un patrón (ej. `pre-[0-9]{8}[0-9]{2}`).
    ```yaml
    app:
      my-service:
        cloudbuild:
          repo_name: "my-service-repo"
          inline: true
          cloudbuild_file_path: "services-cloudbuild.yaml"
          dockerfile_path: "Dockerfile"
    ```

*   **Configuración de Build**: La configuración del build puede ser `inline` (definida directamente en el YAML a través de un archivo `cloudbuild_files/*.yaml`) o referenciar un archivo `cloudbuild.yaml` externo en el repositorio. Los `substitutions` se generan dinámicamente para pasar variables como región, nombre del servicio, rutas de Dockerfile y contexto de build.

*   **Cuenta de Servicio de Cloud Build**: Una cuenta de servicio unificada de Cloud Build (`cloudbuild-sa`) se utiliza para todos los disparadores. Se le otorgan permisos amplios como `roles/run.admin`, `roles/iam.serviceAccountUser`, `roles/artifactregistry.writer`, y `roles/storage.objectAdmin` para permitirle desplegar servicios, gestionar imágenes de Docker y acceder a recursos de almacenamiento.

---

## 4. Cloud SQL (Base de Datos PostgreSQL)

Aunque la instancia de Cloud SQL suele ser un recurso compartido, al definir un nuevo servicio Cloud Run que requiere acceso a la base de datos, se crean los siguientes recursos *dentro de la instancia de Cloud SQL existente*:

*   **Base de Datos Dedicada**: Se crea una base de datos específica para el servicio (ej. `my-service-db`).
    ```yaml
    app:
      my-service:
        cloudrun:
          env:
            - name: DATABASE_NAME
              value: my-service-db
            - name: DATABASE_USER
              value: my-service-app-user
    ```

*   **Usuario de Base de Datos**: Se crea un usuario de base de datos específico para el servicio (ej. `my-service-app-user`) con un password generado automáticamente y almacenado en Secret Manager. La cuenta de servicio de Cloud Run obtiene acceso a este secreto.

*   **Conexión Cloud SQL**: La configuración del Cloud Run incluye `cloud_sql_instances_mount` para permitir que el servicio se conecte a la instancia de Cloud SQL a través de un socket UNIX, lo que es el método más seguro y recomendado por GCP.

---

## 5. Cloud Storage (Buckets)

Si el servicio Cloud Run necesita interactuar con buckets de Cloud Storage (ej. para almacenar assets, miniaturas o archivos de procesamiento), se configura:

*   **Permisos en Buckets Existentes**: Se otorgan roles de IAM específicos (ej. `roles/storage.objectAdmin`, `roles/storage.objectViewer`) a la cuenta de servicio del Cloud Run para los buckets que se definan en la sección `bucket` del YAML, con miembros como `cloudrun:my-service` transformados en el email de la cuenta de servicio.
    ```yaml
    bucket:
      assets:
        permissions:
          creator:
            members: ["cloudrun:my-service"]
            roles: ["roles/storage.objectAdmin"]
    ```

---

## 6. Balanceador de Carga (Load Balancer) e IAP

Si el servicio Cloud Run debe ser accesible desde internet y se configura con reglas de `loadbalancer` en el YAML:

*   **Network Endpoint Group (NEG)**: Se crea un Network Endpoint Group (NEG) serverless que apunta al servicio Cloud Run. Esto permite que el Balanceador de Carga dirija el tráfico directamente al servicio Cloud Run.

*   **Backend Service**: Se crea un servicio de backend que utiliza el NEG del Cloud Run. Este backend es el que se asocia con el URL Map del Balanceador de Carga.

*   **Reglas de URL Map**: Se añaden reglas al URL Map existente del Balanceador de Carga para enrutar el tráfico a tu servicio Cloud Run basándose en los `paths` y `rewrite` definidos en la configuración `loadbalancer.rules` del YAML.
    ```yaml
    app:
      my-service:
        loadbalancer:
          rules:
            - path: "/my-service/*"
              rewrite: "/"
              iap:
                enabled: false
    ```

*   **IAP (Identity-Aware Proxy)**: Si se habilita IAP en las reglas del balanceador de carga (`iap.enabled: true`):
    *   Se configura el Backend Service para que utilice IAP.
    *   Se añaden los `members` especificados (o los miembros por defecto si `use_default_members: true`) a la política de IAM de IAP con el rol `roles/iap.httpsResourceAccessor`, permitiendo el acceso autenticado y autorizado al servicio.

---

## 7. Cloud DNS

Aunque no se crea un recurso DNS por cada servicio, al inicializar la infraestructura, se configuran recursos DNS que benefician a todos los servicios Cloud Run:

*   **Zona DNS Privada para Cloud Run**: Se establece una zona DNS privada para `run.app.` vinculada a la VPC del proyecto. Esto permite que los servicios dentro de la VPC resuelvan los nombres de dominio internos de Cloud Run (ej. `my-service-xxx.region.run.app`) de forma privada, sin pasar por la red pública de internet.

*   **Registro A para Cloud Run**: Se crea un registro `A` comodín (`*.run.app.`) que apunta a los rangos de IP internos de GCP para servicios privados (`199.36.153.8/30`).

---
