variable "region" {
  description = "Oracle Cloud region"
  type        = string
  default     = "ap-mumbai-1"
}

variable "tenancy_ocid" {
  description = "OCID of your tenancy"
  type        = string
  sensitive   = true
}

variable "user_ocid" {
  description = "OCID of your user"
  type        = string
  sensitive   = true
}

variable "fingerprint" {
  description = "API key fingerprint"
  type        = string
  sensitive   = true
}

variable "private_key_path" {
  description = "Path to your OCI API private key file"
  type        = string
  default     = "~/.oci/oci_api_key.pem"
}

# Cluster configuration
variable "cluster_name" {
  description = "Name of the OKE cluster"
  type        = string
  default     = "go-ms-cluster"
}

variable "kubernetes_version" {
  description = "Kubernetes version for the OKE cluster"
  type        = string
  default     = "v1.29.1"
}

# Node pool configuration
variable "node_pool_name" {
  description = "Name of the node pool"
  type        = string
  default     = "node-pool"
}

variable "node_shape" {
  description = "Shape of the nodes (Always Free eligible: VM.Standard.A1.Flex)"
  type        = string
  default     = "VM.Standard.A1.Flex"
}

variable "node_count" {
  description = "Number of nodes in the node pool (Always Free: up to 2 with 6 OCPUs each)"
  type        = number
  default     = 2
}

variable "node_memory_gbs" {
  description = "Memory per node in GB (for A1.Flex: 6GB allows 2 OCPUs)"
  type        = number
  default     = 6
}

variable "node_ocpus" {
  description = "OCPUs per node (Always Free: max 4 total across 2 nodes = 2 each)"
  type        = number
  default     = 2
}

# VCN configuration
variable "vcn_cidr" {
  description = "CIDR block for the VCN"
  type        = string
  default     = "10.0.0.0/16"
}

variable "subnet_cidr" {
  description = "CIDR block for the subnet"
  type        = string
  default     = "10.0.1.0/24"
}

# Tags
variable "freeform_tags" {
  description = "Freeform tags to apply to all resources"
  type        = map(string)
  default     = {
    Project = "go-ms"
    ManagedBy = "terraform"
  }
}

# SSH key
variable "ssh_public_key" {
  description = "SSH public key content for node access"
  type        = string
  default     = null
}

# Node image (optional - if not specified, will auto-detect)
variable "node_image_id" {
  description = "Custom image ID for nodes (if auto-detection fails)"
  type        = string
  default     = null
}
