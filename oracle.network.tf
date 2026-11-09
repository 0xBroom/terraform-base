locals {
  oracle_compartment_id = try(local.settings.oracle.compartment_id, "")
  oracle_networks       = try(local.settings.oracle.networks, {})
}

resource "oci_core_vcn" "main" {
  for_each = local.oracle_networks

  cidr_block     = each.value.cidr_blocks[0]
  cidr_blocks    = each.value.cidr_blocks
  compartment_id = local.oracle_compartment_id

  display_name            = each.key
  dns_label               = each.value.dns_label
  ipv6private_cidr_blocks = []
  is_ipv6enabled          = false
  security_attributes     = {}

  lifecycle {
    ignore_changes = [
      defined_tags,
      freeform_tags
    ]
  }
}
