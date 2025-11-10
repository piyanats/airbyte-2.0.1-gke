# Troubleshooting Guide

This document provides solutions to common issues encountered when deploying and operating Airbyte on GKE.

## Table of Contents

1. [Pod Issues](#pod-issues)
2. [Networking Issues](#networking-issues)
3. [API and Health Check Issues](#api-and-health-check-issues)
4. [Database Issues](#database-issues)
5. [Storage Issues](#storage-issues)
6. [Authentication Issues](#authentication-issues)
7. [Backup and Restore Issues](#backup-and-restore-issues)
8. [Performance Issues](#performance-issues)
9. [Workload Identity Issues](#workload-identity-issues)
10. [Local Development Issues](#local-development-issues)

---

## Pod Issues

### Issue: Pods Stuck in Pending State

**Symptoms:**
```bash
$ kubectl get pods -n airbyte
NAME                              READY   STATUS    RESTARTS   AGE
airbyte-server-xxxxx             0/1     Pending   0          5m
```

**Possible Causes & Solutions:**

**1. Insufficient Resources**
```bash
# Check node resources
kubectl describe nodes

# Check events
kubectl describe pod -n airbyte <pod-name>
```

**Solution:**
- Scale up cluster nodes
- Reduce resource requests in deployment
- Check ResourceQuota limits

**2. PVC Not Bound**
```bash
# Check PVC status
kubectl get pvc -n airbyte
```

**Solution:**
```bash
# Check if StorageClass exists
kubectl get storageclass

# Describe PVC for issues
kubectl describe pvc -n airbyte <pvc-name>
```

**3. Node Selector or Taints**
```bash
kubectl describe pod -n airbyte <pod-name> | grep -A 5 "Events:"
```

**Solution:**
- Remove node selectors if not needed
- Add tolerations for tainted nodes

### Issue: Pods CrashLoopBackOff

**Symptoms:**
```bash
$ kubectl get pods -n airbyte
NAME                              READY   STATUS             RESTARTS   AGE
airbyte-server-xxxxx             0/1     CrashLoopBackOff   5          10m
```

**Diagnosis:**
```bash
# Check logs
kubectl logs -n airbyte <pod-name>

# Check previous container logs
kubectl logs -n airbyte <pod-name> --previous

# Check events
kubectl describe pod -n airbyte <pod-name>
```

**Common Causes:**

**1. Database Connection Failed**
```
ERROR: Cannot connect to database
```

**Solution:**
```bash
# Verify database pod is running
kubectl get pods -n airbyte -l app=airbyte-db

# Check database credentials in secret
kubectl get secret airbyte-secrets -n airbyte -o yaml

# Test database connection
kubectl exec -it -n airbyte <server-pod> -- sh
nc -zv airbyte-db-svc 5432
```

**2. Missing Environment Variables**
```bash
# Check configmap
kubectl get configmap airbyte-env -n airbyte -o yaml

# Verify all required variables are set
```

**3. Wrong Image Version**
```bash
# Check image pull status
kubectl describe pod -n airbyte <pod-name> | grep Image
```

**Solution:**
- Verify image version in deployment manifest
- Check image pull secrets if using private registry

### Issue: Pods Running But Not Ready

**Symptoms:**
```bash
$ kubectl get pods -n airbyte
NAME                              READY   STATUS    RESTARTS   AGE
airbyte-server-xxxxx             0/1     Running   0          5m
```

**Diagnosis:**
```bash
# Check readiness probe
kubectl describe pod -n airbyte <pod-name> | grep -A 10 "Readiness:"

# Check logs
kubectl logs -n airbyte <pod-name>
```

**Solution:**

**1. Health Check Endpoint Wrong**
- For Airbyte 2.0+: Use `/v1/health` (NOT `/api/v1/health`)
- Update deployment manifest

**2. Increase Initial Delay**
```yaml
readinessProbe:
  httpGet:
    path: /v1/health
    port: 8001
  initialDelaySeconds: 60  # Increase this
  periodSeconds: 10
```

**3. Application Not Starting**
```bash
# Check application logs for errors
kubectl logs -n airbyte <pod-name> | tail -50
```

---

## Networking Issues

### Issue: Cannot Access Airbyte UI

**Symptoms:**
- Port-forward command hangs
- Connection refused on localhost:8000

**Diagnosis:**
```bash
# Check if webapp pod is running
kubectl get pods -n airbyte -l app=airbyte-webapp

# Check webapp service
kubectl get svc -n airbyte airbyte-webapp-svc

# Check service endpoints
kubectl get endpoints -n airbyte airbyte-webapp-svc
```

**Solutions:**

**1. Pod Not Ready**
```bash
# Wait for pod to be ready
kubectl wait --for=condition=ready pod -l app=airbyte-webapp -n airbyte --timeout=300s
```

**2. Service Selector Wrong**
```bash
# Verify service selector matches pod labels
kubectl get svc airbyte-webapp-svc -n airbyte -o yaml | grep -A 3 selector
kubectl get pods -n airbyte -l app=airbyte-webapp --show-labels
```

**3. Port-Forward Command**
```bash
# Correct command
kubectl port-forward -n airbyte svc/airbyte-webapp-svc 8000:8000

# If above fails, try pod directly
kubectl port-forward -n airbyte pod/<webapp-pod-name> 8000:8000
```

### Issue: Webapp Cannot Connect to Server

**Symptoms:**
- UI loads but shows "Cannot connect to server"
- API calls fail from UI

**Diagnosis:**
```bash
# Check server pod status
kubectl get pods -n airbyte -l app=airbyte-server

# Check internal DNS resolution
kubectl exec -it -n airbyte <webapp-pod> -- nslookup airbyte-server-svc

# Test connectivity
kubectl exec -it -n airbyte <webapp-pod> -- wget -O- http://airbyte-server-svc:8001/v1/health
```

**Solutions:**

**1. Server Not Running**
```bash
# Check server logs
kubectl logs -n airbyte deployment/airbyte-server --tail=50
```

**2. Wrong INTERNAL_API_HOST**
```bash
# Check configmap
kubectl get configmap airbyte-env -n airbyte -o yaml | grep INTERNAL_API_HOST

# Should be: airbyte-server-svc:8001
```

**3. Network Policy Blocking**
```bash
# Check for network policies
kubectl get networkpolicies -n airbyte

# Temporarily remove to test
kubectl delete networkpolicy <policy-name> -n airbyte
```

---

## API and Health Check Issues

### Issue: Health Check Returns 404

**Symptoms:**
```bash
$ curl http://localhost:8001/api/v1/health
404 Not Found
```

**Solution:**

For Airbyte 2.0+, use the correct health endpoint:
```bash
# Correct endpoint
curl http://localhost:8001/v1/health

# Should return:
{"available": true}
```

**Update Manifests:**
```yaml
livenessProbe:
  httpGet:
    path: /v1/health  # NOT /api/v1/health
    port: 8001
```

### Issue: API Returns 401 Unauthorized

**Symptoms:**
```bash
$ curl http://localhost:8001/api/public/v1/workspaces
401 Unauthorized
```

**Solution:**

Airbyte 2.0+ requires Bearer token authentication:

**1. Generate API Token:**
- Open Airbyte UI
- Go to Settings → Account → Applications
- Click "New Application"
- Copy the token

**2. Use Token in Requests:**
```bash
curl -H "Authorization: Bearer YOUR_TOKEN" \
  http://localhost:8001/api/public/v1/workspaces
```

**3. Update Backup Scripts:**
```bash
export AIRBYTE_API_TOKEN='your-token'
./scripts/backup-airbyte-v2.sh
```

### Issue: API Endpoint Not Found (404)

**Symptoms:**
```bash
$ curl http://localhost:8001/api/v1/workspaces
404 Not Found
```

**Solution:**

Airbyte 2.0+ uses new API endpoint:

**Old (Deprecated):**
```bash
/api/v1/*
```

**New (Correct):**
```bash
/api/public/v1/*
```

**Example:**
```bash
# Correct endpoint
curl -H "Authorization: Bearer YOUR_TOKEN" \
  http://localhost:8001/api/public/v1/workspaces
```

---

## Database Issues

### Issue: Database Connection Failed

**Symptoms:**
```
ERROR: Connection to database failed
ERROR: FATAL: password authentication failed for user "airbyte"
```

**Diagnosis:**
```bash
# Check database pod
kubectl get pods -n airbyte -l app=airbyte-db

# Check database logs
kubectl logs -n airbyte statefulset/airbyte-db

# Check secrets
kubectl get secret airbyte-secrets -n airbyte -o jsonpath='{.data.DATABASE_PASSWORD}' | base64 -d
```

**Solutions:**

**1. Database Not Ready**
```bash
# Wait for database to be ready
kubectl wait --for=condition=ready pod -l app=airbyte-db -n airbyte --timeout=300s
```

**2. Wrong Credentials**
```bash
# Verify credentials match in:
# - k8s/secrets.yaml
# - k8s/airbyte/configmap.yaml (DATABASE_HOST, DATABASE_DB)

# Update secret if needed
kubectl delete secret airbyte-secrets -n airbyte
kubectl apply -f k8s/secrets.yaml
kubectl rollout restart deployment/airbyte-server -n airbyte
```

**3. Test Connection Manually**
```bash
kubectl exec -it -n airbyte statefulset/airbyte-db -- psql -U airbyte -d airbyte -c "SELECT version();"
```

### Issue: Database PVC Not Bound

**Symptoms:**
```bash
$ kubectl get pvc -n airbyte
NAME                STATUS    VOLUME   CAPACITY   ACCESS MODES
data-airbyte-db-0   Pending
```

**Diagnosis:**
```bash
kubectl describe pvc data-airbyte-db-0 -n airbyte
```

**Solutions:**

**1. StorageClass Not Available**
```bash
# List available storage classes
kubectl get storageclass

# If none exist, create one or use default
kubectl patch storageclass standard -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
```

**2. Insufficient Storage**
- Check cluster has available storage
- Reduce PVC size request

**3. Regional PVC Issue (GKE)**
```bash
# Ensure nodes are in same zone as PVC
kubectl get nodes -o wide
kubectl get pvc data-airbyte-db-0 -n airbyte -o yaml
```

---

## Storage Issues

### Issue: Minio Pod Cannot Start

**Symptoms:**
```
ERROR: Cannot write to /data directory
```

**Diagnosis:**
```bash
# Check PVC
kubectl get pvc -n airbyte -l app=airbyte-minio

# Check pod
kubectl logs -n airbyte statefulset/airbyte-minio
```

**Solutions:**

**1. PVC Not Bound**
```bash
kubectl describe pvc -n airbyte data-airbyte-minio-0
```

**2. Permission Issues**
```bash
# Check fsGroup in pod spec
kubectl get statefulset airbyte-minio -n airbyte -o yaml | grep -A 5 securityContext
```

**3. Insufficient Storage**
```bash
# Check available storage
kubectl get pvc -n airbyte

# Increase PVC size (if supported)
kubectl edit pvc data-airbyte-minio-0 -n airbyte
```

### Issue: Out of Disk Space

**Symptoms:**
```
ERROR: No space left on device
```

**Solutions:**

**1. Clean Up Old Data**
```bash
# Connect to Minio
kubectl exec -it -n airbyte statefulset/airbyte-minio -- sh

# Clean up old logs
mc rm --recursive --force airbyte-minio/airbyte-dev-logs/
```

**2. Increase PVC Size**
```bash
# Edit PVC (if storage class supports expansion)
kubectl edit pvc data-airbyte-minio-0 -n airbyte

# Change:
spec:
  resources:
    requests:
      storage: 200Gi  # Increase this
```

**3. Use External Storage**
- Migrate to Google Cloud Storage
- See configuration in `k8s/airbyte/configmap.yaml`

---

## Authentication Issues

### Issue: Basic Auth Not Working for UI

**Symptoms:**
- Prompted for credentials
- Credentials rejected

**Solutions:**

**1. Check Credentials in Secret**
```bash
kubectl get secret airbyte-secrets -n airbyte -o jsonpath='{.data.BASIC_AUTH_USERNAME}' | base64 -d
kubectl get secret airbyte-secrets -n airbyte -o jsonpath='{.data.BASIC_AUTH_PASSWORD}' | base64 -d
```

**2. Verify Webapp Configuration**
```bash
kubectl get deployment airbyte-webapp -n airbyte -o yaml | grep -A 5 BASIC_AUTH
```

**3. Update Credentials**
```bash
# Edit k8s/secrets.yaml
# Then apply:
kubectl delete secret airbyte-secrets -n airbyte
kubectl apply -f k8s/secrets.yaml
kubectl rollout restart deployment/airbyte-webapp -n airbyte
```

### Issue: API Token Not Working

**Symptoms:**
```
401 Unauthorized when using API token
```

**Solutions:**

**1. Verify Token Format**
```bash
# Correct format
curl -H "Authorization: Bearer YOUR_TOKEN" http://...

# NOT "Basic" or without "Bearer"
```

**2. Regenerate Token**
- Go to Settings → Account → Applications
- Delete old application
- Create new application
- Copy new token

**3. Check Token Permissions**
- Ensure token has required permissions
- Some operations require workspace-specific tokens

---

## Backup and Restore Issues

### Issue: Backup Script Fails

**Symptoms:**
```bash
$ ./scripts/backup-airbyte-v2.sh
ERROR: AIRBYTE_API_TOKEN not set
```

**Solutions:**

**1. Set API Token**
```bash
export AIRBYTE_API_TOKEN='your-token-here'
./scripts/backup-airbyte-v2.sh
```

**2. Install Dependencies**
```bash
# Check if jq and curl are installed
which jq curl

# Install if missing (Ubuntu/Debian)
apt-get update && apt-get install -y jq curl

# Install if missing (macOS)
brew install jq
```

**3. Check Server Accessibility**
```bash
# Ensure port-forward is running
kubectl port-forward -n airbyte svc/airbyte-server-svc 8001:8001 &

# Test connectivity
curl http://localhost:8001/v1/health
```

### Issue: Restore Script Fails

**Symptoms:**
```
ERROR: Cannot create workspace
ERROR: Source already exists
```

**Solutions:**

**1. Clean Workspace First**
- Delete existing connections
- Delete sources/destinations
- Or restore to fresh instance

**2. Check API Compatibility**
```bash
# Ensure using v2 API endpoints
./scripts/test-api-compatibility.sh
```

**3. Verify Backup File**
```bash
# Extract and inspect backup
tar -tzf backups/airbyte_backup_v2_*.tar.gz
```

---

## Performance Issues

### Issue: Slow Sync Performance

**Diagnosis:**
```bash
# Check worker resources
kubectl top pods -n airbyte -l app=airbyte-worker

# Check worker count
kubectl get pods -n airbyte -l app=airbyte-worker
```

**Solutions:**

**1. Scale Workers**
```bash
kubectl scale deployment airbyte-worker -n airbyte --replicas=3
```

**2. Increase Worker Resources**
```yaml
# Edit k8s/airbyte/worker.yaml
resources:
  requests:
    cpu: 2
    memory: 4Gi
  limits:
    cpu: 4
    memory: 8Gi
```

**3. Adjust Worker Configuration**
```yaml
# Edit k8s/airbyte/configmap.yaml
MAX_SYNC_WORKERS: "10"  # Increase concurrent syncs
MAX_CHECK_WORKERS: "5"
```

### Issue: High Memory Usage

**Diagnosis:**
```bash
# Check memory usage
kubectl top pods -n airbyte

# Check pod limits
kubectl describe pod -n airbyte <pod-name> | grep -A 5 "Limits:"
```

**Solutions:**

**1. Increase Memory Limits**
```yaml
resources:
  limits:
    memory: 8Gi  # Increase
```

**2. Enable Heap Dump (for Java components)**
```yaml
env:
- name: JAVA_OPTS
  value: "-Xmx4g -Xms2g"
```

**3. Scale Horizontally**
```bash
# Add more worker replicas instead of increasing memory
kubectl scale deployment airbyte-worker -n airbyte --replicas=3
```

---

## Workload Identity Issues

### Issue: Workload Identity Not Working

**Symptoms:**
```
ERROR: Cannot authenticate to GCP services
ERROR: Default credentials not found
```

**Diagnosis:**
```bash
# Check service account annotation
kubectl get sa airbyte-sa -n airbyte -o yaml

# Check IAM binding
gcloud iam service-accounts get-iam-policy airbyte-gsa@PROJECT_ID.iam.gserviceaccount.com
```

**Solutions:**

**1. Verify Workload Identity Enabled on Cluster**
```bash
gcloud container clusters describe airbyte-cluster --zone=us-central1-a | grep workloadPool
```

**2. Check Service Account Binding**
```bash
gcloud iam service-accounts add-iam-policy-binding \
  airbyte-gsa@PROJECT_ID.iam.gserviceaccount.com \
  --role roles/iam.workloadIdentityUser \
  --member "serviceAccount:PROJECT_ID.svc.id.goog[airbyte/airbyte-sa]"
```

**3. Verify Pod Uses Correct Service Account**
```bash
kubectl get pods -n airbyte -o jsonpath='{.items[*].spec.serviceAccountName}'
```

**4. Re-run Setup Script**
```bash
./scripts/setup-workload-identity.sh
```

---

## Local Development Issues

### Issue: Docker Compose Not Working

**Symptoms:**
```
ERROR: Cannot pull image airbyte/server
ERROR: manifest unknown
```

**Solution:**

**Docker Compose is NOT FUNCTIONAL** (deprecated by Airbyte in August 2024)

**Use `abctl` instead:**

```bash
# Install abctl
curl -LsfS https://get.airbyte.com | bash -

# Start Airbyte locally
abctl local install

# Get credentials
abctl local credentials

# Access UI
open http://localhost:8000
```

See [LOCAL_DEVELOPMENT.md](LOCAL_DEVELOPMENT.md) for details.

### Issue: abctl Installation Fails

**Symptoms:**
```
ERROR: Cannot download abctl
```

**Solutions:**

**1. Check Internet Connection**
```bash
ping get.airbyte.com
```

**2. Manual Installation**
```bash
# Download latest release from GitHub
wget https://github.com/airbytehq/abctl/releases/latest/download/abctl-linux-amd64
chmod +x abctl-linux-amd64
sudo mv abctl-linux-amd64 /usr/local/bin/abctl
```

**3. Use Docker Alternative (if abctl fails)**
```bash
# Run Airbyte using abctl's Docker backend
abctl local install --docker
```

---

## General Troubleshooting Commands

### Check Overall System Health

```bash
# Run health check script
./scripts/health-check.sh

# Check all pods
kubectl get pods -n airbyte

# Check all services
kubectl get svc -n airbyte

# Check resource usage
kubectl top nodes
kubectl top pods -n airbyte
```

### Get Detailed Pod Information

```bash
# Describe pod
kubectl describe pod -n airbyte <pod-name>

# Get logs
kubectl logs -n airbyte <pod-name> --tail=100

# Get previous logs (if pod restarted)
kubectl logs -n airbyte <pod-name> --previous

# Follow logs
kubectl logs -n airbyte <pod-name> -f
```

### Interactive Debugging

```bash
# Shell into pod
kubectl exec -it -n airbyte <pod-name> -- sh

# Test connectivity
kubectl exec -it -n airbyte <pod-name> -- ping airbyte-server-svc
kubectl exec -it -n airbyte <pod-name> -- curl http://airbyte-server-svc:8001/v1/health

# Check environment variables
kubectl exec -it -n airbyte <pod-name> -- env | grep AIRBYTE
```

### Check Events

```bash
# All events in namespace
kubectl get events -n airbyte --sort-by='.lastTimestamp'

# Events for specific pod
kubectl get events -n airbyte --field-selector involvedObject.name=<pod-name>
```

### Network Debugging

```bash
# Install debug tools
kubectl run debug --image=nicolaka/netshoot -it --rm -n airbyte -- bash

# From debug pod, test connectivity
nslookup airbyte-server-svc.airbyte.svc.cluster.local
curl http://airbyte-server-svc.airbyte.svc.cluster.local:8001/v1/health
```

---

## When to Contact Support

If you've tried the above solutions and still have issues:

1. **Gather Information:**
   ```bash
   # Save pod descriptions
   kubectl describe pods -n airbyte > pod-descriptions.txt

   # Save logs
   kubectl logs -n airbyte deployment/airbyte-server > server-logs.txt
   kubectl logs -n airbyte deployment/airbyte-worker > worker-logs.txt

   # Save events
   kubectl get events -n airbyte --sort-by='.lastTimestamp' > events.txt
   ```

2. **Check Airbyte Resources:**
   - Documentation: https://docs.airbyte.com/
   - Community Slack: https://slack.airbyte.io/
   - GitHub Issues: https://github.com/airbytehq/airbyte/issues

3. **Include in Support Request:**
   - Airbyte version
   - Kubernetes version
   - GKE cluster details
   - Error messages
   - Steps to reproduce

---

**Document Version**: 1.0
**Last Updated**: 2025-11-10
**Airbyte Version**: 2.0.1
