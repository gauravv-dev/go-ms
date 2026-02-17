# Troubleshooting Guide: Go Microservice Kubernetes Deployment

This document details all issues encountered during local Kubernetes deployment and their resolutions, plus a detailed explanation of the request flow.

## Table of Contents
- [Issues and Resolutions](#issues-and-resolutions)
  - [Issue 1: Go Version Compatibility](#issue-1-go-version-compatibility)
  - [Issue 2: Binary Permission Denied](#issue-2-binary-permission-denied)
  - [Issue 3: PostgreSQL VolumeMount Not Found](#issue-3-postgresql-volumemount-not-found)
  - [Issue 4: Health Probe 401 Unauthorized](#issue-4-health-probe-401-unauthorized)
  - [Issue 5: Istio VirtualService Field Errors](#issue-5-istio-virtualservice-field-errors)
  - [Issue 6: Let's Encrypt Invalid Email](#issue-6-lets-encrypt-invalid-email)
  - [Issue 7: Certificate DNS Resolution Failing](#issue-7-certificate-dns-resolution-failing)
  - [Issue 8: Istio Gateway Not Routing Traffic](#issue-8-istio-gateway-not-routing-traffic)
- [Request Path Explanation](#request-path-explanation)
- [Key Learnings](#key-learnings)

---

## Issues and Resolutions

### Issue 1: Go Version Compatibility

**Problem:**
```
go: github.com/jackc/pgx/v5@v5.8.0: module github.com/jackc/pgx/v5@v5.8.0 requires go >= 1.24.0 (running go 1.23.12)
```

The `pgx/v5` PostgreSQL driver library requires Go 1.24, but the Dockerfile was using Go 1.23 Alpine image.

**Root Cause:**
- The `go.mod` file specified `go 1.24.0` after running `go mod tidy`
- Docker images for Go 1.24 weren't initially available
- The Dockerfile hardcoded `golang:1.23-alpine`

**Resolution:**
1. Updated Dockerfile to use `golang:1.24-alpine` (image became available)
2. Ensured `go.mod` specifies `go 1.24`

**Files Changed:**
- `Dockerfile`: Changed `FROM golang:1.23-alpine` to `FROM golang:1.24-alpine`
- `go.mod`: Set version to `go 1.24`

**Lesson:** Always ensure Docker base image version matches or exceeds Go module requirements.

---

### Issue 2: Binary Permission Denied

**Problem:**
```
Error: failed to create containerd task: OCI runtime create failed: runc create failed:
unable to start container process: error during container init:
exec: "./book-service": stat ./book-service: permission denied
```

**Root Cause:**
The Dockerfile built the binary as `root` user but the Kubernetes deployment runs as `runAsUser: 1000` (non-root). When a non-root user tries to execute a root-owned binary, it fails with permission denied.

**Original Dockerfile:**
```dockerfile
# Runtime stage
FROM alpine:latest
RUN apk --no-cache add ca-certificates
WORKDIR /root/
COPY --from=builder /app/book-service .
RUN chmod +x book-service  # Still owned by root
```

**Resolution:**
Created non-root user during build and set proper ownership:

```dockerfile
# Runtime stage
FROM alpine:latest
RUN apk --no-cache add ca-certificates

# Create non-root user
RUN addgroup -g 1000 appuser && \
    adduser -D -u 1000 -G appuser appuser

WORKDIR /app

# Copy with correct ownership
COPY --from=builder --chown=appuser:appuser /app/book-service .
RUN chmod +x book-service

COPY --from=builder --chown=appuser:appuser /app/migrations ./migrations

# Switch to non-root user
USER appuser
```

**Files Changed:**
- `Dockerfile`: Added user creation, ownership changes, USER directive

**Lesson:** When running containers as non-root (security best practice), ensure the binary ownership matches the runtime user.

---

### Issue 3: PostgreSQL VolumeMount Not Found

**Problem:**
```
error: Pod "postgres-0" is invalid: spec.containers[0].volumeMounts[0].name: Not found: "postgres-data"
```

**Root Cause:**
The StatefulSet referenced a volumeMount named `postgres-data` but there was no corresponding `volume` or `volumeClaimTemplate` defined. A separate PVC was created in a different file, but StatefulSets should use `volumeClaimTemplates` for dynamic volume provisioning.

**Original Configuration:**
```yaml
# statefulset.yaml
spec:
  template:
    spec:
      containers:
      - volumeMounts:
        - name: postgres-data  # No matching volume!
          mountPath: /var/lib/postgresql/data
# Separate pvc.yaml file - doesn't work with StatefulSets this way
```

**Resolution:**
Added `volumeClaimTemplates` directly in the StatefulSet:

```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: postgres
spec:
  serviceName: postgres
  replicas: 1
  # ... template spec ...
  volumeClaimTemplates:
  - metadata:
      name: postgres-data
    spec:
      accessModes:
      - ReadWriteOnce
      resources:
        requests:
          storage: 5Gi
```

**Files Changed:**
- `k8s/postgres/statefulset.yaml`: Added `volumeClaimTemplates` section
- `k8s/postgres/kustomization.yaml`: Removed reference to separate `pvc.yaml`

**Lesson:** StatefulSets should use `volumeClaimTemplates` for storage, not separate PVC resources.

---

### Issue 4: Health Probe 401 Unauthorized

**Problem:**
```
NAME                     READY   STATUS             RESTARTS   AGE
go-ms-xxx-xxx           1/2     CrashLoopBackOff   4           2m
```

Pods showed `1/2` (istio-proxy ready, app container crashing). Logs showed:
```
"msg":"request","method":"GET","path":"/health","status":401
```

**Root Cause:**
The application requires API key authentication via `X-API-Key` header for all endpoints. The Kubernetes liveness and readiness probes were calling `/health` without this header, receiving 401 responses. This caused probes to fail, triggering pod restarts.

**Original Probe Configuration:**
```yaml
livenessProbe:
  httpGet:
    path: /health
    port: http
readinessProbe:
  httpGet:
    path: /health
    port: http
```

**Resolution:**
Added API key header to probes:

```yaml
livenessProbe:
  httpGet:
    path: /health
    port: http
    httpHeaders:
    - name: X-API-Key
      value: prod-key-123
readinessProbe:
  httpGet:
    path: /health
    port: http
    httpHeaders:
    - name: X-API-Key
      value: prod-key-123
```

**Alternative Approach:** Create a `/healthz` endpoint that bypasses authentication (requires code changes).

**Files Changed:**
- `k8s/base/deployment.yaml`: Added `httpHeaders` to probes

**Lesson:** When services require authentication for health endpoints, probes must include authentication credentials or use separate unauthenticated endpoints.

---

### Issue 5: Istio VirtualService Field Errors

**Problem:**
```
Error from server (BadRequest): error when creating "k8s/istio/virtualservice.yaml":
VirtualService in version "v1beta1" cannot be handled as a VirtualService:
strict decoding error: unknown field "spec.http[0].route[0].retries",
unknown field "spec.http[0].route[0].timeout"
```

**Root Cause:**
The VirtualService had incorrectly nested fields. In Istio API, `timeout` and `retries` should be at the `http` level (sibling to `route`), not nested inside `route`.

**Incorrect Structure:**
```yaml
http:
- match:
  - uri:
      prefix: /health
  route:
  - destination:
      host: go-ms
      port:
        number: 8080
    timeout: 5s      # WRONG: inside route
    retries: ...     # WRONG: inside route
```

**Correct Structure:**
```yaml
http:
- match:
  - uri:
      prefix: /health
  route:
  - destination:
      host: go-ms
      port:
        number: 8080
  timeout: 5s        # CORRECT: sibling to route
  retries:
    attempts: 3
    perTryTimeout: 3s
```

**Files Changed:**
- `k8s/istio/virtualservice.yaml`: Moved `timeout` and `retries` to correct nesting level

**Lesson:** Istio API structure is specific - always check field placement in the API reference.

---

### Issue 6: Let's Encrypt Invalid Email Address

**Problem:**
```
Message: Failed to register ACME account: 400 urn:ietf:params:acme:error:invalidContact:
Error validating contact(s) :: contact email has forbidden domain "example.com"
```

**Root Cause:**
The ClusterIssuer was created with a placeholder email `your-email@example.com`. Let's Encrypt rejects emails with the `example.com` domain as it's reserved for documentation.

**Original Configuration:**
```yaml
spec:
  acme:
    email: your-email@example.com  # Invalid!
```

**Resolution:**
Updated to a real email address:

```yaml
spec:
  acme:
    email: gauravaws20@gmail.com  # Real email
```

**Command Used:**
```bash
kubectl patch clusterissuer letsencrypt-cloudflare --type='json' \
  -p='[
    {"op": "replace", "path": "/spec/acme/email", "value": "gauravaws20@gmail.com"},
    {"op": "replace", "path": "/spec/acme/solvers/0/dns01/cloudflare/email", "value": "gauravaws20@gmail.com"}
  ]'
```

**Files Changed:**
- `k8s/cert-manager/cluster-issuer.yaml`: Updated email address

**Lesson:** Let's Encrypt requires valid email addresses for certificate notifications and account recovery.

---

### Issue 7: Certificate DNS Resolution Failing

**Problem:**
```
Message: Waiting for DNS-01 challenge propagation: Could not determine the zone for
"_acme-challenge.dev-go-ms-api.gauravv.dev.": When querying the SOA record for the domain
'_acme-challenge.dev-go-ms-api.gauravv.dev.' using nameservers [10.43.0.10:53],
rcode was expected to be 'NOERROR' or 'NXDOMAIN', but got 'SERVFAIL'
```

**Root Cause:**
The k3d cluster's internal DNS (CoreDNS at `10.43.0.10:53`) couldn't properly resolve external DNS records for the DNS-01 challenge. When cert-manager tried to verify the TXT record created by Cloudflare, the cluster's DNS resolver returned `SERVFAIL`.

**Why This Happened:**
1. k3d runs inside Docker with its own network stack
2. CoreDNS in k3d may not have proper upstream DNS configured
3. Local Kubernetes clusters often have DNS resolution issues for external domains

**Attempted Fix:**
Configured external DNS resolvers in ClusterIssuer (this failed due to API structure issues).

**Final Resolution:**
For local development, use HTTP instead of HTTPS with cert-manager. The DNS-01 challenge works properly on:
- Cloud-hosted Kubernetes (GKE, EKS, AKS)
- Production clusters with proper DNS
- Clusters with reliable external DNS resolution

**Workaround for Local Development:**
```bash
# Option 1: Use port-forward
kubectl port-forward -n go-ms svc/go-ms 8080:8080

# Option 2: Add to /etc/hosts
echo "127.0.0.1 dev-go-ms-api.gauravv.dev" | sudo tee -a /etc/hosts
# Access via http://dev-go-ms-api.gauravv.dev:8080
```

**Files Changed:**
- `k8s/istio/gateway.yaml`: Configured for HTTP-only for local development
- No actual fix for DNS issue - acknowledged as limitation of local k3d clusters

**Lesson:** Local Kubernetes clusters (k3d, kind, minikube) often have limitations with external DNS resolution. For SSL certificate automation, use a cloud-hosted cluster or accept HTTP-only for local development.

---

### Issue 8: Istio Gateway Not Routing Traffic

**Problem:**
```
* Request completely sent off
* Empty reply from server
curl: (52) Empty reply from server
```

When accessing the service through the Istio Gateway, connections were established but no response was returned. The istio-ingressgateway wasn't logging any requests.

**Root Causes (Multiple Issues):**

#### 8a. Namespace Mismatch
The Gateway was in `default` namespace but the VirtualService was in `go-ms` namespace, causing routing confusion.

**Fix:** Moved both Gateway and VirtualService to `go-ms` namespace.

#### 8b. Gateway Selector Not Matching
The Gateway selector was correct (`istio: ingressgateway`) but the VirtualService reference was wrong.

**Fix:** Updated VirtualService to reference gateway correctly:
```yaml
gateways:
- go-ms-gateway  # Same namespace
# vs
- default/go-ms-gateway  # Cross-namespace (wasn't working)
```

#### 8c. HTTPS Port Without Valid Certificate
The Gateway was configured for HTTPS on port 443 with a self-signed/non-existent certificate, causing TLS handshake failures.

**Fix:** Simplified to HTTP-only for local development:
```yaml
servers:
- port:
    number: 80
    name: http
    protocol: HTTP
  hosts:
    - "*"
```

#### 8d. Fundamental k3d Port Mapping Issue
**The Real Problem:** k3d's LoadBalancer maps:
- Container port 80 → Host port 8080
- Container port 443 → Host port 8443

The istio-ingressgateway Service exposes:
- port 80 → targetPort 8080 (inside pod)
- port 443 → targetPort 8443 (inside pod)

When you access `localhost:8080`, you're hitting the k3d LoadBalancer which forwards to the Service's port 80, which forwards to the pod's port 8080. The Gateway needs to be configured for port 80 (the Service port), not the target port.

**Final Resolution:**
```yaml
# Correct Gateway configuration
spec:
  servers:
  - port:
      number: 80      # Service port, not targetPort!
      name: http
      protocol: HTTP
    hosts:
      - "*"
```

**Files Changed:**
- `k8s/istio/gateway.yaml`: Multiple iterations fixing namespace, hosts, port
- `k8s/istio/virtualservice.yaml`: Fixed namespace and gateway reference

**Lesson:** In Istio, Gateway `port.number` should match the Service port, not the pod's targetPort. The Service handles the port translation.

---

## Request Path Explanation

### Overview Diagram

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              External Request                                │
│                         curl http://localhost:8080/health                      │
└─────────────────────────────────────┬───────────────────────────────────────┘
                                      │
                                      ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                          k3d LoadBalancer                                   │
│  k3d-go-ms-local-serverlb                                                   │
│  Port Mapping: 8080 (host) → 80 (container)                                 │
└─────────────────────────────────────┬───────────────────────────────────────┘
                                      │
                                      ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                    Istio IngressGateway Service                             │
│  Namespace: istio-system                                                    │
│  Type: LoadBalancer                                                         │
│  Port: 80 → targetPort 8080 (istio-ingressgateway pod)                      │
└─────────────────────────────────────┬───────────────────────────────────────┘
                                      │
                                      ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                   Istio IngressGateway Pod                                  │
│  Container: istio-proxy (envoy)                                             │
│  Listening: port 8080                                                       │
│                                                                              │
│  Processing Steps:                                                          │
│  1. Receive request on port 8080                                            │
│  2. Check Gateway configuration (port 80, host "*")                          │
│  3. Match VirtualService rules                                             │
│  4. Apply DestinationRule policies (mTLS, etc.)                             │
│  5. Establish mutual TLS connection to destination                          │
└─────────────────────────────────────┬───────────────────────────────────────┘
                                      │
                                      ▼ mTLS (encrypted)
┌─────────────────────────────────────────────────────────────────────────────┐
│                         go-ms Service                                        │
│  Namespace: go-ms                                                           │
│  Type: ClusterIP                                                            │
│  Selector: app=go-ms                                                         │
│  Port: 8080                                                                 │
└─────────────────────────────────────┬───────────────────────────────────────┘
                                      │
                                      ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                          go-ms Pod                                           │
│  Containers:                                                                │
│  ┌───────────────────────────────────────────────────────────────────────┐│
│  │ Container 2: istio-proxy (envoy)                                       ││
│  │  - Handles mTLS termination/establishment                             ││
│  │  - Enforces traffic policies                                          ││
│  │  - Provides telemetry (metrics, traces, logs)                         ││
│  │  - Forwards to localhost:8080 (application container)                ││
│  └───────────────────────────────────────────────────────────────────────┘│
│  ┌───────────────────────────────────────────────────────────────────────┐│
│  │ Container 1: go-ms (application)                                      ││
│  │  - Listening on port 8080                                            ││
│  │  - Handles HTTP request                                               ││
│  │  - Process:                                                           ││
│  │    1. Check X-API-Key header for authentication                       ││
│  │    2. Route to handler (health, list books, etc.)                     ││
│  │    3. Query database if needed                                        ││
│  │    4. Return JSON response                                            ││
│  └───────────────────────────────────────────────────────────────────────┘│
└─────────────────────────────────────────────────────────────────────────────┘
                                      │
                                      ▼ (if database access needed)
┌─────────────────────────────────────────────────────────────────────────────┐
│                         postgres Service                                     │
│  Namespace: go-ms                                                           │
│  Type: ClusterIP                                                            │
│  Port: 5432                                                                │
└─────────────────────────────────────┬───────────────────────────────────────┘
                                      │
                                      ▼ mTLS (encrypted)
┌─────────────────────────────────────────────────────────────────────────────┐
│                        postgres-0 Pod (StatefulSet)                          │
│  Container 1: postgres                                                       │
│  - PostgreSQL 17 Alpine                                                      │
│  - Listening: 5432                                                          │
│  - Executes SQL query                                                       │
│  - Returns result                                                           │
│                                                                              │
│  Container 2: istio-proxy (envoy)                                           │
│  - Handles mTLS (no access to DB without valid cert)                        │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Detailed Request Flow

#### 1. External Request to k3d LoadBalancer
```
curl http://localhost:8080/health
```
- Request sent to `localhost:8080`
- k3d LoadBalancer (`k3d-go-ms-local-serverlb`) receives traffic on port 8080
- Maps to container port 80

#### 2. Istio IngressGateway Service
- Service: `istio-ingressgateway.istio-system.svc.cluster.local:80`
- Type: LoadBalancer
- Forwards to istio-ingressgateway pods on targetPort 8080
- Selects pods with label `istio=ingressgateway`

#### 3. Istio IngressGateway Pod (Envoy)
**Configuration:**
- Gateway: `go-ms-gateway.go-ms`
  - Port: 80, Protocol: HTTP, Hosts: *
- VirtualService: `go-ms.go-ms`
  - Match: prefix `/`
  - Route: `go-ms.go-ms.svc.cluster.local:8080`
- DestinationRule: `go-ms.go-ms`
  - mTLS: STRICT mode

**Processing:**
1. Receive HTTP request on port 8080
2. Check Gateway: matches port 80, host "*"
3. Check VirtualService: matches all paths (prefix: /)
4. Check DestinationRule: apply mTLS policy
5. Establish mTLS connection to go-ms pod
6. Forward request via mutual TLS tunnel

#### 4. Service-to-Service Communication (mTLS)
```
istio-ingressgateway → go-ms service
```
- Source: istio-ingressgateway pod (with istio-proxy sidecar)
- Destination: go-ms pods (with istio-proxy sidecar)
- Mutual TLS handshake:
  1. Client presents certificate
  2. Server validates certificate
  3. Server presents certificate
  4. Client validates certificate
  5. Encrypted tunnel established
- Traffic encrypted end-to-end between pods

#### 5. go-ms Pod
**Container 1: istio-proxy (envoy)**
- Receives mTLS traffic from ingressgateway
- Validates client certificate
- Decrypts request
- Forwards to application container on localhost:8080

**Container 2: go-ms (application)**
```
Request Flow:
1. HTTP received on port 8080
2. Middleware chain:
   a. Recovery: catch panics
   b. RequestID: generate/add request ID
   c. Logger: log incoming request
   d. CORS: add CORS headers
   e. Auth: validate X-API-Key header (skipped for /health if configured)
3. Router: match route to handler
4. Handler: process request
5. Return response
```

**Example: GET /health**
```go
// Request received
GET /health HTTP/1.1
Host: dev-go-ms-api.gauravv.dev
X-API-Key: prod-key-123
X-Request-ID: abc-123-xyz

// Middleware processing
1. Recovery: OK (no panic)
2. RequestID: added to context
3. Logger: "incoming GET /health"
4. CORS: headers added
5. Auth: X-API-Key validated (or skipped for /health)

// Handler
func HandleHealth(w http.ResponseWriter, r *http.Request) {
    w.Header().Set("Content-Type", "application/json")
    json.NewEncoder(w).Encode(map[string]string{"status": "healthy"})
}

// Response
HTTP/1.1 200 OK
Content-Type: application/json
X-Request-ID: abc-123-xyz

{"status":"healthy"}
```

#### 6. Database Access (for /books endpoints)
```
go-ms pod → postgres service → postgres-0 pod
```
- Application makes SQL query via pgx driver
- Connection: `postgres://bookuser:***@postgres:5432/bookdb`
- DNS resolution: `postgres.go-ms.svc.cluster.local:5432`
- Service: selects postgres-0 pod
- mTLS: istio-proxy on postgres pod validates client certificate
- Only requests with valid mTLS certificates can reach PostgreSQL
- Query executed, result returned

---

## Key Learnings

### Docker & Kubernetes
1. **Go Version Consistency:** Always ensure Docker base image version matches or exceeds Go module requirements
2. **Non-Root Users:** When running as non-root, ensure binary ownership matches runtime user
3. **StatefulSet Storage:** Use `volumeClaimTemplates` for dynamic provisioning, not separate PVCs
4. **Health Probes:** Must include authentication credentials if endpoints are protected

### Istio Service Mesh
1. **API Structure:** Istio VirtualService fields have specific nesting - consult API reference
2. **Namespace Placement:** Keep Gateways, VirtualServices, and Services in same namespace for simplicity
3. **Port Configuration:** Gateway port = Service port, not pod targetPort
4. **mTLS:** STRICT mode requires all services to have sidecar injection enabled
5. **Local Development:** Istio + local Kubernetes (k3d) has DNS resolution limitations for external SSL

### Local Development vs Production
| Aspect | Local (k3d) | Production |
|--------|-------------|------------|
| SSL/TLS | Use HTTP or self-signed | cert-manager with Let's Encrypt |
| DNS | /etc/hosts or port-forward | Real DNS with proper records |
| LoadBalancer | k3d built-in | Cloud provider LB |
| Resource Limits | Can be minimal | Set appropriate requests/limits |

### Production Readiness Checklist
- [ ] Go version compatible with all dependencies
- [ ] Binary built for correct architecture/OS
- [ ] Non-root user with correct permissions
- [ ] Health probes include auth credentials
- [ ] Istio resources in correct namespace
- [ ] mTLS policies consistent across mesh
- [ ] Database credentials stored as Secrets
- [ ] PVCs properly configured for StatefulSets
- [ ] Gateway/VirtualService port configuration correct
- [ ] DNS properly configured for external access
- [ ] Certificates configured for HTTPS (production)

### Useful Commands

```bash
# Check pod status
kubectl get pods -n go-ms

# Check logs from specific container
kubectl logs -n go-ms <pod-name> -c go-ms
kubectl logs -n go-ms <pod-name> -c istio-proxy

# Port-forward for local testing
kubectl port-forward -n go-ms svc/go-ms 8080:8080

# Check Istio configuration
istioctl proxy-status
istioctl proxy-config routes -n go-ms deployment/go-ms

# Debug mTLS
istioctl authn check -n go-ms deployment/go-ms

# Test with API key
curl -H "X-API-Key: prod-key-123" http://localhost:8080/health
```
