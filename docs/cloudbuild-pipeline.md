# The Cloud Build pipeline

One file — `cloudbuild_files/cloudbuild.yaml` — builds every image in this project. It
contains no service names, no build arguments, no image paths and no timeouts. Anything
that differs between two services is **data in `settings/<workspace>.yaml`**, turned into
Cloud Build substitutions by `gcp.cloudbuild.tf` at plan time.

The rule that follows from that: **you never edit the pipeline to give one service what
it needs.** If you find yourself about to, the key you are looking for is below.

```
settings/<workspace>.yaml          gcp.cloudbuild.tf              cloudbuild.yaml
  app.service.<svc>.cloudbuild  →  local.all_cloudbuild_configs →  substitutions
    build_args: {K: v}          →  _BUILD_ARGS                  →  docker build --build-arg
    job_name / deploy / …       →  local.cloudbuild_capabilities → x-when filter on steps
```

## Giving an image a build-time variable

```yaml
app:
  service:
    leader-web:
      cloudbuild:
        repo_name: "leader-web"
        build_args:
          SITE_ENV: "dev"
```

Terraform renders every entry into one deterministic string, sorted by key and
single-quoted, and the pipeline passes it verbatim to `docker build`:

```
--build-arg SITE_ENV='dev'
```

Single quotes are what make an arbitrary value safe: `$`, backticks, globs, spaces and
newlines cannot reach the shell, and an embedded quote is escaped the POSIX way
(`'\''`). A value containing `${_FOO}` is inserted literally — Cloud Build substitutes
once and never re-expands what it inserted.

Two consequences worth knowing:

- **An argument the Dockerfile does not declare is dropped by docker**, with a warning.
  Passing one is harmless; forgetting one is not.
- **An argument you stop declaring here restores the Dockerfile's own `ARG` default.**
  Before removing one, read the Dockerfile.

## Every key, and what it does

All of them live under `cloudbuild:` in a service, a job, or a top-level `cloudbuild`
entry. `settings/example.yaml` carries the same list with inline comments.

| Key | Default | What it does |
|---|---|---|
| `repo_name` | — | mandatory; the connected repository |
| `provider` | `repo_providers.default` | `github` or `bitbucket` |
| `inline` | `false` | `true`: pipeline read from `cloudbuild_files/`. `false`: from the application repository, and only `substitutions` reach it |
| `cloudbuild_file_path` | `cloudbuild.yaml` | which pipeline file |
| `dockerfile_path` | `Dockerfile` | matched literally — `dockerfile` is a different file |
| `build_context_path` | `.` | what docker sees; a Dockerfile that `COPY`s from its own directory needs that directory |
| `build_args` | `{}` | **any** build-time variable, as a map |
| `docker_target` | — | `--target=<stage>` for a multi-stage Dockerfile. Not a build arg |
| `image` | `<client>-<svc>/<svc>` | Artifact Registry path, or a job's `job-config.image` minus the tag |
| `image_base` | — | passed as `--build-arg IMAGE_BASE`, resolved against this project's registry when it has no host of its own |
| `reqs_file` | — | passed as `--build-arg REQS_FILE` |
| `artifact_registry_token` | `false` | adds a step that mints an access token and passes it as `--build-arg GOOGLE_ACCESS_TOKEN`. Only for images that install private packages from Artifact Registry |
| `build_timeout` | pipeline's `1800s` | per-service build timeout |
| `machine_type` | pipeline's default worker | a bigger builder |
| `deploy` | `true` | `false` builds and pushes without touching Cloud Run |
| `job_name` | — | a Cloud Run **job** that shares this service's image; the build repoints it at the digest it just pushed |
| `cloudrun.region` (outside the `cloudbuild` block) | `region_name` | where the service lives, and therefore where the build deploys it |
| `branch_pattern` / `tag_pattern` | tag `^<workspace>-YYYYMMDDNN$` | what fires the trigger |
| `build_filter_paths` | — | only build when these paths changed (branch triggers) |
| `substitutions` | `{}` | raw Cloud Build substitutions, for a pipeline this repository cannot see |

## Optional steps: `x-when`

A step in the pipeline may carry `x-when: [flag, ...]` — a Terraform-only key, ANDed,
absent meaning unconditional. Terraform keeps the step only if every flag is on for that
service, then **rewrites the `waitFor` of the steps that survived**, so removing a step
never leaves a dangling dependency. A flag that is not a real capability is a plan
error, never a step that silently stops running.

| Capability | On when |
|---|---|
| `ar_token` | `artifact_registry_token: true` |
| `deploy_service` | the entry is a service (or a raw build) and `deploy` is not `false` |
| `deploy_job` | the entry is a Cloud Run job and `deploy` is not `false` |
| `update_companion_job` | a service declared `job_name` |

Because the `x-*` keys are not Cloud Build syntax, the file is a **Terraform-only
artifact**: `gcloud builds submit --config cloudbuild_files/cloudbuild.yaml` rejects it.
Read it with the renderer instead.

## Seeing what a service actually builds

```bash
bin/cloudbuild-render.py my-workspace --list          # every build, with its capabilities
bin/cloudbuild-render.py my-workspace my-service      # the effective pipeline, substituted
bin/cloudbuild-render.py my-workspace my-service --raw # …with ${_PLACEHOLDERS} intact
```

The renderer is a reader; Terraform is the source of truth. What keeps the two honest is
a check against a real plan:

```bash
terraform workspace select my-workspace
terraform plan -refresh=false -out=/tmp/w.plan
terraform show -json /tmp/w.plan > /tmp/w.json
bin/cloudbuild-render.py my-workspace --check-plan /tmp/w.json
```

It compares every planned trigger's steps, order, `waitFor` and substitutions with what
the renderer produces, and exits non-zero on the first disagreement. Run it whenever you
change `gcp.cloudbuild.tf` or the pipeline.

And the pipeline's own self-test, which needs no credentials:

```bash
python3 bin/cloudbuild-render-test.py    # exit 0 required
```

## Traps that have already cost time here

- **Cloud Build reads `$WORD` anywhere in the pipeline file, comments included**, as a
  substitution, and refuses a name that is not a valid builtin. Shell variables inside a
  step are lowercase; a literal dollar for the shell is `$$`.
- **`ALLOW_LOOSE` is forced on triggered builds**: an unset custom substitution becomes
  an empty string instead of an error. Nothing tells you a variable never arrived — the
  image just builds with the Dockerfile's default. This is exactly how the dev door of
  `leader-web` was served with production's `robots.txt`: the value was declared under
  `substitutions:` while the shared pipeline only ever passed a fixed list of build args.
- **A substitution is not expanded inside another substitution.** Everything is resolved
  in Terraform, in full, which is why `_IMAGE` is a literal path and not a template.
- **An external pipeline (`inline: false`) is handed as little as possible**: the naming
  substitutions, the registry helpers, and whatever `substitutions:` declares — never
  `_IMAGE`, `_BUILD_ARGS`, `_DOCKER_TARGET` or `_JOB_NAME`. A file this repository cannot
  read may treat an unset substitution as a signal; a common pattern is one that
  falls back to `${_IMAGE_BASE}:${SHORT_SHA}` when `$_IMAGE` is empty. Defining one for
  it would quietly change what it builds.
- **The rollout goes where the resource is.** Three services live in `us-east1` while the
  project's region is `europe-west1`, so the deploy step uses `_DEPLOY_REGION` (the
  service's own `cloudrun.region`) and the job steps use `_JOB_REGION`. `gcloud run
  deploy` with the wrong region does not fail — it creates a second service.
- **Cloud Run pins the image digest at deploy time.** A job that shares a service's image
  keeps running the digest it was created with until something updates it — that is what
  `job_name` is for.
