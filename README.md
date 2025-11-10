# Airbyte on GKE with Workload Identity

Production-ready deployment configuration for Airbyte 2.0.1 on Google Kubernetes Engine (GKE) with secure authentication, high availability, and automated operations.

## Overview

This repository provides a complete, production-ready setup for deploying Airbyte 2.0.1 on Google Kubernetes Engine (GKE) with:

- **Workload Identity**: Secure keyless authentication to GCP services
- **High Availability**: PodDisruptionBudgets, ResourceQuota, and proper resource limits
- **Internal Services**: ClusterIP services (no public exposure)
- **Automated Backups**: Backup/restore scripts using Airbyte Public API
- **Monitoring**: Health checks and comprehensive logging

## Quick Start

### Prerequisites

- Google Cloud Project with billing enabled
- `gcloud` CLI installed and configured
- `kubectl` installed
- Bash shell (Linux/macOS)

### 1. Set Environment Variables

```bash
export PROJECT_ID="your-gcp-project-id"
export CLUSTER_NAME="airbyte-cluster"
export ZONE="us-central1-a"
```

### 2. Create GKE Cluster

```bash
./scripts/create-cluster.sh
```

This script will:
- Create a GKE cluster with Workload Identity enabled
- Create and configure Google Service Account
- Bind Kubernetes Service Account to Google Service Account
- Get cluster credentials

### 3. Deploy Airbyte

```bash
# Apply Kubernetes manifests in order
kubectl apply -f k8s/namespace.yaml
kubectl apply -f k8s/workload-identity.yaml
kubectl apply -f k8s/secrets.yaml
kubectl apply -f k8s/resource-quota.yaml

# Deploy PostgreSQL (optional - use external database for production)
kubectl apply -f k8s/airbyte/optional/postgres.yaml

# Deploy Airbyte components
kubectl apply -f k8s/airbyte/
```

### 4. Wait for Pods to be Ready

```bash
kubectl get pods -n airbyte -w
```

Wait until all pods show `Running` status with `READY 1/1` or `2/2`.

### 5. Access Airbyte UI

```bash
kubectl port-forward -n airbyte svc/airbyte-webapp-svc 8000:8000
```

Open http://localhost:8000 in your browser.

**Default credentials:**
- Username: `airbyte`
- Password: `password`

⚠️ **Change these credentials in `k8s/secrets.yaml` before deploying to production!**

## Architecture

See [ARCHITECTURE.md](ARCHITECTURE.md) for detailed architecture documentation.

**Key Components:**
- **Airbyte Server**: API and orchestration (Port 8001)
- **Airbyte Worker**: Executes sync jobs
- **Airbyte Webapp**: User interface (Port 8000)
- **PostgreSQL**: Metadata storage (optional - can use Cloud SQL)
- **Minio**: Object storage (optional - can use GCS)

## Configuration

### Using External Database (Recommended for Production)

See [k8s/airbyte/optional/EXTERNAL_DATABASE.md](k8s/airbyte/optional/EXTERNAL_DATABASE.md) for instructions on using Cloud SQL or external PostgreSQL.

### Customizing Resources

Edit resource limits in deployment manifests:
- `k8s/airbyte/server.yaml`
- `k8s/airbyte/worker.yaml`
- `k8s/airbyte/webapp.yaml`

### Scaling Workers

```bash
kubectl scale deployment airbyte-worker -n airbyte --replicas=3
```

## Backup and Restore

### Generate API Token

1. Access Airbyte UI
2. Go to Settings → Account → Applications
3. Click "New Application"
4. Copy the generated token

### Backup

```bash
export AIRBYTE_API_TOKEN='your-token-here'
./scripts/backup-airbyte-v2.sh
```

Backups are saved to `backups/airbyte_backup_v2_TIMESTAMP.tar.gz`

### Restore

```bash
export AIRBYTE_API_TOKEN='your-token-here'
./scripts/restore-airbyte-v2.sh backups/airbyte_backup_v2_20240101_120000.tar.gz
```

See [scripts/V2_MIGRATION_GUIDE.md](scripts/V2_MIGRATION_GUIDE.md) for detailed backup/restore documentation.

## Monitoring and Health Checks

### Run Comprehensive Health Check

```bash
./scripts/health-check.sh
```

### Check Specific Component

```bash
# Check pod status
kubectl get pods -n airbyte

# Check logs
kubectl logs -n airbyte deployment/airbyte-server
kubectl logs -n airbyte deployment/airbyte-worker

# Check API health
kubectl port-forward -n airbyte svc/airbyte-server-svc 8001:8001
curl http://localhost:8001/v1/health
```

## Local Development

⚠️ **Docker Compose is NOT functional** (deprecated by Airbyte in August 2024)

For local testing, use `abctl` (Airbyte's official CLI):

```bash
# Install abctl
curl -LsfS https://get.airbyte.com | bash -

# Start Airbyte locally
abctl local install

# Get credentials
abctl local credentials
```

See [LOCAL_DEVELOPMENT.md](LOCAL_DEVELOPMENT.md) for detailed instructions.

## Troubleshooting

See [TROUBLESHOOTING.md](TROUBLESHOOTING.md) for common issues and solutions.

**Quick Checks:**

1. **Pods not starting?**
   ```bash
   kubectl describe pod -n airbyte <pod-name>
   kubectl logs -n airbyte <pod-name>
   ```

2. **Health check fails?**
   - Ensure using `/v1/health` endpoint (NOT `/api/v1/health`)
   - For Airbyte 2.0+, use `/api/public/v1` for API calls

3. **API authentication fails?**
   - Use Bearer token for API (not basic auth)
   - Basic auth is only for UI access

## Operations

See [RUNBOOK.md](RUNBOOK.md) for detailed operations procedures including:
- Daily operations
- Scaling procedures
- Upgrade procedures
- Disaster recovery
- Security best practices

## Cleanup

### Remove Airbyte (Keep Cluster)

```bash
kubectl delete namespace airbyte
```

### Remove Everything

```bash
./scripts/cleanup.sh
gcloud container clusters delete $CLUSTER_NAME --zone=$ZONE
```

## Documentation

- **[ARCHITECTURE.md](ARCHITECTURE.md)** - System architecture and component details
- **[RUNBOOK.md](RUNBOOK.md)** - Operations procedures and daily tasks
- **[TROUBLESHOOTING.md](TROUBLESHOOTING.md)** - Common issues and solutions
- **[LOCAL_DEVELOPMENT.md](LOCAL_DEVELOPMENT.md)** - Local testing guide
- **[CLAUDE.md](CLAUDE.md)** - AI assistant context and guidelines

## Version Information

- **Airbyte Version**: 2.0.1 (October 2025)
- **Kubernetes**: 1.27+ recommended
- **GKE**: Standard or Autopilot mode
- **API**: Public API `/api/public/v1` (Bearer token authentication)

## Important Notes

### Airbyte 2.0+ Changes

- Health endpoint: `/v1/health` (NOT `/api/v1/health`)
- API endpoint: `/api/public/v1/*` (requires Bearer token)
- Old `/api/v1` endpoint is DEPRECATED
- Basic auth only works for UI access (not API)

### Security

- Uses Workload Identity (no service account keys)
- ClusterIP services (internal only)
- Basic auth for UI (change defaults in `k8s/secrets.yaml`)
- API tokens required for backup/restore

### High Availability

- PodDisruptionBudgets ensure minimum replicas
- ResourceQuota prevents resource exhaustion
- Health checks and readiness probes configured
- Can scale workers horizontally

## Contributing

When modifying this project:

1. Follow existing naming conventions (`app=airbyte-*`)
2. Add appropriate resource limits
3. Include health checks for new deployments
4. Update relevant documentation
5. Test changes in development environment first

## Support

For issues specific to this deployment:
1. Check [TROUBLESHOOTING.md](TROUBLESHOOTING.md)
2. Review [RUNBOOK.md](RUNBOOK.md)
3. Check logs: `kubectl logs -n airbyte deployment/airbyte-server`

For Airbyte-specific issues:
- Documentation: https://docs.airbyte.com/
- Community Slack: https://slack.airbyte.io/
- GitHub: https://github.com/airbytehq/airbyte

## License

This deployment configuration is provided as-is for use with Airbyte.

Airbyte is licensed under the Elastic License 2.0 (ELv2). See [Airbyte License](https://github.com/airbytehq/airbyte/blob/master/LICENSE) for details.

---

**Last Updated**: 2025-11-10
**Airbyte Version**: 2.0.1
**Maintained By**: DevOps Team
