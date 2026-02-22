# ===================================================================
# VCN (Virtual Cloud Network)
# ===================================================================

resource "oci_core_vcn" "oke_vcn" {
  compartment_id = local.compartment_id
  cidr_block     = var.vcn_cidr
  display_name   = "${var.cluster_name}-vcn"
  dns_label      = "okevcn"

  freeform_tags = var.freeform_tags
}

# Internet Gateway
resource "oci_core_internet_gateway" "igw" {
  compartment_id = local.compartment_id
  vcn_id         = oci_core_vcn.oke_vcn.id
  display_name   = "${var.cluster_name}-igw"
  enabled        = true

  freeform_tags = var.freeform_tags
}

# NAT Gateway (for nodes to pull images)
resource "oci_core_nat_gateway" "nat" {
  compartment_id = local.compartment_id
  vcn_id         = oci_core_vcn.oke_vcn.id
  display_name   = "${var.cluster_name}-nat"
  block_traffic  = false

  freeform_tags = var.freeform_tags
}

# Route Table for public subnet
resource "oci_core_route_table" "public_rt" {
  compartment_id = local.compartment_id
  vcn_id         = oci_core_vcn.oke_vcn.id
  display_name   = "${var.cluster_name}-public-rt"

  route_rules {
    network_entity_id = oci_core_internet_gateway.igw.id
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
  }

  freeform_tags = var.freeform_tags
}

# Route Table for private subnet (nodes)
resource "oci_core_route_table" "private_rt" {
  compartment_id = local.compartment_id
  vcn_id         = oci_core_vcn.oke_vcn.id
  display_name   = "${var.cluster_name}-private-rt"

  route_rules {
    network_entity_id = oci_core_nat_gateway.nat.id
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
  }

  freeform_tags = var.freeform_tags
}

# Security List for OKE (allow Kubernetes traffic)
resource "oci_core_security_list" "oke_sl" {
  compartment_id = local.compartment_id
  vcn_id         = oci_core_vcn.oke_vcn.id
  display_name   = "${var.cluster_name}-sl"

  # Ingress rules
  ingress_security_rules {
    protocol = "6" # TCP
    source   = "0.0.0.0/0"

    tcp_options {
      min = 22
      max = 22
    }
  }

  ingress_security_rules {
    protocol = "6" # TCP
    source   = "0.0.0.0/0"

    tcp_options {
      min = 80
      max = 80
    }
  }

  ingress_security_rules {
    protocol = "6" # TCP
    source   = "0.0.0.0/0"

    tcp_options {
      min = 443
      max = 443
    }
  }

  ingress_security_rules {
    protocol = "6" # TCP
    source   = var.vcn_cidr

    tcp_options {
      min = 6443
      max = 6443
    }
  }

  ingress_security_rules {
    protocol = "6" # TCP
    source   = var.vcn_cidr

    tcp_options {
      min = 10250
      max = 10250
    }
  }

  ingress_security_rules {
    protocol = "6" # TCP
    source   = var.vcn_cidr

    tcp_options {
      min = 10256
      max = 10256
    }
  }

  ingress_security_rules {
    protocol = "all"
    source   = var.vcn_cidr
  }

  # Egress rules
  egress_security_rules {
    protocol    = "all"
    destination = "0.0.0.0/0"
  }

  freeform_tags = var.freeform_tags
}

# Public subnet (for API server/LB)
resource "oci_core_subnet" "public_subnet" {
  compartment_id      = local.compartment_id
  vcn_id              = oci_core_vcn.oke_vcn.id
  cidr_block          = var.subnet_cidr
  display_name        = "${var.cluster_name}-public-subnet"
  dns_label           = "public"
  route_table_id      = oci_core_route_table.public_rt.id
  security_list_ids   = [oci_core_security_list.oke_sl.id]
  prohibit_public_ip_on_vnic = false

  freeform_tags = var.freeform_tags
}

# Private subnet (for worker nodes)
resource "oci_core_subnet" "private_subnet" {
  compartment_id      = local.compartment_id
  vcn_id              = oci_core_vcn.oke_vcn.id
  cidr_block          = cidrsubnet(var.vcn_cidr, 8, 1)
  display_name        = "${var.cluster_name}-private-subnet"
  dns_label           = "private"
  route_table_id      = oci_core_route_table.private_rt.id
  security_list_ids   = [oci_core_security_list.oke_sl.id]
  prohibit_public_ip_on_vnic = true

  freeform_tags = var.freeform_tags
}

# ===================================================================
# OKE Cluster
# ===================================================================

resource "oci_containerengine_cluster" "oke_cluster" {
  compartment_id     = local.compartment_id
  kubernetes_version = var.kubernetes_version
  name               = var.cluster_name

  # VCN configuration - use simple syntax
  vcn_id = oci_core_vcn.oke_vcn.id

  # Endpoint configuration
  endpoint_config {
    is_public_ip_enabled = true
    subnet_id            = oci_core_subnet.public_subnet.id
  }

  options {
    add_ons {
      is_kubernetes_dashboard_enabled = false
      is_tiller_enabled              = false
    }

    admission_controller_options {
      is_pod_security_policy_enabled = false
    }

    kubernetes_network_config {
      pods_cidr     = "10.244.0.0/16"
      services_cidr = "10.96.0.0/16"
    }

    # LoadBalancer subnet IDs - use list syntax
    service_lb_subnet_ids = [oci_core_subnet.public_subnet.id]
  }

  freeform_tags = var.freeform_tags
}

# ===================================================================
# Node Pool
# ===================================================================

resource "oci_containerengine_node_pool" "node_pool" {
  cluster_id      = oci_containerengine_cluster.oke_cluster.id
  compartment_id  = local.compartment_id
  name            = var.node_pool_name
  kubernetes_version = var.kubernetes_version

  node_shape      = var.node_shape

  # SSH key for node access
  ssh_public_key {
    key = file("~/.ssh/id_rsa.pub")
  }

  node_config_details {
    placement_configs {
      availability_domain = data.oci_identity_availability_domains.ads.availability_domains[0].name
      subnet_id           = oci_core_subnet.private_subnet.id
    }

    size = var.node_count
  }

  node_source_details {
    source_type = "IMAGE"
    # Use the latest Oracle Linux image for OKE
    image_id    = data.oci_core_images.oke_images.images[0].id
  }

  # Shape config for A1.Flex
  dynamic "node_shape_config" {
    for_each = var.node_shape == "VM.Standard.A1.Flex" ? [1] : []
    content {
      ocpus         = var.node_ocpus
      memory_in_gbs = var.node_memory_gbs
    }
  }

  initial_node_labels {
    key   = "name"
    value = var.node_pool_name
  }

  freeform_tags = var.freeform_tags
}

# ===================================================================
# Data Sources
# ===================================================================

# Get availability domains
data "oci_identity_availability_domains" "ads" {
  compartment_id = var.tenancy_ocid
}

# Get latest OKE-optimized Oracle Linux image
data "oci_core_images" "oke_images" {
  # Use tenancy_ocid if compartment_name is not set
  compartment_id = var.compartment_name == null ? var.tenancy_ocid : local.compartment_id
  operating_system = "Oracle Linux"
  shape           = var.node_shape
  sort_by         = "TIMECREATED"
  sort_order      = "DESC"

  filter {
    name   = "display_name"
    values = ["^.*Oracle-Linux-[0-9]*-[0-9]*-Minimum.*-aarch64-.*$"]
    regex  = true
  }
}
