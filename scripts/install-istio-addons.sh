#!/bin/bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
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

# Check if istioctl is installed
if ! command -v istioctl &> /dev/null; then
    log_error "istioctl is not installed"
    log_info "Install from: https://istio.io/latest/docs/setup/getting-started/"
    exit 1
fi

ISTIO_VERSION=$(istioctl version --remote=false 2>/dev/null | head -1)
log_info "Istio version: $ISTIO_VERSION"

# Prompt for addons
echo ""
log_info "This script will install Istio addons for observability"
echo ""
echo "Available addons:"
echo "  1) Prometheus (metrics)"
echo "  2) Grafana (dashboards)"
echo "  3) Jaeger (tracing)"
echo "  4) Kiali (mesh visualization)"
echo "  5) All addons"
echo "  6) Cancel"
echo ""
read -p "Select option [1-6]: " choice

case $choice in
    1)
        ADDONS="prometheus"
        ;;
    2)
        ADDONS="grafana"
        ;;
    3)
        ADDONS="jaeger"
        ;;
    4)
        ADDONS="kiali"
        ;;
    5)
        ADDONS="prometheus grafana jaeger kiali"
        ;;
    6)
        log_info "Cancelled"
        exit 0
        ;;
    *)
        log_error "Invalid option"
        exit 1
        ;;
esac

NAMESPACE="istio-system"

# Create namespace if it doesn't exist
log_info "Ensuring $NAMESPACE namespace exists..."
kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

# Install addons
for addon in $ADDONS; do
    log_info "Installing $addon..."
    istioctl addon install "$addon" --set values.global.istioNamespace="$NAMESPACE" || {
        log_warn "$addon may already be installed or istioctl version doesn't support addon install"
        log_info "Trying manual installation..."
        case $addon in
            prometheus)
                kubectl apply -f https://raw.githubusercontent.com/istio/istio/release-1.20/samples/addons/prometheus.yaml
                ;;
            grafana)
                kubectl apply -f https://raw.githubusercontent.com/istio/istio/release-1.20/samples/addons/grafana.yaml
                ;;
            jaeger)
                kubectl apply -f https://raw.githubusercontent.com/istio/istio/release-1.20/samples/addons/jaeger.yaml
                ;;
            kiali)
                kubectl apply -f https://raw.githubusercontent.com/istio/istio/release-1.20/samples/addons/kiali.yaml
                ;;
        esac
    }
done

# Wait for deployments
log_info "Waiting for addons to be ready..."
for addon in $ADDONS; do
    kubectl wait -n "$NAMESPACE" --for=condition=available --timeout=120s "deployment/${addon}" 2>/dev/null || true
done

log_info "Addons installed!"
echo ""
echo "Access dashboards:"
echo ""

for addon in $ADDONS; do
    case $addon in
        prometheus)
            echo "  Prometheus: kubectl port-forward -n $NAMESPACE svc/prometheus 9090:9090"
            echo "               Open: http://localhost:9090"
            ;;
        grafana)
            echo "  Grafana:    kubectl port-forward -n $NAMESPACE svc/grafana 3000:3000"
            echo "               Open: http://localhost:3000 (admin/admin)"
            ;;
        jaeger)
            echo "  Jaeger:     kubectl port-forward -n $NAMESPACE svc/tracing 16686:16686"
            echo "               Open: http://localhost:16686"
            ;;
        kiali)
            echo "  Kiali:      kubectl port-forward -n $NAMESPACE svc/kiali 20001:20001"
            echo "               Open: http://localhost:20001"
            ;;
    esac
done
echo ""
