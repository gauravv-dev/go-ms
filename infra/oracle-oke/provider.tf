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

# Get the root compartment (tenancy) for Always Free resources
data "oci_identity_tenancy" "tenancy" {
  tenancy_id = var.tenancy_ocid
}

# Use the tenancy OCID directly as compartment_id for simplicity
# This works for the root compartment which has Always Free eligibility
locals {
  compartment_id = var.tenancy_ocid
}
