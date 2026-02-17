#!/bin/bash
set -e

REGISTRY="ghcr.io/gauravv/dev-go-ms-api"
IMAGE_NAME="dev-go-ms-api"
TAG="local"

# Colors
GREEN='\033[0;32m'
NC='\033[0m'

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

# Build image
log_info "Building Docker image..."
docker build -t $REGISTRY:$TAG -f Dockerfile .

# Load into k3d
log_info "Loading image into k3d..."
k3d image import $REGISTRY:$TAG -c go-ms-local

# Update kustomize to use local image
log_info "Updating kustomize for local image..."
cat > k8s/overlays/local/kustomization.yaml <<EOF
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: go-ms

resources:
  - ../../base
  - ../../postgres

images:
  - name: ghcr.io/gauravv/dev-go-ms-api
    newName: $REGISTRY
    newTag: $TAG

# Use Let's Encrypt staging for local (no rate limits)
patches:
  - patch: |-
      - op: replace
        path: /spec/acme/server
        value: https://acme-staging-v02.api.letsencrypt.org/directory
    target:
      kind: ClusterIssuer
      name: letsencrypt-cloudflare
EOF

log_info "Image loaded and manifests updated!"
