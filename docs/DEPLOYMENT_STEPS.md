# Go Microservice Deployment - Production Steps

This document details all the steps taken to deploy the Go microservice to a k3d cluster in a production-like configuration.

## Prerequisites

- Docker Desktop installed and running
- k3d installed
- kubectl installed
- GitHub account with Personal Access Token (PAT)
- Cloudflare account with API Token

## Phase 1: GitHub Repository Setup

### 1.1 Initialize Git Repository

```bash
cd /Users/gaurav.verma/Work/repos/glm4-7/go-ms
git init
git remote add origin https://github.com/gauravv-dev/go-ms.git
```

### 1.2 Commit and Push Initial Code

```bash
git add .
git commit -m "feat: Add Go microservice with Kubernetes deployment"
git push -u origin main
```

**Repository:** https://github.com/gauravv-dev/go-ms

## Phase 2: Docker Image Build and Push

### 2.1 Build Docker Image

```bash
docker build -t ghcr.io/gauravv-dev/go-ms:latest .
```

**Built image:** `ghcr.io/gauravv-dev/go-ms:latest`

### 2.2 Login to GitHub Container Registry (GHCR)

```bash
echo "YOUR_GITHUB_PAT" | docker login ghcr.io -u gauravv-dev --password-stdin
```

**Required permissions:** `write:packages`, `read:packages`

### 2.3 Push Image to GHCR

```bash
docker push ghcr.io/gauravv-dev/go-ms:latest
```

**Image pushed:** `ghcr.io/gauravv-dev/go-ms:latest`

## Phase 3: Update K8s Configuration

### 3.1 Update Image References

Updated files to use correct image name:
- `k8s/base/deployment.yaml`
- `k8s/base/kustomization.yaml`
- `k8s/overlays/production/kustomization.yaml`

**Old image:** `ghcr.io/gauravv/dev-go-ms-api`
**New image:** `ghcr.io/gauravv-dev/go-ms`

### 3.2 Remove secretGenerator from Production Overlay

Removed `secretGenerator` section from `k8s/overlays/production/kustomization.yaml` for better security.

**Reason:** Secrets should be created manually in production, not generated.

### 3.3 Fix Kustomize Patch Paths

Updated production overlay to use correct JSON patch paths for container resources:

```yaml
# Before (incorrect):
path: /spec/resources/requests/memory

# After (correct):
path: /spec/template/spec/containers/0/resources/requests/memory
```

### 3.4 Commit Configuration Changes

```bash
git add -A
git commit -m "fix: Update image references and fix kustomize patches"
git push
```

## Phase 4: k3d Cluster Setup

### 4.1 Start k3d Cluster

```bash
k3d cluster start go-ms-local
```

**Cluster name:** `go-ms-local`
**Nodes:** 1 server, 1 agent, 1 loadbalancer

### 4.2 Verify Cluster Connection

```bash
kubectl cluster-info
kubectl get nodes
```

## Phase 5: Kubernetes Deployment

### 5.1 Create Namespace

```bash
kubectl create namespace go-ms
kubectl label namespace go-ms istio-injection=enabled
```

### 5.2 Create Secrets

**Application secrets:**
```bash
kubectl create secret generic go-ms-secrets -n go-ms \
  --from-literal=database-url="postgres://bookuser:bookdb@postgres:5432/bookdb" \
  --from-literal=api-keys="prod-key-123"
```

**PostgreSQL secrets:**
```bash
kubectl create secret generic postgres-secrets -n go-ms \
  --from-literal=postgres-password="bookdb"
```

### 5.3 Create Image Pull Secret

```bash
kubectl create secret docker-registry ghcr-pull-secret -n go-ms \
  --docker-server=ghcr.io \
  --docker-username=gauravv-dev \
  --docker-password=YOUR_GITHUB_PAT
```

### 5.4 Patch Deployment with Pull Secret

```bash
kubectl patch deployment go-ms -n go-ms \
  -p '{"spec":{"template":{"spec":{"imagePullSecrets":[{"name":"ghcr-pull-secret"}]}}}}'
```

### 5.5 Deploy Application

```bash
kubectl apply -k k8s/overlays/production/
```

**Resources deployed:**
- Deployment: `go-ms` (3 replicas)
- StatefulSet: `postgres`
- Services: `go-ms`, `postgres`
- ConfigMaps, Secrets

### 5.6 Deploy Istio Resources

```bash
kubectl apply -f k8s/istio/
```

**Istio resources deployed:**
- Gateway: `go-ms-gateway`
- VirtualService: `go-ms`
- DestinationRules
- AuthorizationPolicies

### 5.7 Configure Cloudflare Secret for SSL

```bash
kubectl create secret generic cloudflare-api-token \
  --from-literal=api-token=Ge2oX4yUA8uRpb0oGOhoSj9HNqmiFaKtKmZ2G2vD \
  -n cert-manager
```

### 5.8 Deploy Cert-Manager Resources

```bash
kubectl apply -f k8s/cert-manager/cluster-issuer.yaml
kubectl apply -f k8s/cert-manager/certificate.yaml
```

**Certificate:** `go-ms-cert` for `dev-go-ms-api.gauravv.dev`
**Valid until:** 2026-05-14

### 5.9 Wait for Deployment

```bash
kubectl wait -n go-ms --for=condition=ready pod -l app=postgres --timeout=120s
kubectl wait -n go-ms --for=condition=available deployment/go-ms --timeout=120s
kubectl rollout restart deployment/go-ms -n go-ms
```

## Phase 6: k3d Network Configuration

### 6.1 Expose Istio NodePorts

The k3d LoadBalancer doesn't automatically expose NodePorts. Created custom nginx configuration to expose:

- **HTTP NodePort 32705** → Host port 32705
- **HTTPS NodePort 30884** → Host port 30884

### 6.2 Custom nginx Configuration

Created `/Users/gaurav.verma/Work/repos/glm4-7/go-ms/tmp/nginx.conf` with stream blocks for:
- Port 80 (HTTP to cluster)
- Port 443 (HTTPS to cluster)
- Port 6443 (Kubernetes API)
- Port 32705 (Istio HTTP NodePort)
- Port 30884 (Istio HTTPS NodePort)

### 6.3 Recreate k3d ServerLB

```bash
docker stop k3d-go-ms-local-serverlb
docker rm k3d-go-ms-local-serverlb
docker run -d --name k3d-go-ms-local-serverlb \
  --network k3d-go-ms-local \
  --restart always \
  -p 8080:80 \
  -p 8443:443 \
  -p 52364:6443 \
  -p 32705:32705 \
  -p 30884:30884 \
  -v /Users/gaurav.verma/Work/repos/glm4-7/go-ms/tmp/nginx.conf:/etc/nginx/nginx.conf:ro \
  nginx:alpine
```

## Phase 7: DNS Configuration

### 7.1 Local DNS Entry

Added to `/etc/hosts`:
```
127.0.0.1 dev-go-ms-api.gauravv.dev
```

## Phase 8: Verification

### 8.1 Check Resources

```bash
kubectl get pods -n go-ms
kubectl get svc -n go-ms
kubectl get certificate -n go-ms
```

**Expected output:**
- 3 go-ms pods running (2/2 READY each)
- 1 postgres pod running (2/2 READY)
- Certificate status: True

### 8.2 Test Endpoints

**Health check via HTTP NodePort:**
```bash
curl -H "Host: dev-go-ms-api.gauravv.dev" \
  -H "X-API-Key: prod-key-123" \
  http://localhost:32705/health
```

**Get books via HTTP NodePort:**
```bash
curl -H "Host: dev-go-ms-api.gauravv.dev" \
  -H "X-API-Key: prod-key-123" \
  http://localhost:32705/books
```

**Via domain name:**
```bash
curl -H "X-API-Key: prod-key-123" \
  http://dev-go-ms-api.gauravv.dev:32705/health
```

## Deployment Summary

| Component | Value |
|-----------|-------|
| **Repository** | https://github.com/gauravv-dev/go-ms |
| **Docker Image** | ghcr.io/gauravv-dev/go-ms:latest |
| **Cluster** | k3d `go-ms-local` |
| **Replicas** | 3 (production) |
| **Domain** | dev-go-ms-api.gauravv.dev |
| **HTTP Port** | 32705 |
| **HTTPS Port** | 30884 (configured, not yet tested) |
| **API Key** | prod-key-123 |
| **SSL Certificate** | Valid until 2026-05-14 |

## Current Status

✅ Application deployed and running
✅ 3 replicas active with Istio sidecars
✅ PostgreSQL database running
✅ SSL certificate installed and valid
✅ HTTP access working via NodePort 32705
⏳ HTTPS access configured (to be tested)

## Next Steps

1. Test HTTPS access via NodePort 30884
2. Configure proper HTTPS termination
3. Set up GitHub Actions for automated deployment to cloud cluster
