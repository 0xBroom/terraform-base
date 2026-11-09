locals {
  m_base_name        = var.base_name
  m_base_name_medium = format("%s--%s", local.m_base_name, var.module_name)

  # Only VPC_PEERING ranges can be reserved for the service networking peering.
  psa_range_keys = sort([for key, range in var.services_ip_ranges : key if range.purpose == "VPC_PEERING"])
}
