# Operations Runbook

This runbook provides step-by-step procedures for common operational tasks when managing Airbyte on GKE.

## Table of Contents

1. [Daily Operations](#daily-operations)
2. [Deployment Procedures](#deployment-procedures)
3. [Scaling Procedures](#scaling-procedures)
4. [Backup and Restore](#backup-and-restore)
5. [Upgrade Procedures](#upgrade-procedures)
6. [Disaster Recovery](#disaster-recovery)
7. [Security Operations](#security-operations)
8. [Monitoring and Alerting](#monitoring-and-alerting)
9. [Performance Tuning](#performance-tuning)
10. [Maintenance Windows](#maintenance-windows)

---

## Daily Operations

### Morning Health Check

**Frequency**: Every morning

**Steps**:

```bash
# 1. Run automated health check
./scripts/health-check.sh

# 2. Check pod status
kubectl get pods -n airbyte

# 3. Check resource usage
kubectl top pods -n airbyte
kubectl top nodes

# 4. Check recent events
kubectl get events -n airbyte --sort-by='.lastTimestamp' | tail -20

# 5. Check for failed syncs (from Airbyte UI)
# - Open http://localhost:8000
# - Review Connections page
# - Check for failed syncs
```

**Expected Results**:
- All pods in `Running` state with `READY 1/1`
- Health check script exits with code 0
- Resource usage within normal limits (< 80%)
- No critical events

**If Issues Found**:
- See [TROUBLESHOOTING.md](TROUBLESHOOTING.md)
- Escalate if critical

### Log Review

**Frequency**: Daily

**Steps**:

```bash
# Check for errors in last 24 hours
kubectl logs -n airbyte deployment/airbyte-server --since=24h | grep -i error
kubectl logs -n airbyte deployment/airbyte-worker --since=24h | grep -i error

# Check for warnings
kubectl logs -n airbyte deployment/airbyte-server --since=24h | grep -i warn

# Review recent events
kubectl get events -n airbyte --sort-by='.lastTimestamp' | grep -i "error\|warning"
```

**Action Items**:
- Investigate any ERROR logs
- Document recurring warnings
- Create tickets for non-urgent issues

### Backup Verification

**Frequency**: Daily (after automated backup runs)

**Steps**:

```bash
# 1. Check backup CronJob status
kubectl get cronjobs -n airbyte
kubectl get jobs -n airbyte

# 2. Verify backup file exists
ls -lh backups/ | tail -5

# 3. Verify backup is recent (< 24 hours old)
find backups/ -name "airbyte_backup_v2_*.tar.gz" -mtime -1

# 4. Check backup size (should be > 1KB)
du -sh backups/airbyte_backup_v2_*.tar.gz | tail -1
```

**If Backup Failed**:
```bash
# Check CronJob logs
kubectl logs -n airbyte job/<backup-job-name>

# Run manual backup
export AIRBYTE_API_TOKEN='your-token'
./scripts/backup-airbyte-v2.sh
```

---

## Deployment Procedures

### Initial Deployment

**Prerequisites**:
- GCP project with billing enabled
- `gcloud` CLI configured
- `kubectl` installed
- Environment variables set

**Steps**:

```bash
# 1. Set environment variables
export PROJECT_ID="your-gcp-project-id"
export CLUSTER_NAME="airbyte-cluster"
export ZONE="us-central1-a"

# 2. Create GKE cluster
./scripts/create-cluster.sh

# Confirm when prompted

# 3. Verify cluster access
kubectl cluster-info
kubectl get nodes

# 4. Apply Kubernetes manifests
kubectl apply -f k8s/namespace.yaml
kubectl apply -f k8s/workload-identity.yaml

# 5. Update secrets with production credentials
# Edit k8s/secrets.yaml first, then:
kubectl apply -f k8s/secrets.yaml

# 6. Apply resource controls
kubectl apply -f k8s/resource-quota.yaml

# 7. Deploy database (or configure external DB)
kubectl apply -f k8s/airbyte/optional/postgres.yaml

# Wait for database to be ready
kubectl wait --for=condition=ready pod -l app=airbyte-db -n airbyte --timeout=300s

# 8. Deploy Airbyte components
kubectl apply -f k8s/airbyte/

# 9. Wait for all pods to be ready
kubectl get pods -n airbyte -w

# 10. Verify deployment
./scripts/health-check.sh

# 11. Access UI and complete setup
kubectl port-forward -n airbyte svc/airbyte-webapp-svc 8000:8000
# Open http://localhost:8000
```

**Verification**:
- All pods running and ready
- Health check passes
- Can access UI
- Can create test connection

### Updating Configuration

**To update ConfigMap**:

```bash
# 1. Edit configuration
vi k8s/airbyte/configmap.yaml

# 2. Apply changes
kubectl apply -f k8s/airbyte/configmap.yaml

# 3. Restart affected deployments
kubectl rollout restart deployment/airbyte-server -n airbyte
kubectl rollout restart deployment/airbyte-worker -n airbyte
kubectl rollout restart deployment/airbyte-webapp -n airbyte

# 4. Monitor rollout
kubectl rollout status deployment/airbyte-server -n airbyte
kubectl rollout status deployment/airbyte-worker -n airbyte
kubectl rollout status deployment/airbyte-webapp -n airbyte

# 5. Verify
./scripts/health-check.sh
```

**To update Secrets**:

```bash
# 1. Edit secrets
vi k8s/secrets.yaml

# 2. Delete old secret
kubectl delete secret airbyte-secrets -n airbyte

# 3. Apply new secret
kubectl apply -f k8s/secrets.yaml

# 4. Restart affected deployments
kubectl rollout restart deployment -n airbyte

# 5. Verify
kubectl get pods -n airbyte
```

---

## Scaling Procedures

### Scaling Workers Horizontally

**When to Scale**:
- Many syncs queued
- Long wait times for syncs to start
- High CPU/memory on single worker
- Increased workload requirements

**Steps**:

```bash
# 1. Check current worker count
kubectl get deployment airbyte-worker -n airbyte

# 2. Check current resource usage
kubectl top pods -n airbyte -l app=airbyte-worker

# 3. Scale workers
kubectl scale deployment airbyte-worker -n airbyte --replicas=3

# 4. Verify scaling
kubectl get pods -n airbyte -l app=airbyte-worker -w

# 5. Monitor resource usage
kubectl top pods -n airbyte -l app=airbyte-worker

# 6. Check ResourceQuota not exceeded
kubectl describe resourcequota -n airbyte
```

**Scaling Guidelines**:
- Start with 1 worker for light workloads
- Scale to 3-5 workers for medium workloads
- Scale to 5+ workers for heavy workloads
- Each worker should have 2 CPU, 4Gi memory
- Monitor and adjust based on actual usage

### Scaling Workers Vertically

**When to Scale**:
- Workers hitting memory limits
- CPU throttling observed
- Large data volumes per sync

**Steps**:

```bash
# 1. Edit deployment manifest
vi k8s/airbyte/worker.yaml

# Update resources:
# resources:
#   requests:
#     cpu: 2
#     memory: 8Gi
#   limits:
#     cpu: 4
#     memory: 16Gi

# 2. Apply changes
kubectl apply -f k8s/airbyte/worker.yaml

# 3. Monitor rollout
kubectl rollout status deployment/airbyte-worker -n airbyte

# 4. Verify new resources
kubectl describe pod -n airbyte -l app=airbyte-worker | grep -A 5 "Limits:"
```

### Scaling Database

**For Internal PostgreSQL**:

```bash
# 1. Edit StatefulSet
vi k8s/airbyte/optional/postgres.yaml

# Update resources

# 2. Apply changes
kubectl apply -f k8s/airbyte/optional/postgres.yaml

# 3. Delete pod to restart with new resources
kubectl delete pod airbyte-db-0 -n airbyte

# 4. Wait for pod to be ready
kubectl wait --for=condition=ready pod airbyte-db-0 -n airbyte --timeout=300s
```

**For Production**: Migrate to Cloud SQL (see EXTERNAL_DATABASE.md)

### Scaling Cluster Nodes

**Manual Node Scaling**:

```bash
# Check current node count
kubectl get nodes

# Resize node pool
gcloud container clusters resize $CLUSTER_NAME \
  --num-nodes=5 \
  --zone=$ZONE

# Verify
kubectl get nodes
```

**Enable Cluster Autoscaler**:

```bash
gcloud container clusters update $CLUSTER_NAME \
  --enable-autoscaling \
  --min-nodes=3 \
  --max-nodes=10 \
  --zone=$ZONE
```

---

## Backup and Restore

### Creating Manual Backup

**Prerequisites**:
- API token generated
- `jq` and `curl` installed
- Server accessible

**Steps**:

```bash
# 1. Generate API token (if not already done)
# - Open Airbyte UI: Settings → Account → Applications
# - Create new application
# - Copy token

# 2. Export token
export AIRBYTE_API_TOKEN='your-token-here'

# 3. Ensure server is accessible
kubectl port-forward -n airbyte svc/airbyte-server-svc 8001:8001 &

# 4. Run backup
./scripts/backup-airbyte-v2.sh

# 5. Verify backup created
ls -lh backups/ | tail -1

# 6. Test backup integrity
tar -tzf backups/airbyte_backup_v2_*.tar.gz | head
```

**Backup Storage**:

```bash
# Upload to Google Cloud Storage
gsutil cp backups/airbyte_backup_v2_*.tar.gz gs://your-backup-bucket/airbyte/

# Or sync entire backup directory
gsutil rsync -r backups/ gs://your-backup-bucket/airbyte/
```

### Restoring from Backup

**Prerequisites**:
- Backup file available
- API token
- Target Airbyte instance running

**Steps**:

```bash
# 1. Download backup if needed
gsutil cp gs://your-backup-bucket/airbyte/airbyte_backup_v2_20240101_120000.tar.gz backups/

# 2. Export API token
export AIRBYTE_API_TOKEN='your-token-here'

# 3. Ensure server is accessible
kubectl port-forward -n airbyte svc/airbyte-server-svc 8001:8001 &

# 4. Run restore
./scripts/restore-airbyte-v2.sh backups/airbyte_backup_v2_20240101_120000.tar.gz

# 5. Verify restoration
# - Open Airbyte UI
# - Check workspaces exist
# - Check sources and destinations
# - Check connections
```

**Important Notes**:
- Restore creates NEW UUIDs for entities
- Connections will need to be re-enabled
- OAuth tokens may need to be refreshed
- Test connections after restore

### Automated Backup Setup

**Deploy Backup CronJob**:

```bash
# 1. Create API token secret
kubectl create secret generic airbyte-api-token \
  -n airbyte \
  --from-literal=token='your-token-here'

# 2. Deploy CronJob
kubectl apply -f k8s/airbyte/optional/backup-cronjob-v2.yaml

# 3. Verify CronJob created
kubectl get cronjobs -n airbyte

# 4. Test CronJob manually
kubectl create job --from=cronjob/airbyte-backup-v2 test-backup -n airbyte

# 5. Check job status
kubectl get jobs -n airbyte
kubectl logs -n airbyte job/test-backup
```

**Backup Schedule**:
- Default: Daily at 2 AM UTC
- Modify schedule in CronJob spec: `schedule: "0 2 * * *"`

---

## Upgrade Procedures

### Upgrade Airbyte Version

**Prerequisites**:
- Current backup completed
- Maintenance window scheduled
- Release notes reviewed

**Steps**:

```bash
# 1. Create backup
export AIRBYTE_API_TOKEN='your-token'
./scripts/backup-airbyte-v2.sh

# 2. Verify backup
ls -lh backups/ | tail -1

# 3. Review release notes
# Check: https://docs.airbyte.com/release_notes/

# 4. Update image versions in manifests
# Edit each deployment file:
# - k8s/airbyte/server.yaml
# - k8s/airbyte/worker.yaml
# - k8s/airbyte/webapp.yaml
# Change: image: airbyte/server:2.0.1 → image: airbyte/server:2.1.0

# 5. Update ConfigMap version
# Edit k8s/airbyte/configmap.yaml
# Change: AIRBYTE_VERSION: "2.0.1" → "2.1.0"

# 6. Apply changes
kubectl apply -f k8s/airbyte/configmap.yaml
kubectl apply -f k8s/airbyte/

# 7. Monitor rollout
kubectl rollout status deployment/airbyte-server -n airbyte
kubectl rollout status deployment/airbyte-worker -n airbyte
kubectl rollout status deployment/airbyte-webapp -n airbyte

# 8. Verify upgrade
kubectl get pods -n airbyte
kubectl describe pod -n airbyte -l app=airbyte-server | grep Image:

# 9. Run health check
./scripts/health-check.sh

# 10. Verify in UI
# - Access Airbyte UI
# - Check version in Settings
# - Test a sync
```

**Rollback If Needed**:

```bash
# Rollback deployments
kubectl rollout undo deployment/airbyte-server -n airbyte
kubectl rollout undo deployment/airbyte-worker -n airbyte
kubectl rollout undo deployment/airbyte-webapp -n airbyte

# Verify rollback
kubectl rollout status deployment/airbyte-server -n airbyte
./scripts/health-check.sh
```

### Upgrade Kubernetes Version

**Steps**:

```bash
# 1. Check available versions
gcloud container get-server-config --zone=$ZONE

# 2. Upgrade control plane
gcloud container clusters upgrade $CLUSTER_NAME \
  --master \
  --cluster-version=1.28 \
  --zone=$ZONE

# 3. Upgrade node pools
gcloud container clusters upgrade $CLUSTER_NAME \
  --node-pool=default-pool \
  --cluster-version=1.28 \
  --zone=$ZONE

# 4. Verify upgrade
kubectl version
kubectl get nodes
```

---

## Disaster Recovery

### Complete Cluster Loss

**Recovery Steps**:

```bash
# 1. Create new cluster
export PROJECT_ID="your-project"
export CLUSTER_NAME="airbyte-cluster-new"
export ZONE="us-central1-a"
./scripts/create-cluster.sh

# 2. Deploy Airbyte
kubectl apply -f k8s/namespace.yaml
kubectl apply -f k8s/workload-identity.yaml
kubectl apply -f k8s/secrets.yaml
kubectl apply -f k8s/resource-quota.yaml
kubectl apply -f k8s/airbyte/optional/postgres.yaml

# Wait for database
kubectl wait --for=condition=ready pod -l app=airbyte-db -n airbyte --timeout=300s

kubectl apply -f k8s/airbyte/

# Wait for all pods
kubectl get pods -n airbyte -w

# 3. Restore from backup
export AIRBYTE_API_TOKEN='your-token'
./scripts/restore-airbyte-v2.sh backups/latest-backup.tar.gz

# 4. Verify restoration
./scripts/health-check.sh
```

**RTO**: ~60 minutes
**RPO**: Last backup (24 hours if daily backups)

### Database Corruption

**Recovery Steps**:

```bash
# 1. Stop Airbyte components
kubectl scale deployment/airbyte-server -n airbyte --replicas=0
kubectl scale deployment/airbyte-worker -n airbyte --replicas=0

# 2. Backup current PVC (if possible)
kubectl get pvc data-airbyte-db-0 -n airbyte -o yaml > pvc-backup.yaml

# 3. Delete corrupted database
kubectl delete statefulset airbyte-db -n airbyte
kubectl delete pvc data-airbyte-db-0 -n airbyte

# 4. Recreate database
kubectl apply -f k8s/airbyte/optional/postgres.yaml

# Wait for database
kubectl wait --for=condition=ready pod airbyte-db-0 -n airbyte --timeout=300s

# 5. Scale up Airbyte components
kubectl scale deployment/airbyte-server -n airbyte --replicas=1
kubectl scale deployment/airbyte-worker -n airbyte --replicas=1

# Wait for pods
kubectl wait --for=condition=ready pod -l app=airbyte-server -n airbyte --timeout=300s

# 6. Restore from API backup
export AIRBYTE_API_TOKEN='your-token'
./scripts/restore-airbyte-v2.sh backups/latest-backup.tar.gz

# 7. Verify
./scripts/health-check.sh
```

---

## Security Operations

### Rotating Credentials

**Rotate Database Password**:

```bash
# 1. Update password in PostgreSQL
kubectl exec -it -n airbyte statefulset/airbyte-db -- psql -U airbyte -c "ALTER USER airbyte WITH PASSWORD 'new-password';"

# 2. Update secret
# Edit k8s/secrets.yaml with new password
kubectl delete secret airbyte-secrets -n airbyte
kubectl apply -f k8s/secrets.yaml

# 3. Restart components
kubectl rollout restart deployment -n airbyte

# 4. Verify
./scripts/health-check.sh
```

**Rotate Basic Auth Credentials**:

```bash
# 1. Update credentials in k8s/secrets.yaml

# 2. Apply changes
kubectl delete secret airbyte-secrets -n airbyte
kubectl apply -f k8s/secrets.yaml

# 3. Restart webapp
kubectl rollout restart deployment/airbyte-webapp -n airbyte

# 4. Test login with new credentials
```

**Rotate API Tokens**:

```bash
# 1. Generate new token in UI (Settings → Account → Applications)

# 2. Update backup scripts
export AIRBYTE_API_TOKEN='new-token'

# 3. Update CronJob secret
kubectl delete secret airbyte-api-token -n airbyte
kubectl create secret generic airbyte-api-token \
  -n airbyte \
  --from-literal=token='new-token'

# 4. Delete old token in UI
```

### Security Audit

**Monthly Security Checklist**:

```bash
# 1. Check for outdated images
kubectl get pods -n airbyte -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.containers[*].image}{"\n"}{end}'

# 2. Review RBAC permissions
kubectl get rolebindings -n airbyte
kubectl get clusterrolebindings | grep airbyte

# 3. Check secrets are not exposed
kubectl get secrets -n airbyte
kubectl describe configmap -n airbyte | grep -i password

# 4. Verify Workload Identity binding
gcloud iam service-accounts get-iam-policy airbyte-gsa@$PROJECT_ID.iam.gserviceaccount.com

# 5. Review network policies (if configured)
kubectl get networkpolicies -n airbyte

# 6. Check for security updates
# Review Airbyte release notes
# Check for CVEs
```

---

## Monitoring and Alerting

### Setting Up Monitoring

**Google Cloud Monitoring**:

```bash
# Enable monitoring for GKE cluster
gcloud container clusters update $CLUSTER_NAME \
  --enable-cloud-monitoring \
  --zone=$ZONE
```

**Key Metrics to Monitor**:
- Pod CPU and memory usage
- Pod restart count
- API response time
- Sync job success rate
- Database connections
- Storage usage

### Creating Alerts

**Example Alert Policies**:

1. **Pod Not Ready**:
   - Metric: `kubernetes.io/container/ready`
   - Condition: < 1 for > 5 minutes
   - Action: Send notification

2. **High Memory Usage**:
   - Metric: `kubernetes.io/container/memory/usage`
   - Condition: > 90% for > 10 minutes
   - Action: Send notification

3. **High CPU Usage**:
   - Metric: `kubernetes.io/container/cpu/usage_time`
   - Condition: > 90% for > 10 minutes
   - Action: Send notification

4. **Sync Failures**:
   - Monitor: Airbyte UI or logs
   - Condition: Multiple failures
   - Action: Investigate

---

## Performance Tuning

### Database Performance

**For PostgreSQL**:

```bash
# Connect to database
kubectl exec -it -n airbyte statefulset/airbyte-db -- psql -U airbyte

# Check slow queries
SELECT pid, age(clock_timestamp(), query_start), usename, query
FROM pg_stat_activity
WHERE query != '<IDLE>' AND query NOT ILIKE '%pg_stat_activity%'
ORDER BY query_start desc;

# Check database size
SELECT pg_size_pretty(pg_database_size('airbyte'));

# Vacuum database
VACUUM ANALYZE;
```

**Tuning Parameters**:
```yaml
# Edit postgres.yaml
env:
- name: POSTGRES_SHARED_BUFFERS
  value: "256MB"
- name: POSTGRES_MAX_CONNECTIONS
  value: "200"
```

### Worker Performance

**Tuning Configuration**:

```yaml
# Edit configmap.yaml
MAX_SYNC_WORKERS: "10"      # Concurrent syncs per worker
MAX_SPEC_WORKERS: "5"        # Concurrent spec operations
MAX_CHECK_WORKERS: "5"       # Concurrent connection checks
SYNC_JOB_MAX_TIMEOUT_DAYS: "3"  # Max sync duration
```

**Resource Allocation**:
- Monitor actual usage with `kubectl top pods`
- Adjust based on workload
- Consider horizontal scaling for high loads

---

## Maintenance Windows

### Planned Maintenance Template

**Before Maintenance**:
```bash
# 1. Announce maintenance window
# 2. Create backup
export AIRBYTE_API_TOKEN='your-token'
./scripts/backup-airbyte-v2.sh

# 3. Upload backup to GCS
gsutil cp backups/airbyte_backup_v2_*.tar.gz gs://backup-bucket/

# 4. Document current state
kubectl get all -n airbyte > pre-maintenance-state.txt
```

**During Maintenance**:
```bash
# Perform maintenance tasks
# (upgrades, scaling, configuration changes, etc.)
```

**After Maintenance**:
```bash
# 1. Verify system health
./scripts/health-check.sh

# 2. Test critical functions
# - Login to UI
# - Run test sync
# - Verify API access

# 3. Monitor for 30 minutes
kubectl get events -n airbyte --sort-by='.lastTimestamp' --watch

# 4. Announce maintenance complete
```

---

**Document Version**: 1.0
**Last Updated**: 2025-11-10
**Airbyte Version**: 2.0.1
