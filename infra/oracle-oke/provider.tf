terraform {
  required_version = ">= 1.0"
  required_providers {
    oci = {
      source  = "oracle/oci"
      version = "~> 6.0"
    }
  }
}

# Oracle Cloud provider
provider "oci" {
  region       = var.region
  fingerprint  = var.fingerprint
  user_ocid    = var.user_ocid
  tenancy_ocid = var.tenancy_ocid
  private_key_path = var.private_key_path
}

# Use the current compartment for resources
data "oci_identity_compartments" "current_compartment" {
  compartment_id = var.tenancy_ocid
  filter {
    name   = "name"
    values = [var.compartment_name]
  }
}

locals {
  compartment_id = one(data.oci_identity_compartments.current_compartment.compartments[*].id)
}
