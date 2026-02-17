#!/bin/bash
set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

# Detect OS
OS="$(uname -s)"
case "${OS}" in
    Linux*)     MACHINE=Linux;;
    Darwin*)    MACHINE=Mac;;
    MINGW*|MSYS*|CYGWIN*)    MACHINE=Windows;;
    *)          MACHINE="UNKNOWN:${OS}"
esac

log_info "Detected OS: $MACHINE"

# Check if k3d is installed
if ! command -v k3d &> /dev/null; then
    log_info "Installing k3d..."
    if [ "$MACHINE" = "Mac" ]; then
        brew install k3d
    elif [ "$MACHINE" = "Linux" ]; then
        curl -s https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash
    else
        log_warn "Please install k3d manually from https://k3d.io"
        exit 1
    fi
fi

# Check if kubectl is installed
if ! command -v kubectl &> /dev/null; then
    log_info "Installing kubectl..."
    if [ "$MACHINE" = "Mac" ]; then
        brew install kubectl
    elif [ "$MACHINE" = "Linux" ]; then
        curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
        chmod +x kubectl
        sudo mv kubectl /usr/local/bin/
    fi
fi

# Check if istioctl is installed
if ! command -v istioctl &> /dev/null; then
    log_info "Installing istioctl..."
    if [ "$MACHINE" = "Mac" ]; then
        brew install istioctl
    else
        curl -L https://istio.io/downloadIstio | sh -
        cd istio-*
        chmod +x bin/istioctl
        sudo mv bin/istioctl /usr/local/bin/
        cd ..
    fi
fi

# Check if helm is installed (useful for cert-manager)
if ! command -v helm &> /dev/null; then
    log_info "Installing helm..."
    if [ "$MACHINE" = "Mac" ]; then
        brew install helm
    else
        curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
    fi
fi

log_info "All tools installed!"
echo ""
echo "Versions:"
k3d version
kubectl version --client
istioctl version --remote=false
helm version --short

# Create local cluster
log_info "Creating local k3d cluster..."
k3d cluster create go-ms-local \
    --agents 1 \
    --port "8080:80@loadbalancer" \
    --port "8443:443@loadbalancer" \
    --k3s-arg "--disable=traefik@server:0" \
    --k3s-arg "--disable=servicelb@server:0" || {
    log_warn "Cluster may already exist. Continuing..."
}

log_info "Cluster created!"
kubectl cluster-info

# Install Istio
log_info "Installing Istio..."
istioctl install --set profile=default -y --skip-confirmation

# Wait for Istio to be ready
log_info "Waiting for Istio to be ready..."
kubectl wait -n istio-system --for=condition=available --timeout=120s deployment/istiod

# Install cert-manager (using helm for local)
log_info "Installing cert-manager..."
helm repo add jetstack https://charts.jetstack.io
helm repo update
helm install cert-manager jetstack/cert-manager \
    --namespace cert-manager \
    --version v1.15.0 \
    --set installCRDs=true \
    --create-namespace

# Wait for cert-manager
log_info "Waiting for cert-manager to be ready..."
kubectl wait -n cert-manager --for=condition=available --timeout=120s deployment/cert-manager
kubectl wait -n cert-manager --for=condition=available --timeout=120s deployment/cert-manager-cainjector
kubectl wait -n cert-manager --for=condition=available --timeout=120s deployment/cert-manager-webhook

log_info "Local cluster setup complete!"
echo ""
echo "Next steps:"
echo "  1. Build container image: make docker-build"
echo "  2. Load image into k3d: ./scripts/local-load-image.sh"
echo "  3. Deploy: ./scripts/deploy-local.sh"
echo ""
echo "Or use: make local-up"
