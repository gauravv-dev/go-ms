# Oracle Cloud OKE - Terraform Deployment

This Terraform configuration deploys a Kubernetes cluster on Oracle Cloud Infrastructure (OCI) using Oracle Kubernetes Engine (OKE) with the Always Free tier.

## Prerequisites

1. **Oracle Cloud Account** with API key configured
2. **Terraform** installed: `brew install terraform`
3. **OCI CLI** installed and configured: `brew install oci-cli`
4. **SSH Key** at `~/.ssh/id_rsa.pub` for node access

## Quick Start

### 1. Copy and Configure terraform.tfvars

```bash
cd infra/oracle-oke
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars` with your values:

```hcl
region           = "ap-mumbai-1"          # Your region
tenancy_ocid     = "ocid1.tenancy.oc1..." # From Oracle Cloud Console
user_ocid        = "ocid1.user.oc1..."    # From Oracle Cloud Console
fingerprint      = "xx:xx:xx:..."         # From your API key config
private_key_path = "~/.oci/oci_api_key.pem"
compartment_name = "your-tenancy-name"
```

### 2. Initialize Terraform

```bash
terraform init
```

### 3. Plan the Deployment

```bash
terraform plan
```

Review the resources that will be created.

### 4. Apply the Deployment

```bash
terraform apply
```

Type `yes` when prompted.

**Wait time:** ~10-15 minutes for cluster creation.

### 5. Get kubeconfig

After the cluster is ready, Terraform will output the command to generate kubeconfig:

```bash
oci ce cluster create-kubeconfig \
  --cluster-id <cluster-id-from-output> \
  --file $HOME/.kube/config-oci \
  --region ap-mumbai-1
```

Or use the output directly:
```bash
terraform output kubeconfig_command | pbcopy && eval $(terraform output kubeconfig_command)
```

### 6. Verify the Cluster

```bash
export KUBECONFIG=$HOME/.kube/config-oci
kubectl get nodes
```

Expected output:
```
NAME           STATUS   ROLES    AGE   VERSION
10.0.2.xxx     Ready    <none>   5m    v1.29.1
10.0.2.yyy     Ready    <none>   5m    v1.29.1
```

## Resources Created

| Resource | Purpose |
|----------|---------|
| VCN | Virtual network (10.0.0.0/16) |
| Internet Gateway | Public internet access |
| NAT Gateway | Private subnet internet access |
| Public Subnet | For LoadBalancer services |
| Private Subnet | For worker nodes |
| Security List | Firewall rules for Kubernetes |
| OKE Cluster | Kubernetes control plane |
| Node Pool | 2x ARM nodes (Always Free) |

## Architecture

```
                    ┌─────────────────┐
                    │   Internet      │
                    └────────┬────────┘
                             │
                    ┌────────▼────────┐
                    │  Internet GW    │
                    └────────┬────────┘
                             │
        ┌────────────────────┴────────────────────┐
        │                                         │
┌───────▼────────┐                       ┌───────▼────────┐
│  Public Subnet │                       │ Private Subnet │
│  (LoadBalancer) │                       │   (Nodes)      │
└────────────────┘                       └───────┬────────┘
                                                 │
                                          ┌──────▼──────┐
                                          │    NAT GW    │
                                          └──────┬──────┘
                                                 │
                                                 ▼
                                          ┌─────────────┐
                                          │  Internet   │
                                          └─────────────┘
```

## Deployment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `cluster_name` | `go-ms-cluster` | Name of the cluster |
| `kubernetes_version` | `v1.29.1` | Kubernetes version |
| `node_shape` | `VM.Standard.A1.Flex` | Node shape (Always Free) |
| `node_count` | `2` | Number of nodes |
| `node_ocpus` | `2` | OCPUs per node |
| `node_memory_gbs` | `6` | Memory per node in GB |
| `vcn_cidr` | `10.0.0.0/16` | VCN CIDR block |
| `subnet_cidr` | `10.0.1.0/24` | Subnet CIDR block |

## Costs

| Resource | Always Free | Paid |
|----------|------------|------|
| OKE Control Plane | ✅ FREE | - |
| Nodes (ARM) | 2x A1.Flex (6GB, 2 OCPUs) | $0.018/OCPU/hr |
| Load Balancer | 1 FREE | - |
| Block Storage | 2x 200GB | - |
| Public IPs | 2 FREE | - |
| Egress | 10 TB/month | - |

**Total: $0/month** with Always Free tier

## Troubleshooting

### SSH Key Not Found

Create an SSH key:
```bash
ssh-keygen -t rsa -b 2048 -f ~/.ssh/id_rsa -N ""
```

### Always Free Limits Exceeded

Check your usage:
```bash
oci limits usage get --compartment-id YOUR_COMPARTMENT_ID
```

### Cluster Taking Too Long

OKE cluster creation takes 10-15 minutes. Check progress:
```bash
oci ce cluster get --cluster-id $(terraform output cluster_id)
```

### Can't Connect to Cluster

1. Verify kubeconfig points to the right cluster:
   ```bash
   kubectl config view
   ```

2. Check cluster state:
   ```bash
   oci ce cluster get --cluster-id $(terraform output cluster_id)
   ```

## Cleanup

To destroy all resources:

```bash
terraform destroy
```

**Important:** This will delete the OKE cluster and all associated resources.

## Next Steps

After the cluster is ready, deploy your application:

```bash
# See terraform output next_steps
terraform output next_steps
```

## Useful Commands

```bash
# Show all outputs
terraform output

# Show specific output
terraform output cluster_id
terraform output kubeconfig_command

# Refresh state
terraform refresh

# Show state
terraform show

# Import existing resources (if needed)
terraform import oci_containerengine_cluster.my_cluster <cluster-id>
```
