# Plan: Production Kubernetes Deployment with Istio Service Mesh

## Target
- Deploy Go microservice to homelab Kubernetes cluster
- Expose via Cloudflare DNS at `dev-go-ms-api.gauravv.dev`
- Istio service mesh for traffic management, mTLS, and observability
- Automated SSL/TLS with Let's Encrypt via Cloudflare DNS challenge
- Persistent PostgreSQL storage
- CI/CD with GitHub Actions

## Prerequisites
- Existing Kubernetes cluster (k3s, microk8s, or standard k8s)
- `kubectl` configured to talk to cluster
- Cloudflare API token for DNS challenges
- GitHub account for GHCR (Container Registry)

## Architecture Overview

```
Internet -> Cloudflare DNS -> Istio Gateway -> VirtualService -> Go Service -> PostgreSQL
                    |
              Let's Encrypt (cert-manager)
                    |
              Istio mTLS (service-to-service)
```

## Components to Create

### 1. Istio Configuration

**Files to create:**
- `k8s/istio/gateway.yaml` - Istio Gateway for external access
- `k8s/istio/virtualservice.yaml` - Route traffic to go-ms service
- `k8s/istio/destinationrule.yaml` - Traffic policies, mTLS settings
- `k8s/istio/authorization-policy.yaml` - Access control policies

### 2. Kubernetes Manifests

**Files to create:**
- `k8s/base/deployment.yaml` - Go app deployment with sidecar injection
- `k8s/base/service.yaml` - ClusterIP service
- `k8s/base/configmap.yaml` - Environment configuration
- `k8s/base/secrets.yaml` - Sensitive data (API keys, DB password)
- `k8s/base/kustomization.yaml` - Kustomize config

### 3. PostgreSQL StatefulSet

**Files to create:**
- `k8s/postgres/statefulset.yaml` - PostgreSQL with persistent volume
- `k8s/postgres/service.yaml` - PostgreSQL service
- `k8s/postgres/pvc.yaml` - Persistent volume claim
- `k8s/postgres/kustomization.yaml`

### 4. cert-manager (First-time Setup)

**Files to create:**
- `k8s/cert-manager/install.yaml` - Installation manifest
- `k8s/cert-manager/cluster-issuer.yaml` - Let's Encrypt with Cloudflare DNS01
- `k8s/cert-manager/certificate.yaml` - Certificate for domain

### 5. GitHub Actions CI/CD

**Files to create:**
- `.github/workflows/build-push.yml` - Build and push container image
- `.github/workflows/deploy.yml` - Deploy to Kubernetes on push to main
- `scripts/deploy.sh` - Deployment helper script

## Directory Structure

```
go-ms/
├── k8s/
│   ├── base/
│   │   ├── deployment.yaml          # Go app with Istio sidecar
│   │   ├── service.yaml
│   │   ├── configmap.yaml
│   │   ├── secrets.yaml
│   │   ├── hpa.yaml                 # Horizontal Pod Autoscaler
│   │   └── kustomization.yaml
│   ├── postgres/
│   │   ├── statefulset.yaml
│   │   ├── service.yaml
│   │   ├── pvc.yaml
│   │   └── kustomization.yaml
│   ├── istio/
│   │   ├── gateway.yaml             # Istio Gateway
│   │   ├── virtualservice.yaml      # Routing rules
│   │   ├── destinationrule.yaml     # mTLS, traffic policies
│   │   └── authorization-policy.yaml # Security policies
│   ├── cert-manager/
│   │   ├── cluster-issuer.yaml      # Let's Encrypt + Cloudflare
│   │   └── certificate.yaml
│   └── overlays/
│       ├── production/
│       │   └── kustomization.yaml
│       └── staging/
│           └── kustomization.yaml
├── .github/
│   └── workflows/
│       ├── build-push.yml           # Build & push to GHCR
│       └── deploy.yml               # Deploy to k8s
├── scripts/
│   ├── deploy.sh
│   └── install-istio-addons.sh
└── Dockerfile                       # Production image
```

## Istio-specific Configuration

### Gateway (External Access)
- Host: `dev-go-ms-api.gauravv.dev`
- Port: 443 (HTTPS)
- TLS mode: SIMPLE (terminates at gateway)

### VirtualService (Routing)
- Route `/` to go-ms service
- Timeout and retry policies
- Canary deployment support (future)

### DestinationRule (Service Policies)
- mTLS mode: STRICT (all mesh traffic encrypted)
- Connection pool settings
- Outlier detection for failover

### AuthorizationPolicy (Security)
- Allow public access to `/health`
- Require API key for `/books/*` endpoints

## Container Registry (GHCR)

**Image naming:** `ghcr.io/gauravv/dev-go-ms-api:{version}`

Tags:
- `latest` - Latest main branch build
- `v1.0.0` - Semantic version tags
- `pr-123` - Pull request builds

## Environment Variables

| Variable | Secret? | Description |
|----------|---------|-------------|
| `PORT` | No | Service port (8080) |
| `DATABASE_URL` | Yes | PostgreSQL connection string |
| `API_KEYS` | Yes | Comma-separated API keys |
| `AUTH_ENABLED` | No | true |
| `LOG_LEVEL` | No | info |
| `ALLOWED_ORIGINS` | No | https://dev-go-ms-api.gauravv.dev |
| `ISTIO_ENABLED` | No | true |

## Cloudflare Requirements

### 1. API Token
Create at https://dash.cloudflare.com/profile/api-tokens

Permissions needed:
- Zone - DNS - Edit
- Zone - Zone - Read

### 2. DNS Record
- **Type:** A
- **Name:** `dev-go-ms-api`
- **Target:** Your cluster/load balancer IP
- **Proxy:** Off (gray cloud) - SSL handled by Istio
- **TTL:** Auto

## Implementation Steps

1. **Install Istio** (if not already installed)
   - Download istioctl
   - Install with default profile

2. **Install cert-manager**
   - Apply cert-manager manifests
   - Create Cloudflare secret for DNS01 challenge

3. **Create Kubernetes manifests**
   - Base deployment, service, configmap
   - PostgreSQL statefulset with PVC

4. **Configure Istio resources**
   - Gateway with TLS certificate
   - VirtualService for routing
   - DestinationRule for mTLS

5. **Setup CI/CD**
   - Create GitHub Actions workflows
   - Configure GitHub secrets (kubeconfig, Cloudflare token)

6. **Build and push image**
   - Tag appropriately for environment

7. **Deploy to cluster**
   - Apply manifests in order
   - Verify Istio sidecar injection

8. **Configure Cloudflare DNS**
   - Create A record pointing to cluster IP

9. **Verify deployment**
   - Check certificate issuance
   - Test mTLS between services
   - Verify end-to-end connectivity

## Verification Steps

```bash
# 1. Check Istio installation
istioctl version

# 2. Check cert-manager
kubectl get pods -n cert-manager

# 3. Deploy application
kubectl apply -k k8s/base/

# 4. Check pods (should have 2/2 containers with sidecar)
kubectl get pods -n go-ms

# 5. Check certificate
kubectl get certificate -n go-ms

# 6. Check Istio configuration
istioctl proxy-status

# 7. Test endpoint
curl -H "X-API-Key: your-key" https://dev-go-ms-api.gauravv.dev/health

# 8. Verify mTLS
istioctl authn check -n go-ms deployment/go-ms

# 9. Check metrics
kubectl port-forward -n istio-system svc/prometheus 9090:9090
```

## GitHub Secrets Required

| Secret | Description |
|--------|-------------|
| `KUBECONFIG` | Base64 encoded kubeconfig file |
| `CLOUDFLARE_API_TOKEN` | Cloudflare API token for cert-manager |
| `GHCR_TOKEN` | GitHub personal access token for container registry |
| `API_KEYS` | Production API keys (for deployment) |
