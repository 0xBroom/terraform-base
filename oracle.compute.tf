locals {
  oracle_instances = try(local.settings.oracle.instances, {})
}

resource "oci_core_instance" "main" {
  for_each = local.oracle_instances

  async                      = null
  availability_domain        = each.value.availability_domain
  cluster_placement_group_id = null
  compartment_id             = local.oracle_compartment_id

  display_name      = each.key
  extended_metadata = {}
  fault_domain      = "FAULT-DOMAIN-2"

  metadata = {
    ssh_authorized_keys = each.value.ssh_authorized_keys
  }

  preserve_boot_volume                    = null
  preserve_data_volumes_created_at_launch = null
  security_attributes                     = {}
  shape                                   = each.value.shape
  state                                   = "RUNNING"
  update_operation_constraint             = null

  agent_config {
    are_all_plugins_disabled = false
    is_management_disabled   = false
    is_monitoring_disabled   = false

    plugins_config {
      desired_state = "DISABLED"
      name          = "Vulnerability Scanning"
    }
    plugins_config {
      desired_state = "DISABLED"
      name          = "Management Agent"
    }
    plugins_config {
      desired_state = "ENABLED"
      name          = "Custom Logs Monitoring"
    }
    plugins_config {
      desired_state = "DISABLED"
      name          = "Compute RDMA GPU Monitoring"
    }
    plugins_config {
      desired_state = "ENABLED"
      name          = "Compute Instance Monitoring"
    }
    plugins_config {
      desired_state = "DISABLED"
      name          = "Compute HPC RDMA Auto-Configuration"
    }
    plugins_config {
      desired_state = "DISABLED"
      name          = "Compute HPC RDMA Authentication"
    }
    plugins_config {
      desired_state = "ENABLED"
      name          = "Cloud Guard Workload Protection"
    }
    plugins_config {
      desired_state = "DISABLED"
      name          = "Block Volume Management"
    }
    plugins_config {
      desired_state = "DISABLED"
      name          = "Bastion"
    }
  }

  availability_config {
    is_live_migration_preferred = false
    recovery_action             = "RESTORE_INSTANCE"
  }

  create_vnic_details {
    assign_ipv6ip             = false
    assign_private_dns_record = false
    assign_public_ip          = "true"

    display_name           = "main-vnic"
    hostname_label         = "main-vnic"
    nsg_ids                = [for k in try(each.value.nsg_keys, []) : oci_core_network_security_group.main[k].id]
    private_ip             = each.value.private_ip
    security_attributes    = {}
    skip_source_dest_check = false
    subnet_id              = each.value.subnet_id
  }

  instance_options {
    are_legacy_imds_endpoints_disabled = false
  }

  launch_options {
    boot_volume_type                    = "PARAVIRTUALIZED"
    firmware                            = "UEFI_64"
    is_consistent_volume_naming_enabled = true
    is_pv_encryption_in_transit_enabled = true
    network_type                        = "PARAVIRTUALIZED"
    remote_data_volume_type             = "PARAVIRTUALIZED"
  }

  shape_config {
    memory_in_gbs = each.value.memory_in_gbs
    nvmes         = 0
    ocpus         = each.value.ocpus
    vcpus         = each.value.ocpus
  }

  source_details {
    boot_volume_size_in_gbs         = each.value.boot_volume_size_in_gbs
    boot_volume_vpus_per_gb         = "10"
    is_preserve_boot_volume_enabled = false
    kms_key_id                      = null
    source_id                       = each.value.source_id
    source_type                     = "image"
  }

  lifecycle {
    ignore_changes = [
      defined_tags,
      freeform_tags
    ]
  }
}
