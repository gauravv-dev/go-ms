# ===================================================================
# Outputs
# ===================================================================

output "cluster_id" {
  description = "OCID of the OKE cluster"
  value       = oci_containerengine_cluster.oke_cluster.id
}

output "cluster_name" {
  description = "Name of the OKE cluster"
  value       = oci_containerengine_cluster.oke_cluster.name
}

output "cluster_endpoint" {
  description = "Kubernetes API endpoint"
  value       = oci_containerengine_cluster.oke_cluster.endpoints[0]
}

output "vcn_id" {
  description = "OCID of the VCN"
  value       = oci_core_vcn.oke_vcn.id
}

output "public_subnet_id" {
  description = "OCID of the public subnet"
  value       = oci_core_subnet.public_subnet.id
}

output "private_subnet_id" {
  description = "OCID of the private subnet"
  value       = oci_core_subnet.private_subnet.id
}

output "node_pool_id" {
  description = "OCID of the node pool"
  value       = oci_containerengine_node_pool.node_pool.id
}

output "kubeconfig_command" {
  description = "Command to generate kubeconfig"
  value       = "oci ce cluster create-kubeconfig --cluster-id ${oci_containerengine_cluster.oke_cluster.id} --file $HOME/.kube/config-oci --region ${var.region}"
}

output "next_steps" {
  description = "Next steps to deploy the application"
  value       = <<-EOT
    1. Set up kubeconfig:
       export KUBECONFIG=$HOME/.kube/config-oci

    2. Verify cluster:
       kubectl get nodes

    3. Create namespace:
       kubectl create namespace go-ms

    4. Create secrets:
       kubectl create secret docker-registry ghcr-pull-secret -n go-ms \
         --docker-server=ghcr.io --docker-username=gauravv-dev --docker-password=YOUR_TOKEN

    5. Deploy application:
       kubectl apply -k k8s/overlays/production/

    6. Get LoadBalancer IP:
       kubectl get svc -n go-ms go-ms
  EOT
}
