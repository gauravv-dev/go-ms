#!/bin/bash
set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check cluster exists
if ! k3d cluster list | grep -q "go-ms-local"; then
    log_error "Cluster 'go-ms-local' not found. Run ./scripts/local-setup.sh first."
    exit 1
fi

# Use k3d context
kubectl config use-context k3d-go-ms-local

log_info "Deploying to local cluster..."

# Create namespace
kubectl create namespace go-ms --dry-run=client -o yaml | kubectl apply -f -
kubectl label namespace go-ms istio-injection=enabled --overwrite

# Create Cloudflare secret for cert-manager (use your real token for actual SSL)
log_info "Creating Cloudflare secret..."
if ! kubectl get secret cloudflare-api-token -n cert-manager &>/dev/null; then
    log_warn "Cloudflare secret not found."
    read -p "Enter your Cloudflare API token (or press Enter to skip SSL): " CF_TOKEN
    if [ -n "$CF_TOKEN" ]; then
        kubectl create secret generic cloudflare-api-token \
            -n cert-manager \
            --from-literal=api-token="$CF_TOKEN"
    else
        log_warn "Skipping cert-manager setup. HTTP only."
        SKIP_CERT_MANAGER=true
    fi
fi

# Install ClusterIssuer
if [ "$SKIP_CERT_MANAGER" != "true" ]; then
    log_info "Installing cert-manager ClusterIssuer..."
    kubectl apply -f k8s/cert-manager/cluster-issuer.yaml
fi

# Deploy PostgreSQL
log_info "Deploying PostgreSQL..."
kubectl apply -k k8s/postgres/
kubectl wait -n go-ms --for=condition=ready pod -l app=postgres --timeout=120s

# Run migrations
log_info "Running migrations..."
POD=$(kubectl get pod -n go-ms -l app=postgres -o jsonpath='{.items[0].metadata.name}')
kubectl exec -n go-ms "$POD" -- psql -U bookuser -d bookdb < migrations/001_create_books_table.up.sql || true

# Deploy application
log_info "Deploying application..."
kubectl apply -k k8s/overlays/local/
kubectl wait -n go-ms --for=condition=available deployment/go-ms --timeout=120s

# Deploy Istio resources
log_info "Deploying Istio resources..."
kubectl apply -f k8s/istio/

# Deploy certificate (if cert-manager is set up)
if [ "$SKIP_CERT_MANAGER" != "true" ]; then
    kubectl apply -f k8s/cert-manager/certificate.yaml
fi

# Show status
log_info "Deployment status:"
echo ""
kubectl get pods -n go-ms
echo ""
kubectl get svc -n go-ms
echo ""
kubectl get gateway,virtualservice -n go-ms

# Get LoadBalancer IP
log_info "Waiting for LoadBalancer..."
sleep 5
EXTERNAL_IP=""
for i in {1..30}; do
    EXTERNAL_IP=$(kubectl get svc istio-ingressgateway -n istio-system -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
    if [ -n "$EXTERNAL_IP" ]; then
        break
    fi
    sleep 2
done

if [ -z "$EXTERNAL_IP" ]; then
    # k3d uses host IP
    EXTERNAL_IP="127.0.0.1"
fi

log_info "Deployment complete!"
echo ""
echo "========================================"
echo "Local cluster is ready!"
echo "========================================"
echo ""
echo "The service is available at:"
echo ""
if [ "$SKIP_CERT_MANAGER" = "true" ]; then
    echo "  HTTP:  http://dev-go-ms-api.gauravv.dev:8443/health"
    echo ""
    echo "Add to /etc/hosts:"
    echo "  127.0.0.1 dev-go-ms-api.gauravv.dev"
else
    echo "  HTTPS: https://dev-go-ms-api.gauravv.dev/health"
    echo ""
    echo "Add DNS A record in Cloudflare:"
    echo "  dev-go-ms-api -> $(curl -s ifconfig.me)"
fi
echo ""
echo "Test with API key:"
echo "  curl -H 'X-API-Key: prod-key-123' http://dev-go-ms-api.gauravv.dev:8443/health"
echo ""
echo "Port-forward to service:"
echo "  kubectl port-forward -n go-ms svc/go-ms 8080:8080"
echo ""

# Optional: Open browser
if command -v open &> /dev/null; then
    read -p "Open in browser? (y/N) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        open "http://dev-go-ms-api.gauravv.dev:8443/health"
    fi
fi
