#!/bin/bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
NAMESPACE="${NAMESPACE:-go-ms}"
CONTEXT="${CONTEXT:-}"
SKIP_TLS="${SKIP_TLS:-false}"

# Functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

check_kubectl() {
    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl is not installed"
        exit 1
    fi

    if [ -n "$CONTEXT" ]; then
        log_info "Using context: $CONTEXT"
        kubectl config use-context "$CONTEXT"
    fi

    log_info "Cluster: $(kubectl config current-context)"
}

check_istio() {
    if ! command -v istioctl &> /dev/null; then
        log_warn "istioctl not found. Istio resources won't be applied."
        return 1
    fi

    local version
    version=$(istioctl version --remote=false 2>/dev/null | head -1 || echo "not found")
    log_info "Istio: $version"
}

create_namespace() {
    log_info "Creating namespace: $NAMESPACE"
    kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
    kubectl label namespace "$NAMESPACE" istio-injection=enabled --overwrite 2>/dev/null || true
}

deploy_postgres() {
    log_info "Deploying PostgreSQL..."
    if [ -f "k8s/postgres/kustomization.yaml" ]; then
        kustomize build k8s/postgres | kubectl apply -f -
    else
        kubectl apply -f k8s/postgres/
    fi
    kubectl wait -n "$NAMESPACE" --for=condition=ready pod -l app=postgres --timeout=300s
}

run_migrations() {
    log_info "Running database migrations..."
    local pod
    pod=$(kubectl get pod -n "$NAMESPACE" -l app=postgres -o jsonpath='{.items[0].metadata.name}')

    if [ -n "$pod" ]; then
        kubectl exec -n "$NAMESPACE" "$pod" -- psql -U bookuser -d bookdb -c "
            SELECT EXISTS (
                SELECT FROM information_schema.tables
                WHERE table_schema = 'public'
                AND table_name = 'books'
            );
        " > /dev/null 2>&1 || {
            log_info "Creating books table..."
            kubectl exec -n "$NAMESPACE" "$pod" -- psql -U bookuser -d bookdb < migrations/001_create_books_table.up.sql || true
        }
    fi
}

deploy_app() {
    log_info "Deploying application..."
    if [ -f "k8s/base/kustomization.yaml" ]; then
        kustomize build k8s/base | kubectl apply -f -
    else
        kubectl apply -f k8s/base/
    fi
    kubectl rollout status deployment/go-ms -n "$NAMESPACE" --timeout=300s
}

deploy_istio() {
    if check_istio; then
        log_info "Deploying Istio resources..."
        kubectl apply -f k8s/istio/
    else
        log_warn "Skipping Istio resources"
    fi
}

deploy_cert_manager() {
    if [ "$SKIP_TLS" = "true" ]; then
        log_warn "Skipping cert-manager (SKIP_TLS=true)"
        return
    fi

    log_info "Deploying cert-manager resources..."
    kubectl apply -f k8s/cert-manager/certificate.yaml
}

show_status() {
    log_info "Deployment status:"
    echo ""
    echo "=== Pods ==="
    kubectl get pods -n "$NAMESPACE"
    echo ""
    echo "=== Services ==="
    kubectl get svc -n "$NAMESPACE"
    echo ""
    echo "=== Certificate ==="
    kubectl get certificate -n "$NAMESPACE" 2>/dev/null || log_warn "Certificate not found"

    if check_istio; then
        echo ""
        echo "=== Istio Resources ==="
        kubectl get gateway,virtualservice -n "$NAMESPACE"
    fi
}

test_deployment() {
    log_info "Running smoke tests..."
    kubectl port-forward -n "$NAMESPACE" svc/go-ms 8080:8080 > /dev/null 2>&1 &
    local pf_pid=$!
    sleep 5

    if curl -f http://localhost:8080/health > /dev/null 2>&1; then
        log_info "Health check passed"
    else
        log_error "Health check failed"
    fi

    kill $pf_pid 2>/dev/null || true
}

# Main deployment flow
main() {
    log_info "Starting deployment to $NAMESPACE..."

    check_kubectl
    create_namespace
    deploy_postgres
    run_migrations
    deploy_app
    deploy_istio
    deploy_cert_manager
    show_status
    test_deployment

    log_info "Deployment complete!"
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -n|--namespace)
            NAMESPACE="$2"
            shift 2
            ;;
        -c|--context)
            CONTEXT="$2"
            shift 2
            ;;
        --skip-tls)
            SKIP_TLS=true
            shift
            ;;
        --status-only)
            check_kubectl
            show_status
            exit 0
            ;;
        --rollback)
            log_info "Rolling back deployment..."
            kubectl rollout undo deployment/go-ms -n "$NAMESPACE"
            kubectl rollout status deployment/go-ms -n "$NAMESPACE"
            exit 0
            ;;
        -h|--help)
            echo "Usage: $0 [options]"
            echo ""
            echo "Options:"
            echo "  -n, --namespace <name>   Kubernetes namespace (default: go-ms)"
            echo "  -c, --context <name>     kubectl context to use"
            echo "      --skip-tls           Skip cert-manager deployment"
            echo "      --status-only        Show deployment status only"
            echo "      --rollback           Rollback deployment"
            echo "  -h, --help               Show this help"
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

main
