# Request Lifecycle - Go Microservice Architecture

This document diagrams the complete lifecycle of an HTTP request through the Go microservice architecture, from external client to database and back.

---

## Overview Diagram

```mermaid
graph TB
    subgraph "External Layer"
        Client[Client Application<br/>Browser, Mobile, CLI]
        CF[Cloudflare DNS<br/>dev-go-ms-api.gauravv.dev]
    end

    subgraph "AWS Infrastructure - Production"
        R53[Route 53<br/>Latency-based Routing]
        ALB[ALB<br/>Application Load Balancer<br/>SSL Termination]
        WAF[AWS WAF<br/>Rate Limiting, DDoS Protection]
    end

    subgraph "Kubernetes Cluster"
        subgraph "Istio Ingress"
            IGW[Istio Gateway<br/>Envoy Proxy<br/>Port 443/8080]
        end

        subgraph "Service Mesh"
            VS[VirtualService<br/>Routing Rules]
            DR[DestinationRule<br/>mTLS Policy]
            AP[AuthorizationPolicy<br/>Access Control]
        end

        subgraph "Application Layer"
            subgraph "go-ms Pod 1"
                IS1[Istio Sidecar<br/>Envoy Proxy]
                APP1[go-ms Container<br/>Go 1.24]
            end

            subgraph "go-ms Pod 2"
                IS2[Istio Sidecar<br/>Envoy Proxy]
                APP2[go-ms Container<br/>Go 1.24]
            end
        end

        subgraph "Data Layer"
            subgraph "postgres Pod"
                ISP[Istio Sidecar<br/>Envoy Proxy]
                PG[PostgreSQL<br/>StatefulSet]
            end
        end
    end

    subgraph "Middleware Chain (inside go-ms container)"
        REC[Recovery Middleware<br/>Panic Handling]
        RID[Request ID Middleware<br/>Correlation ID]
        LOG[Logger Middleware<br/>Structured Logging]
        CORS[CORS Middleware<br/>Headers Validation]
        AUTH[Auth Middleware<br/>API Key Validation]
        HNDL[Handler<br/>Business Logic]
    end

    Client -->|1. DNS Query| CF
    CF -->|2. CNAME| R53
    R53 -->|3. A Record| ALB
    ALB -->|4. TLS/HTTPS| WAF
    WAF -->|5. HTTP/1.1| IGW
    IGW -->|6. mTLS| VS
    VS -->|7. Routing| DR
    DR -->|8. mTLS| AP
    AP -->|9. Distribute| IS1
    AP -->|9. Distribute| IS2
    IS1 -->|10. mTLS| APP1
    IS2 -->|10. mTLS| APP2
    APP1 -->|11. Request Chain| REC
    REC --> RID
    RID --> LOG
    LOG --> CORS
    CORS --> AUTH
    AUTH -->|12. Valid API Key?| HNDL
    HNDL -->|13. pgx Driver| IS1
    IS1 -->|14. mTLS| ISP
    ISP -->|15. Query| PG

    PG -->|16. Result| ISP
    ISP -->|17. mTLS| IS1
    IS1 -->|18. Response| APP1
    APP1 -->|19. Response Chain| HNDL
    HNDL --> AUTH
    AUTH --> CORS
    CORS --> LOG
    LOG --> RID
    RID --> REC
    REC --> IS1
    IS1 -->|20. mTLS| IGW
    IGW -->|21. HTTPS| WAF
    WAF -->|22. Response| ALB
    ALB -->|23. JSON| Client

    style Client fill:#e1f5fe
    style APP1 fill:#c8e6c9
    style APP2 fill:#c8e6c9
    style PG fill:#fff9c4
    style IGW fill:#ffccbc
    style IS1 fill:#b2dfdb
    style IS2 fill:#b2dfdb
    style ISP fill:#b2dfdb
```

---

## Detailed Request Flow

### Phase 1: External Entry (Production AWS)

```mermaid
sequenceDiagram
    participant Client as Client Application
    participant DNS as Cloudflare DNS
    participant R53 as Route 53
    participant ALB as AWS ALB
    participant WAF as AWS WAF
    participant IGW as Istio Gateway

    Client->>DNS: 1. DNS Query: dev-go-ms-api.gauravv.dev
    DNS-->>Client: 2. CNAME: go-ms.elb.us-east-1.amazonaws.com

    Client->>R53: 3. Resolve ALB endpoint
    R53-->>Client: 4. A Record: ALB IP (nearest region)

    Client->>ALB: 5. HTTPS Request<br/>GET /books<br/>X-API-Key: prod-key-123

    Note over ALB,WAF: AWS Edge Layer
    ALB->>WAF: 6. Check WAF Rules
    WAF->>ALB: 7. Allow (no threats)

    ALB->>ALB: 8. SSL Termination (ACM Certificate)
    ALB->>ALB: 9. Health Check Validation
    ALB->>IGW: 10. Forward to Istio Gateway (HTTP/1.1)

    Note over IGW: Kubernetes Cluster Entry
```

### Phase 2: Kubernetes Service Mesh Entry

```mermaid
sequenceDiagram
    participant IGW as Istio Gateway<br/>(Envoy)
    participant VS as VirtualService
    participant DR as DestinationRule
    participant AP as AuthorizationPolicy
    participant Sidecar as Istio Sidecar

    IGW->>VS: 1. Match Host: dev-go-ms-api.gauravv.dev
    VS-->>IGW: 2. Route found: go-ms service

    IGW->>DR: 3. Check Destination Rules
    DR-->>IGW: 4. Subset: v1, mTLS: STRICT

    IGW->>AP: 5. Check Authorization
    AP->>AP: 6. Allow /health (public)<br/>Allow /books/* (authenticated)

    IGW->>Sidecar: 7. Distribute request (round-robin)<br/>Pod 1 or Pod 2

    Note over Sidecar: Service Mesh Encryption
    Sidecar->>Sidecar: 8. mTLS handshake<br/>Mesh CA certificate
```

### Phase 3: Application Middleware Chain

```mermaid
sequenceDiagram
    participant Sidecar as Istio Sidecar<br/>(Envoy Proxy)
    participant Rec as Recovery Middleware
    participant RID as Request ID Middleware
    participant Log as Logger Middleware
    participant Cors as CORS Middleware
    participant Auth as Auth Middleware
    participant Handler as Book Handler

    Sidecar->>Rec: 1. HTTP Request received<br/>X-Request-ID: abc-123

    Rec->>RID: 2. Recover from panics
    RID->>RID: 3. Generate/Validate Request ID<br/>req-id: xyz-789
    RID->>Log: 4. Add request context

    Log->>Log: 5. Log incoming request<br/>{"method":"GET","path":"/books"}

    Log->>Cors: 6. Check CORS headers
    Cors->>Auth: 7. Valid Origin

    Auth->>Auth: 8. Extract X-API-Key header
    Auth->>Auth: 9. Validate against configured keys
    Auth->>Handler: 10. Request authenticated

    Note over Handler: Business Logic Layer
```

### Phase 4: Handler to Database

```mermaid
sequenceDiagram
    participant Handler as Book Handler
    participant Store as PostgresStore
    participant DB as PostgreSQL<br/>(via pgx driver)
    participant SidecarDB as DB Istio Sidecar

    Handler->>Store: 1. store.ListBooks()<br/>Get all books

    Store->>DB: 2. Query: SELECT * FROM books
    Note over DB: pgx Connection Pool

    DB->>SidecarDB: 3. mTLS encrypted request
    SidecarDB->>SidecarDB: 4. Forward to PostgreSQL

    SidecarDB-->>DB: 5. Query result
    DB-->>Store: 6. []model.Book

    Store->>Store: 7. Map to domain models
    Store-->>Handler: 8. Return books

    Handler->>Handler: 9. JSON serialization
    Handler-->>Sidecar: 10. HTTP Response<br/>Content-Type: application/json
```

### Phase 5: Response Journey

```mermaid
sequenceDiagram
    participant Handler as Handler
    participant Auth as Auth Middleware
    participant Log as Logger Middleware
    participant Sidecar as Istio Sidecar
    participant IGW as Istio Gateway
    participant ALB as AWS ALB
    participant Client as Client

    Handler->>Auth: 1. Response: {"status":"ok", "data": [...]}
    Auth->>Log: 2. Pass through
    Log->>Log: 3. Log response<br/>{"status":200,"duration":"15ms"}

    Log->>Sidecar: 4. Forward response
    Note over Sidecar: Add Headers:<br/>X-Request-ID: xyz-789<br/>X-Envoy-Upstream-Service-Time: 15

    Sidecar->>IGW: 5. mTLS response
    IGW->>ALB: 6. HTTPS response
    ALB->>Client: 7. Final JSON response

    Note over Client: Total duration: ~50-100ms<br/>(including AWS edge)
```

---

## Component Communication Details

### 1. Client → Cloudflare DNS

```
Request:  DNS A record query
Domain:   dev-go-ms-api.gauravv.dev
Response: CNAME → go-ms.elb.us-east-1.amazonaws.com
```

### 2. Route 53 → ALB

```
Routing Policy:   Latency-based
Health Check:    HTTPS:443/health
Target:          ALB in nearest AWS region
```

### 3. ALB → Istio Gateway

```
Protocol:         HTTP/1.1 (after SSL termination)
Target Port:      8080 (service mesh)
Health Check:     /health endpoint every 30s
```

### 4. Istio Gateway → VirtualService

```yaml
# VirtualService routing rules
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
spec:
  hosts:
  - "dev-go-ms-api.gauravv.dev"
  gateways:
  - go-ms-gateway
  http:
  - match:
    - uri:
        prefix: /books
    route:
    - destination:
        host: go-ms
        subset: v1
      weight: 100
```

### 5. VirtualService → DestinationRule

```yaml
# mTLS and traffic policy
apiVersion: networking.istio.io/v1beta1
kind: DestinationRule
spec:
  host: go-ms
  trafficPolicy:
    tls:
      mode: ISTIO_MUTUAL  # mTLS between services
    loadBalancer:
      simple: ROUND_ROBIN
```

### 6. AuthorizationPolicy

```yaml
# Access control
apiVersion: security.istio.io/v1beta1
kind: AuthorizationPolicy
spec:
  selector:
    matchLabels:
      app: go-ms
  rules:
  - to:
    - operation:
        paths: ["/health"]
  - when:
    - key: request.headers[X-API-Key]
      values: ["prod-key-123", "dev-key-456"]
```

### 7. Istio Sidecar → Application Container

```
Communication:   localhost (same pod)
Protocol:        HTTP/1.1
Headers Added:
  - X-Request-ID
  - X-Forwarded-For
  - X-Envoy-Original-Path
```

### 8. Application → PostgreSQL

```
Driver:          pgx/v5 (pure Go PostgreSQL driver)
Connection Pool:  5 max connections
Query Timeout:   30 seconds
Idle Timeout:    5 minutes
```

---

## Middleware Chain Details

```go
// Middleware execution order (cmd/server/main.go)

func main() {
    mux := http.NewServeMux()

    // Middleware chain (applied in reverse order of wrapping)
    handler := middleware.Recovery(
        middleware.RequestID(
            middleware.Logger(
                middleware.CORS(
                    middleware.Auth(
                        handler.Routes(),
                    ),
                ),
            ),
        ),
    )

    // Final chain:
    // Request → Recovery → RequestID → Logger → CORS → Auth → Handler
}
```

### Each Middleware's Role

| Middleware | Responsibility | Example Action |
|-------------|------------------|----------------|
| **Recovery** | Catch panics | Log error, return 500 |
| **RequestID** | Correlation | Generate/read `X-Request-ID` header |
| **Logger** | Observability | Log method, path, status, duration |
| **CORS** | Browser security | Add `Access-Control-Allow-Origin` header |
| **Auth** | Authorization | Validate `X-API-Key` header |

---

## Local Development Flow (k3d)

When running locally with `make local-up`:

```mermaid
graph LR
    Client[localhost:8080<br/>Port Forward] --> IGW[Istio Gateway]
    IGW --> VS[VirtualService]
    VS --> APP[go-ms Pods]
    APP --> PG[PostgreSQL]

    style Client fill:#e1f5fe
    style APP fill:#c8e6c9
    style PG fill:#fff9c4
```

**Access Methods:**

```bash
# Method 1: Port-forward (simplest)
kubectl port-forward -n go-ms svc/go-ms 8080:8080
curl http://localhost:8080/health

# Method 2: Via /etc/hosts (simulates production)
127.0.0.1 dev-go-ms-api.gauravv.dev
curl http://dev-go-ms-api.gauravv.dev:8443/health

# Method 3: Direct pod access
kubectl exec -n go-ms <pod-name> -- curl http://localhost:8080/health
```

---

## Time Breakdown (Typical Request)

| Phase | Duration | Notes |
|-------|----------|-------|
| **Client → AWS Edge** | 10-30ms | DNS + Route 53 latency routing |
| **ALB → Istio Gateway** | 5-10ms | VPC network, load balancer |
| **Istio Gateway → Sidecar** | 2-5ms | Service mesh routing |
| **Middleware Processing** | <1ms | In-memory Go code |
| **Handler → Database** | 5-15ms | Query execution + connection pool |
| **Return Path** | Same | Response follows same path back |
| **Total** | **25-60ms** | End-to-end for simple GET |

---

## Security in Transit

```mermaid
graph TB
    subgraph "Encryption Layers"
        L1[Layer 1: Client → ALB<br/>TLS 1.3 (ACM Certificate)]
        L2[Layer 2: ALB → Gateway<br/>HTTPS (VPC-internal)]
        L3[Layer 3: Service Mesh<br/>mTLS (ISTIO_MUTUAL)]
        L4[Layer 4: Pod → Pod<br/>mTLS (sidecar-to-sidecar)]
    end

    L1 --> L2 --> L3 --> L4

    style L1 fill:#c8e6c9
    style L2 fill:#a5d6a7
    style L3 fill:#81c784
    style L4 fill:#4caf50
```

**All traffic is encrypted:**
1. **Client ↔ ALB:** Public TLS (Let's Encrypt via cert-manager)
2. **ALB ↔ Gateway:** VPC-internal HTTPS
3. **Service ↔ Service:** mTLS (Istio automatic)
4. **App ↔ Database:** mTLS (service mesh enforcement)

---

## Observability: Distributed Tracing

```mermaid
graph LR
    Client[Client] -->|req-id: abc-123| ALB[ALB]
    ALB -->|req-id: abc-123| IGW[Gateway]
    IGW -->|x-request-id: abc-123| APP[go-ms]
    APP -->|x-request-id: abc-123| DB[PostgreSQL]

    APP -->|Logs| Loki[Log Aggregator]
    IGW -->|Metrics| Prometheus[Metrics]
    IGW -->|Traces| Jaeger[Trace Collector]

    style Client fill:#e1f5fe
    style APP fill:#c8e6c9
    style DB fill:#fff9c4
    style Loki fill:#ffccbc
    style Prometheus fill:#b2dfdb
    style Jaeger fill:#ce93d8
```

**Every request has:**
- **Request ID:** Traces from client to database
- **Structured Logs:** JSON format with correlation
- **Metrics:** Request count, latency, error rate
- **Traces:** Span tree in Jaeger (optional add-on)

---

## Summary

The request flows through **7 distinct layers**:

1. **External DNS** (Cloudflare → Route 53)
2. **AWS Edge** (ALB + WAF)
3. **Service Mesh Entry** (Istio Gateway)
4. **Service Mesh Routing** (VirtualService → DestinationRule)
5. **Authorization** (AuthorizationPolicy)
6. **Application** (Middleware chain → Handler)
7. **Data Layer** (PostgreSQL via pgx)

**Key Characteristics:**
- ✅ All traffic encrypted (3 layers)
- ✅ Authentication at mesh edge (API key)
- ✅ Authorization per endpoint (policy-based)
- ✅ Observability throughout (request ID correlation)
- ✅ Zero single point of failure (multi-AZ, multi-pod)

---

**Last Updated:** 2026-02-12
**Stack:** Go 1.24 + Istio 1.24 + PostgreSQL 15 + AWS EKS
