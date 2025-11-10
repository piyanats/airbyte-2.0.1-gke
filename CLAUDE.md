# CLAUDE.md - Project Context for AI Assistants

> This file provides comprehensive context about the Airbyte on GKE project to help AI assistants understand the codebase, architecture, and workflows.

## Project Overview

**Project Name:** Airbyte on GKE with Workload Identity

**Purpose:** Production-ready deployment configuration for Airbyte 2.0.1 on Google Kubernetes Engine (GKE) with secure authentication, high availability, and automated operations.

**Technology Stack:**
- Airbyte 2.0.1 (Data integration platform)
- Google Kubernetes Engine (GKE)
- Google Workload Identity (keyless authentication)
- PostgreSQL (database)
- Minio (object storage)
- Bash scripts for automation

**Key Features:**
- Workload Identity for secure GCP authentication (no service account keys)
- ClusterIP services (internal access only, no public exposure)
- Basic authentication + API token support
- Automated backup/restore using Airbyte Public API
- High availability with PodDisruptionBudgets, ResourceQuota, LimitRange
- Comprehensive health checks and monitoring
- Production-ready configuration with proper resource limits

---

## Critical Context

### Airbyte Version Information

**Current Version:** 2.0.1 (October 2025)
- Released October 14, 2025
- 4-6x faster sync speeds
- Public API: `/api/public/v1` (requires Bearer token authentication)
- Health endpoint: `/v1/health` (NOT `/api/v1/health`)

### API Compatibility

**IMPORTANT:**
- Airbyte 2.0+ uses `/api/public/v1` (new Public API)
- Old API endpoint `/api/v1` is DEPRECATED
- All backup/restore scripts use v2 (Public API)
- API authentication requires Bearer token (no basic auth on API)

### Local Development Status

**CRITICAL:** Docker Compose is **NOT FUNCTIONAL**
- Docker Compose was deprecated by Airbyte in August 2024
- Airbyte does NOT publish Docker images (`airbyte/server`, `airbyte/worker`, `airbyte/webapp`) to Docker Hub
- `docker-compose.yml` in this repo is **for reference only** and will NOT work
- **ONLY working method for local development:** `abctl` (Airbyte's official CLI tool)

See: LOCAL_DEVELOPMENT.md for abctl setup instructions

---

## Directory Structure

```
/home/user/airbyte-on-gke/
├── README.md                           # Main documentation
├── ARCHITECTURE.md                     # System architecture details
├── TROUBLESHOOTING.md                  # Common issues and solutions
├── RUNBOOK.md                          # Operations procedures
├── LOCAL_DEVELOPMENT.md                # Local testing guide (abctl)
├── CLAUDE.md                          # This file (AI assistant context)
│
├── docker-compose.yml                  # ⚠️ NON-FUNCTIONAL (reference only)
├── .env.example                        # Environment variables template
├── .dockerignore                       # Docker build exclusions
├── .gitignore                         # Git exclusions
│
├── k8s/                               # Kubernetes manifests
│   ├── namespace.yaml                 # airbyte namespace
│   ├── secrets.yaml                   # Authentication secrets
│   ├── workload-identity.yaml         # Workload Identity config
│   ├── resource-quota.yaml            # Namespace resource limits
│   │
│   ├── airbyte/                       # Core Airbyte manifests
│   │   ├── configmap.yaml            # Application configuration
│   │   ├── server.yaml               # Airbyte server deployment
│   │   ├── worker.yaml               # Airbyte worker deployment
│   │   ├── webapp.yaml               # Airbyte webapp deployment
│   │   ├── services.yaml             # ClusterIP services
│   │   ├── minio.yaml                # Object storage
│   │   ├── pod-disruption-budgets.yaml  # HA configuration
│   │   │
│   │   └── optional/                 # Optional components
│   │       ├── postgres.yaml         # Internal PostgreSQL
│   │       ├── backup-cronjob-v2.yaml  # Automated backups
│   │       └── EXTERNAL_DATABASE.md  # External DB guide
│   │
│   └── examples/                      # Configuration examples
│       ├── configmap-external-database.yaml
│       └── secrets-external-database.yaml
│
└── scripts/                           # Automation scripts
    ├── create-cluster.sh             # Create GKE cluster
    ├── setup-workload-identity.sh    # Configure Workload Identity
    ├── backup-airbyte-v2.sh          # Backup using Public API
    ├── restore-airbyte-v2.sh         # Restore using Public API
    ├── health-check.sh               # Health monitoring
    ├── cleanup.sh                    # Cleanup resources
    ├── test-api-compatibility.sh     # Test API endpoints
    │
    ├── V2_MIGRATION_GUIDE.md         # Backup/restore guide
    └── API_COMPATIBILITY_WARNING.md  # API version notes
```

---

## Key Components

### 1. Airbyte Components

**Server (airbyte-server)**
- API endpoint: Port 8001
- Health check: `/v1/health`
- Public API: `/api/public/v1/*`
- Authentication: Bearer token (for API), Basic auth (for UI via webapp)
- Resource limits: 2 CPU, 4Gi memory

**Worker (airbyte-worker)**
- Executes sync jobs
- Can scale horizontally (multiple replicas)
- Resource limits: 2 CPU, 4Gi memory
- Mounts Docker socket for connector execution

**Webapp (airbyte-webapp)**
- UI frontend: Port 8000
- Routes to server for API calls
- Basic authentication enabled
- Resource limits: 500m CPU, 1Gi memory

**PostgreSQL (optional)**
- StatefulSet with PVC (50Gi)
- Stores Airbyte metadata, connections, schedules
- Can be replaced with Cloud SQL or external PostgreSQL

**Minio (optional)**
- StatefulSet with PVC (100Gi)
- Stores sync state and temporary data
- Can be replaced with GCS or S3

### 2. Authentication & Security

**Workload Identity:**
- Kubernetes Service Account: `airbyte-sa`
- Google Service Account: `airbyte-gsa@PROJECT_ID.iam.gserviceaccount.com`
- No service account key files needed
- Binding: `airbyte-sa` ↔ `airbyte-gsa`

**Basic Authentication:**
- Configured in `k8s/secrets.yaml`
- Default: username=`airbyte`, password=`password`
- Used for UI access

**API Authentication:**
- Airbyte 2.0+ requires Bearer token for Public API
- Generate token: Settings → Account → Applications
- Token format: `Bearer your-token-here`

### 3. Network Configuration

**Service Type:** ClusterIP (internal only)
- No public IP exposure
- Access via: `kubectl port-forward`
- Internal DNS: `airbyte-webapp-svc.airbyte.svc.cluster.local:8000`

**Ports:**
- Webapp: 8000 (UI)
- Server: 8001 (API)
- PostgreSQL: 5432
- Minio: 9000 (API), 9001 (Console)

### 4. High Availability Features

**PodDisruptionBudgets:**
- Server: minAvailable=1
- Worker: minAvailable=1
- Ensures minimum replicas during disruptions

**ResourceQuota (namespace-level):**
- CPU requests: 10, limits: 20
- Memory requests: 20Gi, limits: 40Gi
- Pods: 50 max
- Storage: 500Gi max

**LimitRange (default container limits):**
- CPU: 100m-2 (default 500m)
- Memory: 128Mi-4Gi (default 1Gi)

---

## Automation Scripts

### create-cluster.sh
**Purpose:** Create GKE cluster with Workload Identity enabled

**What it does:**
1. Checks for existing cluster (asks for confirmation before deletion)
2. Creates GKE cluster with Workload Identity enabled
3. Creates Google Service Account
4. Binds KSA to GSA
5. Configures IAM permissions
6. Gets cluster credentials

**Environment Variables:**
- `PROJECT_ID`: GCP project ID
- `CLUSTER_NAME`: GKE cluster name (default: airbyte-cluster)
- `ZONE`: GCP zone (default: us-central1-a)
- `MACHINE_TYPE`: Node machine type (default: n1-standard-4)
- `NUM_NODES`: Number of nodes (default: 3)
- `NAMESPACE`: Kubernetes namespace (default: airbyte)
- `KSA_NAME`: Kubernetes service account (default: airbyte-sa)
- `GSA_NAME`: Google service account (default: airbyte-gsa)

**Safety:** Asks for confirmation before cluster creation/deletion

### backup-airbyte-v2.sh
**Purpose:** Backup Airbyte configuration using Public API

**Requirements:**
- Airbyte 2.0+
- API token (Bearer authentication)
- `jq` and `curl` installed

**What it backs up:**
- Workspaces
- Sources
- Destinations
- Connections
- Source/destination definitions

**Output:** Compressed `.tar.gz` archive in `backups/` directory

**Environment Variables:**
- `AIRBYTE_API_TOKEN`: API token (required)
- `AIRBYTE_API_HOST`: API host (default: uses kubectl to find server)
- `BACKUP_DIR`: Backup directory (default: ./backups)

### restore-airbyte-v2.sh
**Purpose:** Restore Airbyte configuration from backup

**Requirements:**
- Airbyte 2.0+
- API token (Bearer authentication)
- Backup archive file

**What it restores:**
- Workspaces
- Sources
- Destinations
- Connections

**Note:** Creates new UUIDs for restored entities

### health-check.sh
**Purpose:** Comprehensive health check for all components

**Checks:**
- Pod status and readiness
- Service availability
- StatefulSet status
- PVC status
- Server API health endpoint
- Database connectivity

**Exit codes:**
- 0: All checks passed
- 1: One or more checks failed

### setup-workload-identity.sh
**Purpose:** Configure Workload Identity bindings

**What it does:**
1. Creates Google Service Account
2. Creates Kubernetes Service Account
3. Binds GSA to KSA
4. Configures IAM policy bindings

---

## Common Workflows

### 1. Initial Deployment

```bash
# Set environment variables
export PROJECT_ID="your-project-id"
export CLUSTER_NAME="airbyte-cluster"
export ZONE="us-central1-a"

# Create cluster
./scripts/create-cluster.sh

# Apply Kubernetes manifests
kubectl apply -f k8s/namespace.yaml
kubectl apply -f k8s/workload-identity.yaml
kubectl apply -f k8s/secrets.yaml

# Deploy with internal database
kubectl apply -f k8s/airbyte/optional/postgres.yaml
kubectl apply -f k8s/airbyte/

# Wait for pods to be ready
kubectl get pods -n airbyte -w

# Access Airbyte
kubectl port-forward -n airbyte svc/airbyte-webapp-svc 8000:8000
# Open http://localhost:8000
```

### 2. Backup Workflow

```bash
# Generate API token in Airbyte UI:
# Settings → Account → Applications → New Application

# Export token
export AIRBYTE_API_TOKEN='your-token'

# Run backup
./scripts/backup-airbyte-v2.sh

# Backup saved to: backups/airbyte_backup_v2_TIMESTAMP.tar.gz
```

### 3. Restore Workflow

```bash
# Export token
export AIRBYTE_API_TOKEN='your-token'

# Run restore
./scripts/restore-airbyte-v2.sh backups/airbyte_backup_v2_20240101_120000.tar.gz
```

### 4. Health Check Workflow

```bash
# Run comprehensive health check
./scripts/health-check.sh

# Check specific component
kubectl logs -n airbyte deployment/airbyte-server
kubectl describe pod -n airbyte <pod-name>
```

### 5. Scaling Workers

```bash
# Scale worker deployment
kubectl scale deployment airbyte-worker -n airbyte --replicas=3

# Verify scaling
kubectl get deployments -n airbyte
```

### 6. Cleanup Workflow

```bash
# Remove Airbyte resources (keeps cluster)
kubectl delete namespace airbyte

# Or use cleanup script
./scripts/cleanup.sh

# Delete cluster
gcloud container clusters delete airbyte-cluster --zone=us-central1-a
```

---

## Common Issues & Solutions

### Issue: Pods Not Starting
**Solution:**
1. Check pod status: `kubectl get pods -n airbyte`
2. Check logs: `kubectl logs -n airbyte deployment/airbyte-server`
3. Check events: `kubectl describe pod -n airbyte <pod-name>`
4. Common causes: insufficient resources, PVC not bound, wrong image version

### Issue: Health Check Endpoint Returns 404
**Problem:** Using old health check path `/api/v1/health`
**Solution:** Use `/v1/health` (correct for Airbyte 2.0+)

### Issue: API Authentication Fails
**Problem:** Using basic auth on API endpoint
**Solution:** Use Bearer token authentication for `/api/public/v1/*` endpoints

### Issue: Backup Script Fails
**Common causes:**
1. Missing API token
2. Wrong API host
3. Missing `jq` or `curl`
4. Server not accessible

**Solution:**
1. Generate API token in Airbyte UI
2. Verify server is accessible: `curl http://localhost:8001/v1/health`
3. Install dependencies: `apt-get install jq curl`

### Issue: Docker Compose Not Working
**Problem:** Trying to use docker-compose.yml
**Solution:** Docker Compose is NOT functional. Use `abctl` instead:
```bash
curl -LsfS https://get.airbyte.com | bash -
abctl local install
```

---

## Important Configuration Files

### k8s/secrets.yaml
```yaml
# Contains:
# - DATABASE_USER, DATABASE_PASSWORD (PostgreSQL credentials)
# - MINIO_ACCESS_KEY, MINIO_SECRET_KEY (Minio credentials)
# - BASIC_AUTH_USERNAME, BASIC_AUTH_PASSWORD (UI authentication)
```

### k8s/airbyte/configmap.yaml
```yaml
# Contains:
# - AIRBYTE_VERSION: "2.0.1"
# - INTERNAL_API_HOST: "airbyte-server-svc:8001"
# - DATABASE_HOST: "airbyte-db-svc" (change for external DB)
# - Worker configuration (MAX_SYNC_WORKERS, etc.)
# - Sync job configuration (retry attempts, timeouts)
```

### k8s/airbyte/server.yaml
```yaml
# Key configurations:
# - Image: airbyte/server:2.0.1 (or latest version)
# - Health checks: /v1/health (NOT /api/v1/health)
# - Resource limits: 2 CPU, 4Gi memory
# - Service account: airbyte-sa (for Workload Identity)
```

---

## Testing Strategy

### Local Testing
**Method:** Use `abctl` (NOT docker-compose)
```bash
# Install abctl
curl -LsfS https://get.airbyte.com | bash -

# Start Airbyte locally
abctl local install

# Get credentials
abctl local credentials

# Access: http://localhost:8000
```

### Integration Testing
```bash
# Test API compatibility
./scripts/test-api-compatibility.sh

# Test health endpoint
curl http://localhost:8001/v1/health

# Test backup/restore
./scripts/backup-airbyte-v2.sh
./scripts/restore-airbyte-v2.sh backups/latest.tar.gz
```

### Production Testing
```bash
# Run health check
./scripts/health-check.sh

# Check pod health
kubectl get pods -n airbyte

# Check logs
kubectl logs -n airbyte -l app=airbyte-server --tail=100
```

---

## Best Practices for AI Assistants

### When Helping with Deployment Issues:
1. Always check Airbyte version (2.0.1 is current)
2. Verify correct API endpoints (`/api/public/v1` for 2.0+)
3. Confirm health check path (`/v1/health`, NOT `/api/v1/health`)
4. Check Workload Identity is properly configured
5. Verify service account bindings (KSA ↔ GSA)

### When Helping with Backup/Restore:
1. Ensure API token is available
2. Verify Airbyte 2.0+ is being used
3. Check `jq` and `curl` are installed
4. Confirm server is accessible
5. Use v2 scripts (not v1)

### When Helping with Local Development:
1. **DO NOT** suggest using docker-compose.yml (it doesn't work)
2. **ALWAYS** recommend `abctl` for local testing
3. Explain that Docker images are not publicly available
4. Reference LOCAL_DEVELOPMENT.md for instructions

### When Modifying Configuration:
1. Check configmap.yaml for application settings
2. Check secrets.yaml for credentials
3. Update health check endpoints if changing version
4. Verify API compatibility when upgrading
5. Update AIRBYTE_VERSION in configmap when upgrading

### When Adding New Features:
1. Follow existing naming conventions (app=airbyte-*)
2. Add appropriate resource limits
3. Include health checks for new deployments
4. Add to PodDisruptionBudget if critical
5. Document in RUNBOOK.md or TROUBLESHOOTING.md

### Git Branch Strategy:
- Development branch pattern: `claude/airbyte-gke-workload-identity-<session-id>`
- All development must be on the designated branch
- Always push to the correct branch (403 error if wrong branch pattern)
- Use `git push -u origin <branch-name>` for first push

---

## Resource References

### Documentation Files (Priority Order)
1. **ARCHITECTURE.md** - System design and components
2. **RUNBOOK.md** - Operations procedures and daily tasks
3. **TROUBLESHOOTING.md** - Common issues and solutions
4. **LOCAL_DEVELOPMENT.md** - Local testing guide (abctl)
5. **V2_MIGRATION_GUIDE.md** - Backup/restore guide for v2 API
6. **API_COMPATIBILITY_WARNING.md** - API version compatibility notes

### External Resources
- Airbyte 2.0 Release Notes: https://docs.airbyte.com/release_notes/v-2.0
- Airbyte Documentation: https://docs.airbyte.com/
- abctl Documentation: https://docs.airbyte.com/platform/deploying-airbyte/abctl
- GKE Workload Identity: https://cloud.google.com/kubernetes-engine/docs/how-to/workload-identity

### Key Commands Reference

**Cluster Management:**
```bash
gcloud container clusters get-credentials airbyte-cluster --zone=us-central1-a
kubectl config use-context gke_PROJECT_ID_us-central1-a_airbyte-cluster
```

**Pod Management:**
```bash
kubectl get pods -n airbyte
kubectl logs -n airbyte deployment/airbyte-server
kubectl describe pod -n airbyte <pod-name>
kubectl exec -it -n airbyte <pod-name> -- bash
```

**Service Management:**
```bash
kubectl get svc -n airbyte
kubectl port-forward -n airbyte svc/airbyte-webapp-svc 8000:8000
```

**Resource Management:**
```bash
kubectl get all -n airbyte
kubectl top pods -n airbyte
kubectl describe resourcequota -n airbyte
```

---

## Version History & Migration Notes

### Airbyte 2.0.1 (Current)
- Released: October 14, 2025
- API: `/api/public/v1` (Public API)
- Health: `/v1/health`
- Authentication: Bearer token for API
- Breaking changes: API authentication required

### Previous Versions (Pre-2.0)
- API: `/api/v1` (deprecated)
- Health: `/api/v1/health` (no longer valid)
- Authentication: Basic auth worked on API (no longer supported)

### Migration from Pre-2.0 to 2.0+:
1. Update all manifests to version 2.0.1
2. Update health check endpoints to `/v1/health`
3. Generate API tokens for backup/restore
4. Test API compatibility with test-api-compatibility.sh
5. Update backup scripts to v2 (Public API)

---

## Contact & Support

For issues specific to this deployment:
1. Check TROUBLESHOOTING.md
2. Review RUNBOOK.md for operations procedures
3. Check logs: `kubectl logs -n airbyte deployment/airbyte-server`
4. Run health check: `./scripts/health-check.sh`

For Airbyte-specific issues:
- Documentation: https://docs.airbyte.com/
- Community Slack: https://slack.airbyte.io/
- GitHub Issues: https://github.com/airbytehq/airbyte/issues

---

## AI Assistant Quick Reference

**When user asks about:**
- "Deploy Airbyte" → Point to Quick Start in README.md
- "Local testing" → Recommend `abctl`, NOT docker-compose (see LOCAL_DEVELOPMENT.md)
- "Backup" → Use backup-airbyte-v2.sh, requires API token
- "API not working" → Check version (2.0+ requires `/api/public/v1` and Bearer token)
- "Health check fails" → Verify using `/v1/health` (not `/api/v1/health`)
- "Docker Compose not working" → Explain it's non-functional, suggest `abctl`
- "Workload Identity" → Check KSA ↔ GSA binding
- "Pods not starting" → Check logs, resources, PVC, secrets
- "Scaling" → Scale worker deployment, check resource quota
- "External database" → See k8s/airbyte/optional/EXTERNAL_DATABASE.md

**Always verify:**
- Correct Airbyte version (2.0.1 is current)
- Correct API paths (`/api/public/v1`, `/v1/health`)
- API token for authentication (not basic auth for API)
- `abctl` for local development (not docker-compose)

---

**Last Updated:** 2025-11-10
**Project Version:** Airbyte 2.0.1 on GKE
**Maintained by:** Automated deployment using Kubernetes and Bash scripts
