# Oracle Cloud OKE Deployment Guide

This guide explains how to deploy the Go microservice to Oracle Cloud Infrastructure (OCI) using Oracle Kubernetes Engine (OKE) with the Always Free tier.

## Why Oracle Cloud?

| Feature | Oracle Cloud | AWS | GCP |
|---------|-------------|-----|-----|
| **Control Plane** | FREE | $72/month | FREE |
| **Always Free Nodes** | 2x ARM (4GB each) | None | Limited e2-micro |
| **Monthly Cost** | **$0** | $82-92+ | $5-10+ |
| **Architecture** | ARM64 | AMD64 | AMD64 |

## Prerequisites

1. **Oracle Cloud Account** - Sign up at https://oracle.com/cloud/free
   - Requires credit card for verification (won't charge for free tier)
   - You get $300 free credit for 30 days + Always Free resources

2. **OCI CLI** - Install locally
   ```bash
   # macOS
   brew install oci-cli

   # Linux
   wget -qO- https://raw.githubusercontent.com/oracle/oci-cli/master/scripts/install/install.sh | bash

   # Verify
   oci --version
   ```

3. **kubectl** - Already installed for k3d
4. **Docker** - Already installed

## Part 1: Oracle Cloud Setup

### 1.1 Create an Account

1. Go to https://oracle.com/cloud/free
2. Click "Sign Up"
3. Fill in your details (requires credit card for verification)
4. Verify your email
5. Choose your home region (choose closest to you)

### 1.2 Get Your API Credentials

You need API credentials to use the OCI CLI:

1. Go to Oracle Cloud Console
2. Click your profile → **User Settings**
3. Click **API Keys** → **Add API Key**
4. Select **Generate API Key Pair**
5. Download the private key file (save it!)
6. Copy the **Configuration File** contents

### 1.3 Configure OCI CLI

```bash
oci setup config
```

Enter the values from the configuration file:
- Enter a location for your config: `/Users/gauravverma/.oci/config`
- Enter OCID of your tenancy: (from config file)
- Enter OCID of your user: (from config file)
- Enter OCID of your region: (from config file, e.g., `ap-mumbai-1`)
- Enter a path to your API Key private key file: (path to downloaded key)
- Do you want to use a fingerprint from the config file? [Y]: Y

**Test connection:**
```bash
oci iam compartment list
```

## Part 2: Create OKE Cluster

### 2.1 Create the Cluster

**Option A: Using Console (Recommended for first time)**

1. Go to Oracle Cloud Console
2. Navigate to: **Developer Services** → **Kubernetes (OKE)**
3. Click **Create Cluster**
4. Select **Quick Create**
5. Fill in:
   - **Name**: `go-ms-cluster`
   - **Kubernetes Version**: (latest available, e.g., v1.29.1)
   - **Visibility**: Public
   - **Kubernetes Endpoint**: Public
6. Click **Next**

**Node Pool Settings:**
- **Name**: `node-pool`
- **Node Shape**: `VM.Standard.A1.Flex` (Always Free eligible)
- **Number of Nodes**: `2` (you get 2 free OCPUs)
- **Node Memory (GB)**: `6` per node (allows 2 OCPUs per node)
- **Pod Network**: VCN Native (CNI)

7. Click **Next** → Review → **Create Cluster**

**Wait time:** ~5-10 minutes for cluster creation.

**Option B: Using OCI CLI**

```bash
# Get your compartment ID
oci iam compartment list

# Create cluster (replace values)
oci ce cluster create \
  --name go-ms-cluster \
  --compartment-id YOUR_COMPARTMENT_ID \
  --kubernetes-version v1.29.1 \
  --options file://cluster-options.json
```

### 2.3 Get Cluster Access

**Using Console:**
1. Go to your cluster in the console
2. Click **Access Cluster**
3. Copy the **oci ce cluster create-kubeconfig** command

**Example command:**
```bash
oci ce cluster create-kubeconfig \
  --cluster-id ocid1.cluster.oc1.ap-mumbai-1.xxx \
  --file $HOME/.kube/config-oci \
  --region ap-mumbai-1
```

**Set up kubeconfig:**
```bash
export KUBECONFIG=$HOME/.kube/config-oci
kubectl get nodes
```

Expected output:
```
NAME           STATUS   ROLES    AGE   VERSION
10.0.0.xxx     Ready    <none>   5m    v1.29.1
10.0.0.yyy     Ready    <none>   5m    v1.29.1
```

## Part 3: Build Multi-Architecture Image

Your app needs to run on ARM64 (Oracle uses ARM chips).

### 3.1 Option A: Let GitHub Actions Build It

Push to main branch, GitHub Actions will build for both AMD64 and ARM64:

```bash
git add .
git commit -m "chore: trigger multi-arch build"
git push
```

Wait for the workflow to complete, then verify:
```bash
docker buildx imagetools inspect ghcr.io/gauravv-dev/go-ms:latest
```

Should show:
```
Platform: linux/amd64
Platform: linux/arm64
```

### 3.2 Option B: Build Locally for ARM64

```bash
# Build for ARM64 only
docker buildx build \
  --platform linux/arm64 \
  -t ghcr.io/gauravv-dev/go-ms:arm64 \
  --push .
```

## Part 4: Deploy to OKE

### 4.1 Create Namespace

```bash
kubectl create namespace go-ms
kubectl label namespace go-ms istio-injection=enabled
```

### 4.2 Create Secrets

```bash
# Application secrets
kubectl create secret generic go-ms-secrets -n go-ms \
  --from-literal=database-url="postgres://bookuser:bookdb@postgres:5432/bookdb" \
  --from-literal=api-keys="prod-key-123"

# PostgreSQL secrets
kubectl create secret generic postgres-secrets -n go-ms \
  --from-literal=postgres-password="bookdb"
```

### 4.3 Create Image Pull Secret

```bash
kubectl create secret docker-registry ghcr-pull-secret -n go-ms \
  --docker-server=ghcr.io \
  --docker-username=gauravv-dev \
  --docker-password=YOUR_GITHUB_PAT
```

### 4.4 Update Deployment for Image Pull Secret

```bash
kubectl patch deployment go-ms -n go-ms \
  -p '{"spec":{"template":{"spec":{"imagePullSecrets":[{"name":"ghcr-pull-secret"}]}}}}'
```

### 4.5 Deploy Application

```bash
kubectl apply -k k8s/overlays/production/
```

### 4.6 Deploy Istio (Optional)

OKE doesn't come with Istio pre-installed. Install it first:

```bash
# Install Istio
istioctl install --set profile=default -y

# Deploy Istio resources
kubectl apply -f k8s/istio/
```

### 4.7 Deploy Certificate (Optional - for HTTPS)

For public domain with Cloudflare:

```bash
# Install cert-manager
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.14.0/cert-manager.yaml

# Create Cloudflare secret
kubectl create secret generic cloudflare-api-token \
  --from-literal=api-token=YOUR_CLOUDFLARE_TOKEN \
  -n cert-manager

# Deploy certificate resources
kubectl apply -f k8s/cert-manager/
```

## Part 5: Access Your Application

### 5.1 Get External IP

```bash
kubectl get svc -n istio-system istio-ingressgateway
```

Or if using LoadBalancer service:
```bash
kubectl get svc -n go-ms go-ms
```

### 5.2 Test Access

**If using LoadBalancer:**
```bash
EXTERNAL_IP=$(kubectl get svc -n go-ms go-ms -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
curl -H "X-API-Key: prod-key-123" http://$EXTERNAL_IP/health
```

**If using Istio Gateway:**
```bash
EXTERNAL_IP=$(kubectl get svc -n istio-system istio-ingressgateway -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
curl -H "Host: dev-go-ms-api.gauravv.dev" -H "X-API-Key: prod-key-123" http://$EXTERNAL_IP/health
```

### 5.3 Configure DNS (Optional)

1. Go to Cloudflare → DNS → gauravv.dev
2. Add A record: `dev-go-ms-api` → `<EXTERNAL_IP>`
3. Wait for propagation
4. Test: `curl https://dev-go-ms-api.gauravv.dev/health`

## Part 6: Troubleshooting

### ARM Architecture Issues

If pods don't start:

```bash
# Check pod status
kubectl describe pod -n go-ms POD_NAME

# Check if image is ARM compatible
docker buildx imagetools inspect ghcr.io/gauravv-dev/go-ms:latest

# If not ARM, rebuild with multi-arch
docker buildx build --platform linux/amd64,linux/arm64 -t ghcr.io/gauravv-dev/go-ms:latest --push .
```

### Always Free Limits Exceeded

Check your usage:
```bash
oci limits usage get --compartment-id YOUR_COMPARTMENT_ID
```

### Nodes Not Ready

```bash
kubectl describe node
kubectl logs -n kube-system -l app=csi
```

## Part 7: Cost Monitoring

Check your Always Free usage:

```bash
oci usage-api requestsummary summarize-usage --compartment-id YOUR_COMPARTMENT_ID --tenant-id YOUR_TENANCY_ID
```

Or view in Console:
- Billing & Cost Management → Usage & Cost Reports

## Summary

| Resource | Cost |
|----------|------|
| OKE Control Plane | **FREE** |
| 2x ARM Nodes (Always Free) | **FREE** |
| Load Balancer (Always Free) | **FREE** |
| Block Storage | Up to 2x 200GB **FREE** |
| Egress | 10 TB/month **FREE** |
| **Total** | **$0/month** |

## Cleanup (If Needed)

```bash
# Delete cluster
oci ce cluster delete --cluster-id YOUR_CLUSTER_ID --force

# Or from Console: Developer Services → Kubernetes → Cluster → Delete
```

## Next Steps

1. Set up GitHub Actions to deploy to OKE on push
2. Configure proper CI/CD pipeline
3. Add monitoring (Prometheus/Grafana)
4. Set up auto-scaling
