# Architecture Documentation

## System Overview

This document describes the architecture of Airbyte 2.0.1 deployed on Google Kubernetes Engine (GKE) with Workload Identity.

## High-Level Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                     Google Cloud Project                     │
│                                                              │
│  ┌────────────────────────────────────────────────────────┐ │
│  │              GKE Cluster (airbyte-cluster)             │ │
│  │                                                         │ │
│  │  ┌──────────────────────────────────────────────────┐  │ │
│  │  │         Namespace: airbyte                       │  │ │
│  │  │                                                   │  │ │
│  │  │  ┌──────────┐  ┌──────────┐  ┌──────────┐      │  │ │
│  │  │  │ Webapp   │  │  Server  │  │  Worker  │      │  │ │
│  │  │  │ (UI)     │  │  (API)   │  │ (Jobs)   │      │  │ │
│  │  │  │ :8000    │  │  :8001   │  │          │      │  │ │
│  │  │  └────┬─────┘  └────┬─────┘  └────┬─────┘      │  │ │
│  │  │       │             │             │             │  │ │
│  │  │       └─────────────┴─────────────┘             │  │ │
│  │  │                     │                           │  │ │
│  │  │       ┌─────────────┴─────────────┐            │  │ │
│  │  │       │                           │             │  │ │
│  │  │  ┌────▼─────┐              ┌─────▼──────┐     │  │ │
│  │  │  │PostgreSQL│              │   Minio    │     │  │ │
│  │  │  │  (Meta)  │              │ (Storage)  │     │  │ │
│  │  │  │  :5432   │              │ :9000/9001 │     │  │ │
│  │  │  └──────────┘              └────────────┘     │  │ │
│  │  │                                                │  │ │
│  │  └──────────────────────────────────────────────┘  │ │
│  │                                                     │ │
│  │  Workload Identity:                                │ │
│  │  KSA: airbyte-sa ←→ GSA: airbyte-gsa@PROJECT     │ │
│  └────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
```

## Core Components

### 1. Airbyte Webapp

**Purpose**: User interface for Airbyte

**Technical Details:**
- **Deployment**: `airbyte-webapp`
- **Image**: `airbyte/webapp:2.0.1`
- **Port**: 8000
- **Service**: ClusterIP (`airbyte-webapp-svc`)
- **Resource Limits**: 500m CPU, 1Gi Memory
- **Replicas**: 1 (can scale horizontally)

**Configuration:**
- Connects to server via `INTERNAL_API_HOST`
- Basic authentication enabled
- Health checks on `/` endpoint

**Access Method:**
```bash
kubectl port-forward -n airbyte svc/airbyte-webapp-svc 8000:8000
```

### 2. Airbyte Server

**Purpose**: API server and orchestration engine

**Technical Details:**
- **Deployment**: `airbyte-server`
- **Image**: `airbyte/server:2.0.1`
- **Port**: 8001
- **Service**: ClusterIP (`airbyte-server-svc`)
- **Resource Limits**: 2 CPU, 4Gi Memory
- **Replicas**: 1 (can scale with external state store)

**Key Endpoints:**
- Health: `GET /v1/health`
- Public API: `POST /api/public/v1/*` (Bearer token required)

**Configuration:**
- `DATABASE_HOST`: PostgreSQL connection
- `MINIO_ENDPOINT`: Object storage connection
- `TRACKING_STRATEGY`: Anonymous (can be disabled)
- `WORKLOAD_API_HOST`: Worker communication

**Health Checks:**
- Liveness: `/v1/health` (initial delay: 30s)
- Readiness: `/v1/health` (initial delay: 10s)

### 3. Airbyte Worker

**Purpose**: Executes sync jobs and connector operations

**Technical Details:**
- **Deployment**: `airbyte-worker`
- **Image**: `airbyte/worker:2.0.1`
- **Resource Limits**: 2 CPU, 4Gi Memory
- **Replicas**: 1-N (horizontal scaling supported)

**Configuration:**
- `MAX_SYNC_WORKERS`: Number of concurrent syncs
- `MAX_SPEC_WORKERS`: Number of concurrent spec checks
- `MAX_CHECK_WORKERS`: Number of concurrent connection checks
- `SYNC_JOB_MAX_ATTEMPTS`: Retry attempts for failed syncs
- `SYNC_JOB_MAX_TIMEOUT_DAYS`: Maximum sync duration

**Volume Mounts:**
- Docker socket: `/var/run/docker.sock` (for running connectors)
- Workspace: `/tmp/workspace` (temporary data)

**Scaling Considerations:**
- Can scale horizontally to handle more concurrent syncs
- Each replica needs access to Docker socket
- Resource limits should match expected workload

### 4. PostgreSQL

**Purpose**: Stores Airbyte metadata, connections, and schedules

**Technical Details:**
- **StatefulSet**: `airbyte-db`
- **Image**: `postgres:13-alpine`
- **Port**: 5432
- **Service**: ClusterIP (`airbyte-db-svc`)
- **Storage**: 50Gi PersistentVolumeClaim
- **Resource Limits**: 1 CPU, 2Gi Memory

**Data Stored:**
- Workspace configurations
- Source and destination definitions
- Connection configurations
- Sync schedules and history
- User authentication data

**Backup Strategy:**
- Use Airbyte API backup scripts (recommended)
- Or PostgreSQL native backup tools
- Regular snapshots of PVC

**Production Alternative:**
- Cloud SQL for PostgreSQL (recommended)
- See `k8s/airbyte/optional/EXTERNAL_DATABASE.md`

### 5. Minio

**Purpose**: Object storage for sync state and temporary data

**Technical Details:**
- **StatefulSet**: `airbyte-minio`
- **Image**: `minio/minio:latest`
- **Ports**: 9000 (API), 9001 (Console)
- **Service**: ClusterIP (`airbyte-minio-svc`)
- **Storage**: 100Gi PersistentVolumeClaim
- **Resource Limits**: 1 CPU, 2Gi Memory

**Data Stored:**
- Sync state files
- Temporary connector data
- Logs and artifacts

**Production Alternative:**
- Google Cloud Storage (GCS) - recommended
- AWS S3
- Azure Blob Storage

## Authentication & Security

### Workload Identity

**Architecture:**

```
┌─────────────────────────────────────────┐
│   Kubernetes (GKE Cluster)              │
│                                          │
│   Pod: airbyte-server                   │
│   ├── ServiceAccount: airbyte-sa        │
│   └── Annotation:                        │
│       iam.gke.io/gcp-service-account    │
│       = airbyte-gsa@PROJECT_ID          │
└──────────────┬──────────────────────────┘
               │
               │ (Workload Identity Binding)
               │
┌──────────────▼──────────────────────────┐
│   Google Cloud IAM                       │
│                                          │
│   Service Account:                       │
│   airbyte-gsa@PROJECT_ID.iam            │
│   └── IAM Bindings:                      │
│       - roles/iam.workloadIdentityUser   │
│       - (other GCP service roles)        │
└─────────────────────────────────────────┘
```

**How It Works:**
1. Pod uses Kubernetes Service Account `airbyte-sa`
2. KSA is annotated with Google Service Account
3. GCP automatically exchanges K8s token for GCP token
4. No service account keys needed!

**Configuration:**
```yaml
# Kubernetes Service Account
apiVersion: v1
kind: ServiceAccount
metadata:
  name: airbyte-sa
  namespace: airbyte
  annotations:
    iam.gke.io/gcp-service-account: airbyte-gsa@PROJECT_ID.iam.gserviceaccount.com
```

**IAM Binding:**
```bash
gcloud iam service-accounts add-iam-policy-binding \
  airbyte-gsa@PROJECT_ID.iam.gserviceaccount.com \
  --role roles/iam.workloadIdentityUser \
  --member "serviceAccount:PROJECT_ID.svc.id.goog[airbyte/airbyte-sa]"
```

### Basic Authentication

**UI Access:**
- Configured in webapp deployment
- Credentials stored in `k8s/secrets.yaml`
- Default: `airbyte` / `password` (CHANGE IN PRODUCTION!)

### API Authentication

**Airbyte 2.0+ API:**
- Endpoint: `/api/public/v1/*`
- Authentication: Bearer token
- Generate token: Settings → Account → Applications

**Example:**
```bash
curl -H "Authorization: Bearer YOUR_TOKEN" \
  http://localhost:8001/api/public/v1/workspaces
```

## Network Architecture

### Service Types

All services use **ClusterIP** (internal only):

```
External Access (port-forward)
        │
        ▼
┌──────────────────────────────┐
│  airbyte-webapp-svc:8000    │ (ClusterIP)
└──────────────┬───────────────┘
               │
        Internal Routing
               │
               ▼
┌──────────────────────────────┐
│  airbyte-server-svc:8001    │ (ClusterIP)
└──────────────┬───────────────┘
               │
        ┌──────┴────────┐
        │               │
        ▼               ▼
┌───────────────┐  ┌──────────────┐
│ airbyte-db    │  │ airbyte-minio│
│ -svc:5432     │  │ -svc:9000    │
└───────────────┘  └──────────────┘
```

**No Public IPs:**
- Services not exposed to internet
- Access via `kubectl port-forward`
- Or use internal load balancer (optional)

**Internal DNS:**
- Format: `<service>.<namespace>.svc.cluster.local`
- Example: `airbyte-server-svc.airbyte.svc.cluster.local:8001`

### Port Mappings

| Component  | Service Port | Container Port | Protocol |
|-----------|-------------|----------------|----------|
| Webapp    | 8000        | 8000           | HTTP     |
| Server    | 8001        | 8001           | HTTP     |
| PostgreSQL| 5432        | 5432           | TCP      |
| Minio API | 9000        | 9000           | HTTP     |
| Minio UI  | 9001        | 9001           | HTTP     |

## Resource Management

### Resource Quotas (Namespace Level)

```yaml
# k8s/resource-quota.yaml
spec:
  hard:
    requests.cpu: "10"
    requests.memory: "20Gi"
    limits.cpu: "20"
    limits.memory: "40Gi"
    persistentvolumeclaims: "10"
    requests.storage: "500Gi"
    pods: "50"
```

### LimitRange (Default Container Limits)

```yaml
spec:
  limits:
  - default:        # Default limits
      cpu: 1
      memory: 1Gi
    defaultRequest: # Default requests
      cpu: 500m
      memory: 512Mi
    max:           # Maximum allowed
      cpu: 2
      memory: 4Gi
    min:           # Minimum allowed
      cpu: 100m
      memory: 128Mi
```

### Component Resource Allocation

| Component   | CPU Request | CPU Limit | Memory Request | Memory Limit |
|------------|-------------|-----------|----------------|--------------|
| Server     | 1           | 2         | 2Gi            | 4Gi          |
| Worker     | 1           | 2         | 2Gi            | 4Gi          |
| Webapp     | 250m        | 500m      | 512Mi          | 1Gi          |
| PostgreSQL | 500m        | 1         | 1Gi            | 2Gi          |
| Minio      | 500m        | 1         | 1Gi            | 2Gi          |

## High Availability

### PodDisruptionBudgets

```yaml
# Ensures minimum replicas during disruptions
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: airbyte-server-pdb
spec:
  minAvailable: 1
  selector:
    matchLabels:
      app: airbyte-server
```

**Configured For:**
- airbyte-server (minAvailable: 1)
- airbyte-worker (minAvailable: 1)

**Benefits:**
- Prevents all pods being terminated during node maintenance
- Ensures service availability during updates
- Kubernetes respects PDB during voluntary disruptions

### Health Checks

**Liveness Probes:**
- Detects if container is alive
- Restarts container if check fails
- Configured for: server, webapp

**Readiness Probes:**
- Detects if container is ready to serve traffic
- Removes from service endpoints if not ready
- Configured for: server, webapp, worker

### StatefulSet Guarantees

**For PostgreSQL and Minio:**
- Stable network identity
- Stable persistent storage
- Ordered deployment and scaling
- Ordered rolling updates

## Data Persistence

### PersistentVolumeClaims

**PostgreSQL:**
```yaml
storage: 50Gi
storageClassName: standard-rwo
accessModes: [ReadWriteOnce]
```

**Minio:**
```yaml
storage: 100Gi
storageClassName: standard-rwo
accessModes: [ReadWriteOnce]
```

**Storage Classes (GKE Default):**
- `standard-rwo`: Standard persistent disk (HDD)
- `premium-rwo`: SSD persistent disk (recommended for PostgreSQL)

### Backup Strategy

**Application-Level Backup:**
- Use `backup-airbyte-v2.sh` script
- Backs up via Airbyte Public API
- Stores: workspaces, sources, destinations, connections
- Compressed `.tar.gz` archives

**Infrastructure-Level Backup:**
- GKE Volume Snapshots
- PostgreSQL pg_dump
- Minio bucket replication

## Scaling Strategies

### Horizontal Scaling

**Workers (Recommended):**
```bash
kubectl scale deployment airbyte-worker -n airbyte --replicas=3
```

**Benefits:**
- More concurrent sync jobs
- Better resource utilization
- Improved throughput

**Webapp (Optional):**
```bash
kubectl scale deployment airbyte-webapp -n airbyte --replicas=2
```

**Benefits:**
- Handle more concurrent UI users
- Load distribution

### Vertical Scaling

**Increase Resource Limits:**
```yaml
# Edit deployment
resources:
  requests:
    cpu: 2
    memory: 4Gi
  limits:
    cpu: 4
    memory: 8Gi
```

**Apply Changes:**
```bash
kubectl apply -f k8s/airbyte/worker.yaml
```

### Node Scaling

**GKE Cluster Autoscaler:**
```bash
gcloud container clusters update airbyte-cluster \
  --enable-autoscaling \
  --min-nodes=3 \
  --max-nodes=10 \
  --zone=us-central1-a
```

## Monitoring and Observability

### Kubernetes Native

**Pod Metrics:**
```bash
kubectl top pods -n airbyte
kubectl get pods -n airbyte -o wide
```

**Events:**
```bash
kubectl get events -n airbyte --sort-by='.lastTimestamp'
```

**Logs:**
```bash
kubectl logs -n airbyte deployment/airbyte-server --tail=100 -f
kubectl logs -n airbyte deployment/airbyte-worker --tail=100 -f
```

### Health Check Script

**Automated checks:**
- Pod status and readiness
- Service availability
- StatefulSet status
- PVC binding
- API health endpoint
- Database connectivity

**Run:**
```bash
./scripts/health-check.sh
```

### Google Cloud Monitoring

**Integrate with:**
- Cloud Monitoring (Stackdriver)
- Cloud Logging
- GKE Dashboard

**Metrics to Monitor:**
- CPU and memory usage
- Pod restart count
- Sync job success rate
- API response times
- Database connections

## Security Best Practices

### Network Security

- ✅ ClusterIP services (no public exposure)
- ✅ Use kubectl port-forward for access
- ✅ NetworkPolicies (can be added)
- ✅ Private GKE cluster (optional)

### Authentication

- ✅ Workload Identity (no SA keys)
- ✅ Basic auth for UI
- ✅ Bearer token for API
- ✅ Change default passwords

### Secrets Management

- ✅ Kubernetes Secrets (base64)
- 🔄 Consider: Google Secret Manager
- 🔄 Consider: External Secrets Operator

### RBAC

- ✅ Dedicated service account per component
- 🔄 Add RBAC policies for service accounts
- 🔄 Principle of least privilege

## Disaster Recovery

### Backup Strategy

**Regular Backups:**
- Daily API backups (via CronJob)
- Volume snapshots (weekly)
- Configuration files in git

**Backup Storage:**
- Google Cloud Storage
- Versioned and encrypted

### Recovery Procedures

**1. Application Recovery:**
```bash
./scripts/restore-airbyte-v2.sh <backup-file>
```

**2. Database Recovery:**
```bash
# Restore from PVC snapshot or pg_dump
```

**3. Full Cluster Recreation:**
```bash
./scripts/create-cluster.sh
kubectl apply -f k8s/
./scripts/restore-airbyte-v2.sh <backup-file>
```

### RTO and RPO

**Target Objectives:**
- **RTO (Recovery Time Objective)**: < 1 hour
- **RPO (Recovery Point Objective)**: < 24 hours (daily backups)

## Upgrade Strategy

### Rolling Updates

Kubernetes deployments use rolling updates by default:

```yaml
strategy:
  type: RollingUpdate
  rollingUpdate:
    maxSurge: 1
    maxUnavailable: 0
```

**Process:**
1. Update image version in manifest
2. Apply changes: `kubectl apply -f k8s/airbyte/`
3. Monitor rollout: `kubectl rollout status deployment/airbyte-server -n airbyte`
4. Rollback if needed: `kubectl rollout undo deployment/airbyte-server -n airbyte`

### Version Compatibility

**Airbyte 2.0+ Changes:**
- API endpoint changed to `/api/public/v1`
- Health endpoint changed to `/v1/health`
- Bearer token authentication required
- Update backup/restore scripts to v2

**Before Upgrading:**
1. Backup current configuration
2. Review release notes
3. Test in development environment
4. Update manifests
5. Apply changes during maintenance window

## Performance Optimization

### Database Optimization

**For PostgreSQL:**
- Use SSD storage (`premium-rwo`)
- Increase shared_buffers
- Regular VACUUM
- Connection pooling

**For Production:**
- Use Cloud SQL for PostgreSQL
- Enable automatic backups
- Configure replication

### Storage Optimization

**For Minio:**
- Use SSD for better I/O
- Enable lifecycle policies
- Regular cleanup of old data

**For Production:**
- Use Google Cloud Storage
- Lifecycle management rules
- Multi-region for DR

### Worker Optimization

**Tuning Parameters:**
- `MAX_SYNC_WORKERS`: Based on CPU cores
- `SYNC_JOB_MAX_TIMEOUT_DAYS`: Based on sync duration
- Resource limits: Based on connector requirements

## Troubleshooting

See [TROUBLESHOOTING.md](TROUBLESHOOTING.md) for detailed troubleshooting procedures.

---

**Document Version**: 1.0
**Last Updated**: 2025-11-10
**Airbyte Version**: 2.0.1
