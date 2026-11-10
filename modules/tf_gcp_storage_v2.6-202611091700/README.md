## Requirements

No requirements.

## Providers

| Name | Version |
|------|---------|
| <a name="provider_google"></a> [google](#provider\_google) | n/a |
| <a name="provider_random"></a> [random](#provider\_random) | n/a |

## Modules

No modules.

## Resources

| Name | Type |
|------|------|
| [google_storage_bucket.base](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/storage_bucket) | resource |
| [google_storage_bucket_iam_member.permissions](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/storage_bucket_iam_member) | resource |
| [google_storage_bucket_iam_policy.policy](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/storage_bucket_iam_policy) | resource |
| [random_id.base](https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/id) | resource |
| [google_iam_policy.policies](https://registry.terraform.io/providers/hashicorp/google/latest/docs/data-sources/iam_policy) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_authoritative_permissions"></a> [authoritative\_permissions](#input\_authoritative\_permissions) | Set authoritative\_permissions | `bool` | `true` | no |
| <a name="input_base_name"></a> [base\_name](#input\_base\_name) | Name for the resource | `string` | n/a | yes |
| <a name="input_class"></a> [class](#input\_class) | Bucket type | `string` | `"REGIONAL"` | no |
| <a name="input_cors"></a> [cors](#input\_cors) | The cors configurations for the storage | <pre>list(object({<br>    origin          = optional(list(string), null)<br>    method          = optional(list(string), null)<br>    response_header = optional(list(string), null)<br>    max_age_seconds = optional(number, null)<br>  }))</pre> | `[]` | no |
| <a name="input_enable_versioning"></a> [enable\_versioning](#input\_enable\_versioning) | n/a | `bool` | `true` | no |
| <a name="input_force_destroy"></a> [force\_destroy](#input\_force\_destroy) | n/a | `string` | `"true"` | no |
| <a name="input_gcp_project_id"></a> [gcp\_project\_id](#input\_gcp\_project\_id) | GCP Project source | `string` | n/a | yes |
| <a name="input_lifecycle_rules"></a> [lifecycle\_rules](#input\_lifecycle\_rules) | Parameters to configure the lifecycles | <pre>map(<br>    object({<br>      age                   = number<br>      action_type           = string<br>      action_sc             = optional(string, null)<br>      matches_prefixes      = optional(list(string), [])<br>      matches_storage_class = optional(list(string), [])<br>      matches_suffix        = optional(list(string), [])<br>    })<br>  )</pre> | `{}` | no |
| <a name="input_module_name"></a> [module\_name](#input\_module\_name) | Constant for module | `string` | `"storage"` | no |
| <a name="input_permissions"></a> [permissions](#input\_permissions) | Permissions to the bucket | <pre>map(object({<br>    members = list(string)<br>    roles   = list(string)<br>  }))</pre> | `{}` | no |
| <a name="input_region_name"></a> [region\_name](#input\_region\_name) | Region name | `string` | n/a | yes |
| <a name="input_uniform_bucket_level_access"></a> [uniform\_bucket\_level\_access](#input\_uniform\_bucket\_level\_access) | n/a | `bool` | `true` | no |
| <a name="input_soft_delete_retention_duration"></a> [soft\_delete\_retention\_duration](#input\_soft\_delete\_retention\_duration) | The time that the soft delete policy retains deleted objects; if it is set to 0, this policy does not exist | `number` | 604800 | no |
| <a name="input_website"></a> [website](#input\_website) | The website configuration for the bucket. | <pre>object({<br>    main_page_suffix = optional(string, null)<br>    not_found_page   = optional(string, null)<br>  })</pre> | `null` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_bucket_name"></a> [bucket\_name](#output\_bucket\_name) | The name of the bucket |
