.PHONY: help build run test clean docker-up docker-down docker-logs docker-build migrate-up migrate-down lint local-setup local-up local-down local-restart local-logs local-status

# Variables
APP_NAME := book-service
CMD_DIR := ./cmd/server
DOCKER_COMPOSE := docker-compose
GO := go

help: ## Show this help message
	@echo 'Usage: make [target]'
	@echo ''
	@echo 'Available targets:'
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)

build: ## Build the application
	@echo "Building $(APP_NAME)..."
	$(GO) build -o $(APP_NAME) $(CMD_DIR)
	@echo "Build complete: ./$(APP_NAME)"

run: ## Run the application
	@echo "Running $(APP_NAME)..."
	$(GO) run $(CMD_DIR)

test: ## Run tests
	@echo "Running tests..."
	$(GO) test -v -race -cover ./...

test-short: ## Run short tests
	@echo "Running short tests..."
	$(GO) test -v -short ./...

clean: ## Clean build artifacts
	@echo "Cleaning..."
	rm -f $(APP_NAME)
	rm -rf tmp/
	@echo "Clean complete"

lint: ## Run linter
	@echo "Running linter..."
	@if command -v golangci-lint >/dev/null 2>&1; then \
		golangci-lint run ./...; \
	else \
		echo "golangci-lint not installed. Run: go install github.com/golangci/golangci-lint/cmd/golangci-lint@latest"; \
	fi

docker-build: ## Build Docker images
	@echo "Building Docker images..."
	$(DOCKER_COMPOSE) build
	@echo "Docker build complete"

docker-up: ## Start Docker containers
	@echo "Starting Docker containers..."
	$(DOCKER_COMPOSE) up -d
	@echo "Containers started"
	@echo "App: http://localhost:8080"
	@echo "Health: http://localhost:8080/health"

docker-dev: ## Start development environment with hot reload
	@echo "Starting development environment..."
	$(DOCKER_COMPOSE) --profile dev up
	@echo "Dev environment started"

docker-down: ## Stop Docker containers
	@echo "Stopping Docker containers..."
	$(DOCKER_COMPOSE) down
	@echo "Containers stopped"

docker-logs: ## Show Docker logs
	$(DOCKER_COMPOSE) logs -f

docker-ps: ## Show running containers
	$(DOCKER_COMPOSE) ps

docker-restart: docker-down docker-up ## Restart Docker containers

# Database migration targets
migrate-up: ## Run database migrations
	@echo "Running migrations..."
	@if [ -n "$(DATABASE_URL)" ]; then \
		psql $(DATABASE_URL) -f migrations/001_create_books_table.up.sql; \
	else \
		echo "DATABASE_URL not set. Using docker postgres..."; \
		docker exec -i go-ms-postgres psql -U bookuser -d bookdb -f /dev/stdin < migrations/001_create_books_table.up.sql; \
	fi
	@echo "Migrations complete"

migrate-down: ## Rollback database migrations (manual)
	@echo "Rollback not implemented. Use psql to manually rollback."

db-shell: ## Open database shell
	docker exec -it go-ms-postgres psql -U bookuser -d bookdb

# Development helpers
dev: ## Run with in-memory store for quick testing
	AUTH_ENABLED=false DATABASE_URL="" $(GO) run $(CMD_DIR)

deps: ## Download dependencies
	$(GO) mod download
	$(GO) mod tidy

fmt: ## Format code
	$(GO) fmt ./...

vet: ## Run go vet
	$(GO) vet ./...

# CI/CD
ci: fmt vet test ## Run CI checks (fmt, vet, test)

# Local Kubernetes development (k3d)
local-setup: ## Setup local k3d cluster with Istio and cert-manager
	@echo "Setting up local k3d cluster..."
	./scripts/local-setup.sh

local-up: ## Deploy to local k3d cluster
	@echo "Building and deploying to local cluster..."
	docker build -t ghcr.io/gauravv/dev-go-ms-api:local -f Dockerfile .
	k3d image import ghcr.io/gauravv/dev-go-ms-api:local -c go-ms-local
	./scripts/deploy-local.sh

local-down: ## Stop local k3d cluster
	@echo "Stopping local cluster..."
	k3d cluster stop go-ms-local || true

local-start: ## Start local k3d cluster
	@echo "Starting local cluster..."
	k3d cluster start go-ms-local

local-delete: ## Delete local k3d cluster
	@echo "Deleting local cluster..."
	k3d cluster delete go-ms-local

local-restart: local-down local-start ## Restart local cluster

local-logs: ## Show logs from local cluster
	kubectl logs -n go-ms -l app=go-ms -f

local-status: ## Show status of local cluster
	@echo "=== Cluster ==="
	k3d cluster list
	@echo ""
	@echo "=== Pods ==="
	kubectl get pods -n go-ms
	@echo ""
	@echo "=== Services ==="
	kubectl get svc -n go-ms
	@echo ""
	@echo "=== Istio ==="
	kubectl get gateway,virtualservice -n go-ms

local-port-forward: ## Port-forward to local service
	kubectl port-forward -n go-ms svc/go-ms 8080:8080

local-exec: ## Open shell in pod
	@echo "Opening shell in go-ms pod..."
	kubectl exec -it -n go-ms $$(kubectl get pod -n go-ms -l app=go-ms -o jsonpath='{.items[0].metadata.name}') -- sh

.DEFAULT_GOAL := help
