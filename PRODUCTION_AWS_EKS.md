# Global AWS EKS Deployment Architecture

## Overview

Deploy the Book Management microservice globally across multiple AWS regions for low-latency access worldwide.

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              GLOBAL INFRASTRUCTURE                             │
│                                                                                │
│  Users Worldwide                                                               │
│       │                                                                        │
│       ▼                                                                        │
│  ┌───────────────────────────────────────────────────────────────────────┐  │
│  │                      Route 53 (Global DNS)                            │  │
│  │  - Latency-based routing                                               │  │
│  │  - Health checks                                                       │  │
│  │  - DNS: api.gauravv.dev                                                │  │
│  └───────────────────────────────────────────────────────────────────────┘  │
│       │                                                                        │
│       ▼                                                                        │
│  ┌───────────────────────────────────────────────────────────────────────┐  │
│  │                  AWS Global Accelerator (Optional)                      │  │
│  │  - Anycast IP                                                          │  │
│  │  - Regional endpoint groups                                           │  │
│  │  - Health-based routing                                                │  │
│  └───────────────────────────────────────────────────────────────────────┘  │
│       │                                                                        │
│       ├─── us-east-1 (N. Virginia)       ┌─── eu-west-1 (Ireland)             │
│       ├─── us-west-2 (Oregon)              ├─── ap-southeast-1 (Singapore)      │
│       └─── ap-south-1 (Mumbai)            └─── (add more regions...)           │
│       │                                                                        │
│       ▼                                                                        │
│  ┌───────────────────────────────────────────────────────────────────────┐  │
│  │                        REGION (e.g., us-east-1)                         │  │
│  │  ┌─────────────────────────────────────────────────────────────────┐  │  │
│  │  │  Internet Gateway ──▶ Public Subnets                           │  │  │
│  │  │  Network Load Balancer ──▶ EKS Cluster                          │  │  │
│  │  │                                                                  │  │  │
│  │  │  ┌────────────────────────────────────────────────────────────┐ │  │  │
│  │  │  │                   EKS Cluster                               │ │  │  │
│  │  │  │  ┌──────────────────────────────────────────────────────┐ │ │  │  │
│  │  │  │  │  Control Plane (AWS managed)                          │ │ │  │  │
│  │  │  │  │  - API Server                                          │ │ │  │  │
│  │  │  │  │  - etcd                                                │ │ │  │  │
│  │  │  │  │  - Scheduler                                           │ │ │  │  │
│  │  │  │  └──────────────────────────────────────────────────────┘ │ │  │  │
│  │  │  │                                                              │ │  │  │
│  │  │  │  ┌──────────────────────────────────────────────────────┐ │ │  │  │
│  │  │  │  │  Node Groups (3 AZs)                                  │ │ │  │  │
│  │  │  │  │  AZ-a: us-east-1a                                     │ │ │  │  │
│  │  │  │  │  AZ-b: us-east-1b                                     │ │ │  │  │
│  │  │  │  │  AZ-c: us-east-1c                                     │ │ │  │  │
│  │  │  │  └──────────────────────────────────────────────────────┘ │ │  │  │
│  │  │  │                                                              │ │  │  │
│  │  │  │  ┌──────────────────────────────────────────────────────┐ │ │  │  │
│  │  │  │  │  Workloads                                             │ │ │  │  │
│  │  │  │  │  ┌────────────────────────────────────────────────┐ │ │  │  │
│  │  │  │  │  │  ALB (Application Load Balancer)              │ │ │  │  │
│  │  │  │  │  │  - External access                                │ │ │  │  │
│  │  │  │  │  │  - SSL/TLS termination                           │ │ │  │  │
│  │  │  │  │  │  - Health checks                                   │ │ │  │  │
│  │  │  │  │  └────────────────────────────────────────────────┘ │ │  │  │
│  │  │  │  │                                                              │ │  │  │
│  │  │  │  │  ┌────────────────────────────────────────────────┐ │ │  │  │
│  │  │  │  │  │  Istio Ingress Gateway (StatefulSet)           │ │ │  │  │
│  │  │  │  │  │  - 3 replicas (1 per AZ)                         │ │ │  │  │
│  │  │  │  │  │  - NLB per instance for direct access           │ │ │  │  │
│  │  │  │  │  └────────────────────────────────────────────────┘ │ │  │  │
│  │  │  │  │                                                              │ │  │  │
│  │  │  │  │  ┌────────────────────────────────────────────────┐ │ │  │  │
│  │  │  │  │  │  go-ms Deployment                               │ │ │  │  │
│  │  │  │  │  │  - 6 replicas (2 per AZ)                         │ │ │  │  │
│  │  │  │  │  │  - HPA: 2-15 replicas                             │ │ │  │  │
│  │  │  │  │  │  - Istio sidecar per pod                          │ │ │  │  │
│  │  │  │  │  └────────────────────────────────────────────────┘ │ │  │  │
│  │  │  │  │                                                              │ │  │  │
│  │  │  │  │  ┌────────────────────────────────────────────────┐ │ │  │  │
│  │  │  │  │  │  PostgreSQL (Amazon RDS)                          │ │ │  │  │
│  │  │  │  │  │  - Multi-AZ deployment                            │ │ │  │  │
│  │  │  │  │  │  - db.r6g.large (2 vCPU, 16 GB RAM)              │ │ │  │  │
│  │  │  │  │  │  - Automated backups                               │ │ │ │  │  │
│  │  │  │  │  │  - Read replicas for scaling                        │ │ │  │  │
│  │  │  │  │  └────────────────────────────────────────────────┘ │ │  │  │
│  │  │  │  └──────────────────────────────────────────────────────┘ │ │  │  │
│  │  │  └─────────────────────────────────────────────────────────────┘ │  │
│  │  │                                                                  │  │
│  │  │  ┌─────────────────────────────────────────────────────────────┐ │  │
│  │  │  │                   Observability                              │ │  │
│  │  │  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────────┐ │ │  │
│  │  │  │  │ CloudWatch   │  │ AWS X-Ray    │  │ Prometheus/      │ │ │  │
│  │  │  │  │ Logs/Metrics │  │ Tracing      │  │ Grafana (AMP)   │ │ │  │
│  │  │  │  └──────────────┘  └──────────────┘  └──────────────────┘ │ │  │
│  │  │  └─────────────────────────────────────────────────────────────┘ │  │
│  │  └─────────────────────────────────────────────────────────────────┘  │
│  └───────────────────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Architecture Components

### 1. AWS Regions

**Primary Regions (Example):**
| Region | Location | Purpose |
|--------|----------|---------|
| `us-east-1` | N. Virginia | Primary, largest user base |
| `us-west-2` | Oregon | West coast US |
| `eu-west-1` | Ireland | Europe |
| `ap-southeast-1` | Singapore | Asia Pacific |
| `ap-south-1` | Mumbai | India |

**Selection Criteria:**
- Proximity to users
- AWS service availability
- Data residency requirements
- Latency requirements

---

### 2. Global Routing

#### Option A: Route 53 Latency-Based Routing (Recommended)

```yaml
# Route 53 Hosted Zone: gauravv.dev
Type: Public

# A Record for api.gauravv.dev
Type: A
Routing Policy: Latency-based
Records:
  - us-east-1: alb-us-east-1-xxx.elb.amazonaws.com
  - us-west-2: alb-us-west-2-xxx.elb.amazonaws.com
  - eu-west-1: alb-eu-west-1-xxx.elb.amazonaws.com
  - ap-southeast-1: alb-ap-southeast-1-xxx.elb.amazonaws.com
  - ap-south-1: alb-ap-south-1-xxx.elb.amazonaws.com

Health Checks: Enabled for each record
Failover: To nearest healthy region
```

**How it works:**
1. User queries `api.gauravv.dev`
2. Route 53 measures latency from user to all regions
3. Routes to the region with lowest latency
4. If region is unhealthy, routes to next best

#### Option B: AWS Global Accelerator

```yaml
AWS Global Accelerator:
  Type: Anycast
  Accelerator: go-ms-prod
  DNS: go-ms-prod.awsglobalaccelerator.com (CNAME to api.gauravv.dev)

  Listener: TCP 443 (HTTPS)

  Endpoint Groups (regional):
    - us-east-1:
        Endpoint: NLB-us-east-1.elb.amazonaws.com
        Weight: 100
        Health checks: Enabled

    - us-west-2:
        Endpoint: NLB-us-west-2.elb.amazonaws.com
        Weight: 100
        Health checks: Enabled

    - eu-west-1:
        Endpoint: NLB-eu-west-1.elb.amazonaws.com
        Weight: 100
        Health checks: Enabled

    # ... other regions
```

**Benefits:**
- Single anycast IP address
- Automatic failover
- DDoS protection with Shield Standard
- Preserves source IP

---

### 3. Per-Region Architecture

#### VPC Design

```
Region: us-east-1
VPC: 10.0.0.0/16
├── Public Subnets (10.0.1.0/24, 10.0.2.0/24, 10.0.3.0/24)
│   ├── Internet Gateway
│   ├── ALB (in public subnets)
│   └── NAT Gateways (one per AZ)
│
└── Private Subnets (10.0.11.0/24, 10.0.12.0/24, 10.0.13.0/24)
    ├── EKS worker nodes
    ├── RDS PostgreSQL
    └── ElastiCache (if needed)
```

#### EKS Cluster Configuration

```yaml
Cluster: go-ms-prod-us-east-1
Version: 1.29
Endpoint: public (with private API server access)

VPC: 10.0.0.0/16
Subnets:
  Public:
    - us-east-1a: 10.0.1.0/24
    - us-east-1b: 10.0.2.0/24
    - us-east-1c: 10.0.3.0/24
  Private:
    - us-east-1a: 10.0.11.0/24
    - us-east-1b: 10.0.12.0/24
    - us-east-1c: 10.0.13.0/24

Node Groups:
  Primary:
    Instance: m6i.xlarge (4 vCPU, 16 GB RAM)
    Min: 6
    Desired: 9
    Max: 30
    AZs: 3 (2 nodes per AZ initially)

  Spot (for cost optimization):
    Instance: m6i.xlarge
    Min: 0
    Desired: 3
    Max: 15

IRSA: Enabled (IAM Roles for Service Accounts)
Encryption: EKS encryption enabled
```

#### Kubernetes Resources per Region

```yaml
Namespace: go-ms

# Deployment
go-ms:
  Replicas: 6 (2 per AZ)
  HPA:
    Min: 2
    Max: 15
    Target CPU: 70%
  Node Selector:
    topology.kubernetes.io/zone: us-east-1a,us-east-1b,us-east-1c
  Pod Disruption Budget:
    Min Available: 2

# Istio Gateway
istio-ingressgateway:
  Type: LoadBalancer
  Service: NLB per instance (AWS Load Balancer type)
  Replicas: 3 (1 per AZ)
  Annotations:
    service.beta.kubernetes.io/aws-load-balancer-type: nlb

# Service (ClusterIP)
go-ms:
  Ports: 8080
```

---

### 4. Database Architecture

#### Option A: RDS Multi-AZ (Single Region, Recommended)

```
Region: us-east-1

RDS PostgreSQL:
  Instance: db.r6g.large
    - 2 vCPU, 16 GB RAM
    - 1000 GB SSD (gp3)

  Multi-AZ: Yes (standby in different AZ)
  Encryption: At rest and in transit

  Backup:
    - Retention: 30 days
    - Window: 03:00-04:00 UTC
    - PITR: Enabled

  Read Replicas:
    us-east-1a: 2 read replicas (for read scaling)
    us-east-1b: 1 read replica
```

**Connection String:**
```go
// Primary
database-url: "postgres://user:pass@go-ms-db.cluster-xxx.us-east-1.rds.amazonaws.com:5432/go-ms"

// Read replicas (round-robin for reads)
read-replica-urls:
  - "postgres://user:pass@go-ms-db-ro-1.xxx.us-east-1.rds.amazonaws.com:5432/go-ms"
  - "postgres://user:pass@go-ms-db-ro-2.xxx.us-east-1.rds.amazonaws.com:5432/go-ms"
```

#### Option B: Aurora Global Database (Multi-Region)

```
Primary Region: us-east-1
  Writer: db.r6g.large
  Readers: 2 replicas

Secondary Regions:
  eu-west-1:
    Reader: db.r6g.large (1 second lag max)

  ap-southeast-1:
    Reader: db.r6g.large (1 second lag max)

Cross-region replication: Asynchronous
Failover: Manual promotion of secondary (for DR)
```

**When to use:**
- **RDS Multi-AZ:** Most applications, single-region writes
- **Aurora Global:** Active-active reads, global DR requirements

---

### 5. Application Deployment Strategy

#### CI/CD Pipeline

```
GitHub Repository
      │
      ▼ push to main
┌─────────────────────────────────────────────────────────────┐
│  GitHub Actions                                            │
│  ┌─────────────────────────────────────────────────────────┐│
│  │ 1. Build & Test                                         ││
│  │    - Run tests                                         ││
│  │    - Build container image                             ││
│  └─────────────────────────────────────────────────────────┘│
│  ┌─────────────────────────────────────────────────────────┐│
│  │ 2. Push to ECR                                          ││
│  │    - Tag: git SHA, branch, latest                       ││
│  │    - Region: us-east-1 (replicated by AWS)              ││
│  └─────────────────────────────────────────────────────────┘│
│  ┌─────────────────────────────────────────────────────────┐│
│  │ 3. Deploy to all regions (parallel)                     ││
│  │    - Update k8s manifests with new image                ││
│  │    - ArgoCD syncs to each cluster                        ││
│  │    - Canary deployment per region                        ││
│  └─────────────────────────────────────────────────────────┘│
└─────────────────────────────────────────────────────────────┘
      │
      ├─── us-east-1 cluster ──► ArgoCD ──► go-ms deployment
      ├─── us-west-2 cluster ──► ArgoCD ──► go-ms deployment
      ├─── eu-west-1 cluster ──► ArgoCD ──► go-ms deployment
      └─── ap-southeast-1 ──► ArgoCD ──► go-ms deployment
```

#### GitOps with ArgoCD

```yaml
# ArgoCD App per region
App: go-ms-prod-us-east-1
Source: GitHub repo (path: k8s/overlays/production)
Destination: https://eks-xxx.us-east-1.amazonaws.com
Sync Policy: Automatic
Auto-Prune: Yes

App: go-ms-prod-eu-west-1
Source: GitHub repo (path: k8s/overlays/production)
Destination: https://eks-xxx.eu-west-1.amazonaws.com
Sync Policy: Automatic
Auto-Prune: Yes

# ... similar for other regions
```

#### Blue-Green or Canary Deployment

```yaml
# Istio VirtualService for Canary
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: go-ms
spec:
  hosts:
  - api.gauravv.dev
  http:
  - match:
    - headers:
        x-canary:
          exact: "true"
    route:
    - destination:
        host: go-ms-canary  # 10% traffic initially
      weight: 100
  - route:
    - destination:
        host: go-ms-stable  # 90% traffic
      weight: 100
```

---

### 6. Istio Multi-Cluster Setup

#### Multi-Network Architecture

```
Each region = Separate Istio mesh (multi-network)

Region us-east-1:
  Cluster: eks-us-east-1
  Network: 10.0.0.0/16
  Istio Revision: prod

Region eu-west-1:
  Cluster: eks-eu-west-1
  Network: 10.1.0.0/16
  Istio Revision: prod
```

#### Cross-Region Service Discovery

```yaml
# ServiceEntry for remote services (us-east-1 cluster)
apiVersion: networking.istio.io/v1beta1
kind: ServiceEntry
metadata:
  name: go-ms-eu-west-1
spec:
  hosts:
  - go-ms.eu-west-1.svc.cluster.local
  location: eu-west-1
  ports:
  - number: 8080
    name: http
    protocol: HTTP
  resolution: DNS
  endpoints:
  - address: nlb-eu-west-1.elb.amazonaws.com
    ports:
      http: 15443  # SNI routing
```

**Note:** For true global mesh, use:
- Istio Multi-Primary (recommended for EKS)
- TSB (Tetrate Service Bridge)
- Or AWS App Mesh (AWS-native alternative)

---

### 7. Security Architecture

```
Internet
  │
  ▼
┌─────────────────────────────────────────────────────────────┐
│  AWS WAF (Web Application Firewall)                         │
│  - SQL injection protection                                  │
│  - XSS protection                                            │
│  - Rate limiting                                             │
│  - Bot protection                                            │
└────────────────────────┬────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────┐
│  ALB (Application Load Balancer)                            │
│  - SSL/TLS: AWS Certificate Manager (ACM)                   │
│  - Certificate: *.gauravv.dev (public cert)                 │
│  - Security Policy: Redirect HTTP to HTTPS                  │
│  - Target groups: EKS nodes                                   │
└────────────────────────┬────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────┐
│  Istio Gateway                                              │
│  - Mutual TLS (mTLS) between services                        │
│  - JWT authentication/OIDC with Cognito                       │
│  - Authorization policies                                     │
│  - Rate limiting per service                                  │
└─────────────────────────────────────────────────────────────┘
```

#### Authentication Flow

```
┌──────────────────────────────────────────────────────────────┐
│  Client Request                                               │
│  GET https://api.gauravv.dev/books                            │
│  Authorization: Bearer <JWT token>                             │
└──────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌──────────────────────────────────────────────────────────────┐
│  ALB terminates TLS                                           │
│  Passes JWT token to Istio Gateway                            │
└──────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌──────────────────────────────────────────────────────────────┐
│  Istio Gateway                                                │
│  - JWT Authentication policy                                  │
│  - Validates JWT with Amazon Cognito                         │
│  - Adds user info to headers                                  │
└──────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌──────────────────────────────────────────────────────────────┐
│  go-ms service                                                │
│  - Authorization policy checks HTTP headers                   │
│  - Enforces fine-grained permissions                          │
└──────────────────────────────────────────────────────────────┘
```

---

### 8. Secrets Management

```yaml
# AWS Secrets Manager (per region)
Region: us-east-1
Secret: go-ms-prod/us-east-1
  database-url: postgres://user:pass@...
  api-keys: prod-key-xxx,prod-key-yyy
  jwt-secret: <signing-key>

Region: eu-west-1
Secret: go-ms-prod/eu-west-1
  database-url: postgres://user:pass@...
  api-keys: prod-key-xxx,prod-key-yyy
  jwt-secret: <signing-key>

# Kubernetes External Secrets Operator
Secret:
  Name: go-ms-secrets
  RefreshInterval: 1h
  remoteRef:
    kind: Secret
    name: go-ms-prod/us-east-1
```

---

### 9. Observability

#### Centralized Logging

```
Each Region:
  EKS pods ──▶ Fluent Bit ──▶ CloudWatch Logs

Central:
  CloudWatch Logs Insights
    - Cross-region queries
    - Log aggregation
    - Alerting
```

#### Metrics

```
Prometheus (AMP - Amazon Managed Prometheus):
  - Scrape each region
  - Global dashboards in Grafana

CloudWatch:
  - Container Insights
  - ALB metrics
  - RDS metrics
```

#### Tracing

```
AWS X-Ray:
  - Distributed tracing across regions
  - Service map visualization
  - Performance analysis
```

---

### 10. Disaster Recovery

#### Backup Strategy

```
RDS Automated Backups:
  - Daily snapshots (30-day retention)
  - Point-in-time recovery (35 days)
  - Cross-region snapshot replication

EKS:
  - Velero for cluster backup
  - ETS (EKS on EBS) for persistent control plane
```

#### Failover Scenarios

```
Region Failure (us-east-1 down):
  1. Route 53 detects health check failure
  2. DNS updates to route to eu-west-1
  3. Users redirected automatically
  4. Read traffic can go to Aurora read replicas

  RTO: ~2-3 minutes
  RPO: ~0 (if using Aurora global DB)

Database Failure:
  1. RDS Multi-AZ promotes standby
  2. Automatic DNS update
  3. Connection pool drains/reconnects

  RTO: ~30-60 seconds
  RPO: ~0
```

---

## Cost Optimization

### AWS Services Cost Estimation (Per Region)

| Service | Spec | Monthly Cost (USD) |
|---------|------|-------------------|
| EKS Control Plane | $72/month per cluster | $72 |
| EKS Nodes (6x m6i.xlarge) | 4 vCPU, 16 GB | $624 |
| ALB | LCU + hourly | $20 |
| NLB (per gateway instance) | 3 instances | $10 |
| RDS db.r6g.large Multi-AZ | 2 vCPU, 16 GB | $450 |
| RDS Read Replicas (2x) | db.t3.medium | $100 |
| Route 53 | Hosted zone + queries | $5 |
| CloudWatch Logs | 50 GB ingestion | $30 |
| Global Accelerator (optional) | Standard tier | $100 |
| Data Transfer | Inter-region 1 TB | $50 |
| **Per Region Total** | | **~$1,461** |

**For 5 regions:** ~$7,305/month

### Cost Saving Strategies

1. **Use Spot Instances** for non-critical workloads (60-90% savings)
2. **Graviton Instances** (m6i/r6i) - 20% cheaper than Intel
3. **Reserved Instances** - 30-50% savings for 1-3 year commitment
4. **S3 for static content** instead of serving from pods
5. **Compression** - Enable gzip, reduce data transfer costs

---

## Deployment Checklist

### Prerequisites per Region
- [ ] VPC with public/private subnets across 3 AZs
- [ ] EKS cluster created (1.29+)
- [ ] Node groups provisioned
- [ ] RDS PostgreSQL Multi-AZ instance
- [ ] ACM certificate for domain
- [ ] Route 53 health checks configured
- [ ] Secrets Manager secrets created

### Application Deployment
- [ ] Docker images pushed to ECR
- [ ] Kubernetes manifests updated for region
- [ ] Istio installed on EKS
- [ ] Cert-manager installed (for local cert management)
- [ ] External Secrets Operator installed
- [ ] ArgoCD Application registered
- [ ] ALB created with SSL certificate
- [ ] Route 53 A records created (latency routing)
- [ ] WAF rules applied (optional)
- [ ] CloudWatch Alarms configured
- [ ] X-Ray daemon set deployed

### Verification
- [ ] Test endpoint: `curl https://api.gauravv.dev/health`
- [ ] Check latency from different locations
- [ ] Test region failover (disable one region)
- [ ] Run load tests
- [ ] Verify metrics collection
- [ ] Check distributed tracing

---

## Example: Deploying to a New Region

### 1. Create Infrastructure (Terraform recommended)

```hcl
# main.tf
module "eks_region" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 19.0"

  cluster_name    = "go-ms-prod-${var.region}"
  cluster_version = "1.29"

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  eks_managed_node_groups = {
    primary = {
      name = "primary"
      instance_types = ["m6i.xlarge"]
      min_size     = 6
      max_size     = 30
      desired_size = 9

      tags = {
        Environment = "production"
      }
    }
  }
}

module "rds" {
  source = "terraform-aws-modules/rds/aws"
  version = "~> 5.0"

  identifier = "go-ms-db-${var.region}"

  engine         = "postgres"
  engine_version = "15.4"
  instance_class = "db.r6g.large"

  allocated_storage     = 1000
  max_allocated_storage = 2000
  storage_encrypted     = true

  database_name   = "goms"
  master_username = "admin"

  multi_az               = true
  db_subnet_group_name  = module.vpc.database_subnet_group

  read_replica_count = 2
}
```

### 2. Install Istio

```bash
# Download istioctl
curl -L https://istio.io/downloadIstio | sh -

# Install on EKS
istioctl install --set profile=default \
  --set values.pilot.autoscaleEnabled=true \
  --set values.pilot.resources.requests.cpu=500m \
  --set values.pilot.resources.requests.memory=2048Mi \
  --set values.pilot.resources.requests.memory=2048Mi \
  --set values.global.meshID=mesh1 \
  --set values.global.multiCluster.clusterName=${REGION}
```

### 3. Deploy Application

```bash
# Update kustomize for region
cat > k8s/overlays/production/${REGION}/kustomization.yaml <<EOF
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: go-ms

resources:
  - ../../../base
  - ../../../postgres

images:
  - name: ghcr.io/gauravv/dev-go-ms-api
    newName: ${AWS_ACCOUNT}.dkr.ecr.${REGION}.amazonaws.com/go-ms
    newTag: v1.0.0

patchesStrategicMerge:
  - |-
    apiVersion: autoscaling/v2
    kind: HorizontalPodAutoscaler
    metadata:
      name: go-ms-hpa
    spec:
      minReplicas: 6
EOF

# Apply
kubectl apply -k k8s/overlays/production/${REGION}
```

### 4. Configure ALB

```bash
# Install AWS Load Balancer Controller
kubectl apply -k "github.com/aws/eks-charts/stable/aws-load-balancer-controller//crds?ref=master"
helm repo add eks https://aws.github.io/eks-charts
helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system --set clusterName=${CLUSTER_NAME}

# Create Ingress
cat > k8s/base/ingress.yaml <<EOF
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: go-ms-ingress
  namespace: go-ms
  annotations:
    kubernetes.io/ingress.class: alb
    alb.ingress.kubernetes.io/scheme: internet-facing
    alb.ingress.kubernetes.io/target-type: ip
    alb.ingress.kubernetes.io/ssl-redirect: "443"
    alb.ingress.kubernetes.io/certificate-arn: ${CERT_ARN}
    alb.ingress.kubernetes.io/healthcheck-path: /health
    alb.ingress.kubernetes.io/healthcheck-interval-seconds: "15"
    alb.ingress.kubernetes.io/healthy-threshold-count: "2"
    alb.ingress.kubernetes.io/unhealthy-threshold-count: "2"
    alb.ingress.kubernetes.io/success-codes: "200,301,302"
    alb.ingress.kubernetes.io/listen-ports: "[{\"HTTP\": 80}, {\"HTTPS\": 443}]"
spec:
  rules:
  - host: api.gauravv.dev
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: go-ms
            port:
              number: 8080
EOF

kubectl apply -f k8s/base/ingress.yaml
```

### 5. Update Route 53

```bash
# Get ALB DNS name
ALB_DNS=$(kubectl get ingress go-ms-ingress -n go-ms -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

# Create latency-based record
aws route53 change-resource-record-sets \
  --hosted-zone-id ${HOSTED_ZONE_ID} \
  --change-batch '{
    "Comment": "Add '"${REGION}"' region",
    "Changes": [{
      "Action": "CREATE",
      "ResourceRecordSet": {
        "Name": "api.gauravv.dev",
        "Type": "A",
        "AliasTarget": {
          "HostedZoneId": "${ALB_HOSTED_ZONE_ID}",
          "DNSName": "'${ALB_DNS}'",
          "EvaluateTargetHealth": true
        },
        "Region": "'${REGION}'",
        "SetIdentifier": "'${REGION}'",
        "HealthCheckId": "${HEALTH_CHECK_ID}"
      }
    }]
  }'
```

---

## Summary

### Architecture Choices

| Component | Choice | Rationale |
|-----------|--------|-----------|
| Compute | EKS with EC2 | Control plane managed, flexible node sizes |
| Service Mesh | Istio | Advanced traffic management, mTLS |
| Ingress | ALB | AWS-native, integrates with ACM/WAF |
| Database | RDS PostgreSQL Multi-AZ | Managed, HA, backups included |
| DNS | Route 53 Latency-based | Global routing, health checks |
| CI/CD | GitHub Actions + ArgoCD | GitOps, automated deployments |
| Secrets | AWS Secrets Manager | Managed, rotating, auditable |
| Observability | CloudWatch + X-Ray | AWS-integrated monitoring |

### Request Flow (Production)

```
User in Mumbai
  │
  ▼
Route 53 (ap-south-1 is lowest latency)
  │
  ▼
ALB ap-south-1 (SSL termination, WAF)
  │
  ▼
Istio Gateway ap-south-1
  │
  ▼ mTLS
go-ms pods ap-south-1
  │
  ▼ mTLS
RDS PostgreSQL ap-south-1
```

### Key Files Structure

```
go-ms/
├── infrastructure/
│   ├── terraform/
│   │   ├── regions/
│   │   │   ├── us-east-1/
│   │   │   ├── eu-west-1/
│   │   │   └── ap-south-1/
│   │   └── global/
│   │       ├── route53.tf
│   │       └── global_accelerator.tf
│   └── kubernetes/
│       ├── base/
│       └── overlays/
│           └── production/
│               ├── us-east-1/
│               ├── eu-west-1/
│               └── ap-south-1/
├── .github/
│   └── workflows/
│       ├── build-push.yml
│       └── deploy.yml
└── docs/
    ├── GLOBAL_ARCHITECTURE.md
    └── RUNBOOKS.md
```
