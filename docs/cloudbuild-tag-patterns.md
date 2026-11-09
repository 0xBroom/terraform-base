# Managing Cloud Build Triggers via Tag Patterns

This document explains how Cloud Build triggers are implemented and managed in this infrastructure, specifically focusing on the **Tag Pattern** mechanism used to initiate builds.

## 1. Overview

In this project, Cloud Build triggers are:
- **Defined in Terraform**: Using the `google_cloudbuild_trigger` resource in `project.cloudbuild.tf`.
- **Configured via YAML**: In `settings/${workspace}.yaml` files (e.g., `my-workspace.yaml`).
- **Triggered by Git Tags**: Builds are automatically started when a git tag matching a specific REGEX pattern is pushed to the repository.
- **Provider Agnostic**: Supports both GitHub and Bitbucket repositories.

## 2. Default Tag Pattern Behavior

By default, if no specific pattern is defined in the YAML configuration, the system automatically assigns a tag pattern based on the current environment (workspace).

The default pattern logic in `project.cloudbuild.tf` is:
```hcl
tag_pattern = try(value.tag_pattern, format("^%s-[0-9]{8}[0-9]{2}$", terraform.workspace))
```

### Default Pattern Format
`^{workspace}-YYYYMMDDHH$`

**Examples:**
- **Environment: `my-workspace`** -> Pattern: `^my-workspace-[0-9]{8}[0-9]{2}$` (e.g., tag `my-workspace-2024021501`)
- **Environment: `dev`** -> Pattern: `^dev-[0-9]{8}[0-9]{2}$` (e.g., tag `dev-2024021501`)

## 3. Configuration (How to Manage)

You can override the default tag pattern or define new triggers by editing the **YAML settings files**.

### File Location
- `settings/my-workspace.yaml`
- `settings/default.yaml`

### Configuration Structure

You can define `tag_pattern` inside the `cloudbuild` block of an application.

#### Example: Overriding for a specific service
In `settings/my-workspace.yaml`:

```yaml
app:
  service:
    multiweb-nuxt:
      name: "multiweb-nuxt"
      cloudrun: { ... }
      cloudbuild:
        repo_name: "multiweb-nuxt"
        provider: "github" # optional, defaults to settings.repo_providers.default
        # Custom tag pattern override
        tag_pattern: "^release-v[0-9]+.[0-9]+.[0-9]+$" 
```
*This will trigger on tags like `release-v1.0.0`, `release-v2.1.5`.*

## 4. Implementation Details (Codebase)

### `project.cloudbuild.tf`
This file contains the logic that creates the Cloud Build trigger resource. It maps the tag pattern to the repository push event.

```hcl
resource "google_cloudbuild_trigger" "cloudbuild_triggers" {
  for_each = local.all_cloudbuild_configs

  # ... configuration ...

  repository_event_config {
    repository = local.repo_id_map["${each.value.provider}/${each.value.repo_name}"]
    push {
      tag = each.value.tag_pattern
    }
  }
}
```

### `locals.tf` & `project.cloudbuild.tf` (Locals)
The defaults and merging logic are handled in the `locals` block of `project.cloudbuild.tf`.

## 5. How to Deploy & Trigger

### To Update the Pattern:
1. Modify `settings/${workspace}.yaml`.
2. Run `terraform apply`.
3. This updates the Cloud Build trigger configuration in GCP.

### To Trigger a Build:
1. Commit your code to the configured repository.
2. Create and push a tag matching the configured pattern.

```bash
# Example for default my-workspace environment pattern
git tag my-workspace-2024021501
git push origin my-workspace-2024021501
```

3. GCP Cloud Build will detect the tag and start the pipeline.

