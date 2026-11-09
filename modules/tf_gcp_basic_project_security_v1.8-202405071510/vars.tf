# Constant for module
variable "module_name" {
  type    = string
  default = "security"
}

variable "base_name" {
  type        = string
  description = "Base name"
}

variable "gcp_project_id" {
  type        = string
  description = "GCP Project ID"
}

variable "audit_logging" {
  type = object({
    admin_read = optional(bool, true)
    data_read  = optional(bool, false)
    data_write = optional(bool, false)
  })

  default = {}
}

// In this case notification channels are required to fully remove all SCC alerts
variable "notification_channels" {
  type        = list(any)
  description = "List of notification channel resources"
}
