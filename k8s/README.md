# Kubernetes Deployment

This directory contains the Kubernetes manifests for deploying the Go microservice with Istio service mesh.

## Prerequisites

1. **Kubernetes cluster** (k3s, microk8s, or standard k8s)
2. **kubectl** configured to talk to your cluster
3. **Istio** installed on the cluster
4. **cert-manager** installed on the cluster
5. **Cloudflare API token** for SSL certificates

## Quick Start

### 1. Install Istio (if not already installed)

```bash
# Download istioctl
curl -L https://istio.io/downloadIstio | sh -
cd istio-*/
export PATH=$PWD/bin:$PATH

# Install with default profile
istioctl install --set profile=default -y

# Verify
istioctl version
```

### 2. Install cert-manager (if not already installed)

```bash
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.15.0/cert-manager.yaml

# Wait for cert-manager to be ready
kubectl wait -n cert-manager --for=condition=available deployment/cert-manager --timeout=300s
kubectl wait -n cert-manager --for=condition=available deployment/cert-manager-cainjector --timeout=300s
kubectl wait -n cert-manager --for=condition=available deployment/cert-manager-webhook --timeout=300s
```

### 3. Create Cloudflare secret for cert-manager

```bash
# Create secret with your Cloudflare API token
kubectl create secret generic cloudflare-api-token \
  -n cert-manager \
  --from-literal=api-token=YOUR_CLOUDFLARE_API_TOKEN
```

**Cloudflare API Token Permissions:**
- Zone - DNS - Edit
- Zone - Zone - Read

Create at: https://dash.cloudflare.com/profile/api-tokens

### 4. Deploy the application

```bash
# Option 1: Use the deployment script
../scripts/deploy.sh

# Option 2: Manual deployment
kubectl apply -f k8s/namespace.yaml
kubectl apply -k k8s/postgres/
kubectl apply -k k8s/base/
kubectl apply -f k8s/istio/
kubectl apply -f k8s/cert-manager/
```

### 5. Configure DNS

Add an A record in Cloudflare:
- **Name:** `dev-go-ms-api`
- **Target:** Your cluster/load balancer IP
- **Proxy:** Off (gray cloud)

## Directory Structure

```
k8s/
├── base/              # Application deployment
│   ├── deployment.yaml
│   ├── service.yaml
│   ├── configmap.yaml
│   ├── secrets.yaml
│   ├── hpa.yaml
│   └── kustomization.yaml
├── postgres/          # PostgreSQL database
│   ├── statefulset.yaml
│   ├── service.yaml
│   ├── pvc.yaml
│   ├── secrets.yaml
│   └── kustomization.yaml
├── istio/             # Istio service mesh
│   ├── gateway.yaml
│   ├── virtualservice.yaml
│   ├── destinationrule.yaml
│   └── authorization-policy.yaml
├── cert-manager/      # SSL certificates
│   ├── cluster-issuer.yaml
│   ├── certificate.yaml
│   └── cloudflare-secret.yaml
└── overlays/          # Environment-specific overlays
    ├── production/
    └── staging/
```

## Verification

```bash
# Check pods (should have 2/2 containers with Istio sidecar)
kubectl get pods -n go-ms

# Check services
kubectl get svc -n go-ms

# Check certificate
kubectl get certificate -n go-ms

# Check Istio configuration
istioctl proxy-status

# Test the endpoint
curl -H "X-API-Key: prod-key-123" https://dev-go-ms-api.gauravv.dev/health
```

## Deployment Script

The `scripts/deploy.sh` script provides convenient deployment options:

```bash
# Deploy to default namespace (go-ms)
./scripts/deploy.sh

# Deploy to custom namespace
./scripts/deploy.sh -n my-namespace

# Use specific kubectl context
./scripts/deploy.sh -c my-context

# Skip TLS/cert-manager
./scripts/deploy.sh --skip-tls

# Show status only
./scripts/deploy.sh --status-only

# Rollback deployment
./scripts/deploy.sh --rollback
```

## Istio Observability

Install Istio addons for monitoring:

```bash
./scripts/install-istio-addons.sh
```

Addons available:
- **Prometheus** - Metrics collection
- **Grafana** - Visualization dashboards
- **Jaeger** - Distributed tracing
- **Kiali** - Service mesh visualization

## Secrets Management

The following secrets contain placeholder values that should be updated:

**k8s/base/secrets.yaml:**
- `database-url` - PostgreSQL connection string
- `api-keys` - Comma-separated valid API keys

**k8s/postgres/secrets.yaml:**
- `postgres-password` - PostgreSQL password

**k8s/cert-manager/cloudflare-secret.yaml:**
- `api-token` - Cloudflare API token

For production, consider using:
- Sealed Secrets
- External Secrets Operator
- Vault Agent Injector
- Cloud provider secret managers

## Scaling

The application includes a HorizontalPodAutoscaler (HPA) that:
- Min replicas: 2
- Max replicas: 10
- Scales on CPU (70%) and memory (80%) utilization

## Troubleshooting

### Pods not starting

```bash
# Check pod status
kubectl describe pod -n go-ms <pod-name>

# Check logs
kubectl logs -n go-ms <pod-name>

# Check Istio sidecar logs
kubectl logs -n go-ms <pod-name> -c istio-proxy
```

### Certificate not issued

```bash
# Check certificate status
kubectl describe certificate -n go-ms go-ms-cert

# Check cert-manager logs
kubectl logs -n cert-manager deployment/cert-manager

# Check ClusterIssuer
kubectl describe clusterissuer letsencrypt-cloudflare
```

### Istio connectivity issues

```bash
# Check Istio configuration
istioctl analyze

# Check proxy status
istioctl proxy-status

# Check proxy config
istioctl proxy-config clusters -n go-ms <pod-name>
```

## Cleanup

```bash
# Delete application
kubectl delete namespace go-ms

# Uninstall Istio (if needed)
istioctl uninstall -y --purge

# Uninstall cert-manager (if needed)
kubectl delete -f https://github.com/cert-manager/cert-manager/releases/download/v1.15.0/cert-manager.yaml
```

## CI/CD

See `.github/workflows/` for automated deployment via GitHub Actions.

Required GitHub Secrets:
- `KUBECONFIG` - Base64 encoded kubeconfig
- `CLOUDFLARE_API_TOKEN` - Cloudflare API token
- `GHCR_TOKEN` - GitHub token for container registry (optional)
- `API_KEYS` - Production API keys (optional)
