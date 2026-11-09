# Constant for module
variable "module_name" {
  type    = string
  default = "storage"
}

variable "base_name" {
  type        = string
  description = "Name for the resource"
}

variable "region_name" {
  type        = string
  description = "Region name"
}

variable "class" {
  type        = string
  description = "Bucket type"
  default     = "REGIONAL"
}

variable "gcp_project_id" {
  type        = string
  description = "GCP Project source"
}

variable "permissions" {
  type = map(object({
    members = list(string)
    roles   = list(string)
  }))
  description = "Permissions to the bucket"
  default     = {}
}

variable "authoritative_permissions" {
  type        = bool
  description = "Set authoritative_permissions"
  default     = true
}

variable "force_destroy" {
  type    = string
  default = "true"
}

variable "enable_versioning" {
  type    = bool
  default = true
}

variable "uniform_bucket_level_access" {
  type    = bool
  default = true
}

variable "public_access_prevention" {
  description = "enforced stops a later allUsers binding from making the bucket public."
  type        = string
  default     = "enforced"
}

variable "lifecycle_rules" {
  type = map(
    object({
      age                   = number
      action_type           = string
      action_sc             = optional(string, null)
      matches_prefixes      = optional(list(string), [])
      matches_storage_class = optional(list(string), [])
      matches_suffix        = optional(list(string), [])
    })
  )

  validation {
    condition     = alltrue([for item in var.lifecycle_rules : (item.action_sc == null && item.action_type != "SetStorageClass") || (item.action_sc != null && item.action_type == "SetStorageClass")])
    error_message = "With the action_type SetStorageClass you must configure the destination storage class with action_sc."
  }

  validation {
    condition     = alltrue([for item in var.lifecycle_rules : contains(["Delete", "SetStorageClass", "AbortIncompleteMultipartUpload"], item.action_type)])
    error_message = "The action_type option only supports the 'Delete', 'SetStorageClass' and 'AbortIncompleteMultipartUpload' options (case sensitive)."
  }

  validation {
    condition     = alltrue([for item in var.lifecycle_rules : contains(["STANDARD", "MULTI_REGIONAL", "REGIONAL", "NEARLINE", "COLDLINE", "ARCHIVE"], item.action_sc != null ? item.action_sc : "ARCHIVE")])
    error_message = "The action_sc option only supports the 'STANDARD', 'MULTI_REGIONAL', 'REGIONAL', 'NEARLINE', 'COLDLINE' and 'ARCHIVE' options (case sensitive)."
  }

  description = "Parameters to configure the lifecycles"
  default     = {}
}


variable "website" {
  type = object({
    main_page_suffix = optional(string, null)
    not_found_page   = optional(string, null)
  })

  description = "The website configuration for the bucket."
  default     = null
}

variable "cors" {
  type = list(object({
    origin          = optional(list(string), null)
    method          = optional(list(string), null)
    response_header = optional(list(string), null)
    max_age_seconds = optional(number, null)
  }))

  description = "The cors configurations for the storage"
  default     = []
}

variable "soft_delete_retention_duration" {
  type        = number
  description = "The time that the soft delete policy retains deleted objects; if it is set to 0, this policy does not exist"
  default     = 604800
}

variable "autoclass" {
  type = object({
    enabled                = bool
    terminal_storage_class = optional(string, "ARCHIVE")
  })
  description = "Autoclass configuration for the bucket. Set to null to disable."
  default     = null
}

variable "use_random_suffix" {
  type        = bool
  description = "Append a random hex suffix to the bucket name. Set to false to use the base name as-is."
  default     = true
}
