# Local Kubernetes Development

Run the full production-like stack locally using k3d (Kubernetes in Docker) with Istio and cert-manager.

## Prerequisites

- Docker
- k3d (installed by setup script)
- kubectl (installed by setup script)
- istioctl (installed by setup script)

## Quick Start

### 1. Setup Local Cluster (First Time Only)

```bash
make local-setup
```

This installs:
- **k3d** - Kubernetes in Docker
- **kubectl** - Kubernetes CLI
- **istioctl** - Istio CLI
- **helm** - Package manager (for cert-manager)
- **Istio** - Service mesh
- **cert-manager** - SSL certificate management

### 2. Deploy Application

```bash
make local-up
```

This builds the Docker image, loads it into k3d, and deploys all resources.

### 3. Access the Service

**Option A: Port-forward (simplest)**
```bash
make local-port-forward
# Then test:
curl -H "X-API-Key: prod-key-123" http://localhost:8080/health
```

**Option B: Via domain (requires /etc/hosts or DNS)**
```bash
# Add to /etc/hosts:
echo "127.0.0.1 dev-go-ms-api.gauravv.dev" | sudo tee -a /etc/hosts

# Test via domain:
curl -H "X-API-Key: prod-key-123" http://dev-go-ms-api.gauravv.dev:8443/health
```

**Option C: With real SSL (requires Cloudflare API token)**
1. Add A record in Cloudflare: `dev-go-ms-api` → your public IP
2. Create Cloudflare secret:
   ```bash
   kubectl create secret generic cloudflare-api-token \
     -n cert-manager \
     --from-literal=api-token=YOUR_CLOUDFLARE_API_TOKEN
   ```
3. The certificate will be automatically issued

## Makefile Commands

| Command | Description |
|---------|-------------|
| `make local-setup` | Install k3d, Istio, cert-manager (one-time) |
| `make local-up` | Build and deploy to local cluster |
| `make local-down` | Stop local cluster |
| `make local-start` | Start stopped cluster |
| `make local-delete` | Delete local cluster |
| `make local-restart` | Restart cluster |
| `make local-logs` | Follow application logs |
| `make local-status` | Show cluster status |
| `make local-port-forward` | Port-forward to service |
| `make local-exec` | Open shell in pod |

## Workflow

### Development Loop

1. Make code changes
2. Rebuild and redeploy:
   ```bash
   docker build -t ghcr.io/gauravv/dev-go-ms-api:local -f Dockerfile .
   k3d image import ghcr.io/gauravv/dev-go-ms-api:local -c go-ms-local
   kubectl rollout restart deployment/go-ms -n go-ms
   ```
3. Test changes

### Hot Reload (Optional)

For hot reload during development, you can use a development container:

```bash
# Update k8s/overlays/local/kustomization.yaml to use Dockerfile.dev
# Add air or similar hot-reload tool
```

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                        Your Browser                      │
└────────────────────┬────────────────────────────────────┘
                     │
                     │ dev-go-ms-api.gauravv.dev:8443
                     │
┌────────────────────▼────────────────────────────────────┐
│              k3d LoadBalancer (127.0.0.1)                │
└────────────────────┬────────────────────────────────────┘
                     │
┌────────────────────▼────────────────────────────────────┐
│          Istio IngressGateway (port 443)                 │
│          - TLS termination                               │
│          - mTLS to services                              │
└────────────────────┬────────────────────────────────────┘
                     │
┌────────────────────▼────────────────────────────────────┐
│          VirtualService (routing rules)                  │
└────────────────────┬────────────────────────────────────┘
                     │
┌────────────────────▼────────────────────────────────────┐
│          go-ms Service (ClusterIP)                       │
└────────────────────┬────────────────────────────────────┘
                     │
         ┌───────────┴───────────┐
         │                       │
┌────────▼────────┐    ┌────────▼────────┐
│  go-ms Pod      │    │  PostgreSQL     │
│  (2 containers) │    │  StatefulSet    │
│  - app          │    │                 │
│  - istio-proxy  │    │                 │
└─────────────────┘    └─────────────────┘
```

## Troubleshooting

### Cluster won't start

```bash
# Check k3d clusters
k3d cluster list

# Delete and recreate
make local-delete
make local-setup
```

### Pods not starting

```bash
# Check pod status
kubectl get pods -n go-ms

# Describe pod
kubectl describe pod -n go-ms <pod-name>

# Check logs
kubectl logs -n go-ms <pod-name>

# Check Istio sidecar
kubectl logs -n go-ms <pod-name> -c istio-proxy
```

### Certificate not issued

```bash
# Check certificate
kubectl get certificate -n go-ms

# Check cert-manager logs
kubectl logs -n cert-manager deployment/cert-manager

# Check ClusterIssuer
kubectl describe clusterissuer letsencrypt-cloudflare

# For local dev, you can skip cert-manager:
kubectl delete -f k8s/cert-manager/certificate.yaml
```

### Image not found

```bash
# List images in k3d
k3d image list -c go-ms-local

# Import image manually
docker build -t ghcr.io/gauravv/dev-go-ms-api:local -f Dockerfile .
k3d image import ghcr.io/gauravv/dev-go-ms-api:local -c go-ms-local
```

### Reset Everything

```bash
make local-delete
docker system prune -f
make local-setup
make local-up
```

## Storage

PostgreSQL data is stored in a k3d volume. To persist across restarts:

```bash
# Volume is automatically created and persists
# To completely reset data:
kubectl delete pvc postgres-data -n go-ms
make local-up
```

## Next Steps

- Install Istio addons for observability:
  ```bash
  ./scripts/install-istio-addons.sh
  ```
- Access Grafana dashboards:
  ```bash
  kubectl port-forward -n istio-system svc/grafana 3000:3000
  ```
- View service mesh in Kiali:
  ```bash
  kubectl port-forward -n istio-system svc/kiali 20001:20001
  ```
