# Airbyte API Compatibility Warning

## ⚠️ Important: API Changes in Airbyte 2.0+

If you're experiencing issues with API calls or health checks, your scripts may be using deprecated endpoints.

## Quick Check

Run this command to test your Airbyte API:

```bash
./scripts/test-api-compatibility.sh
```

Or with API token:
```bash
export AIRBYTE_API_TOKEN='your-token'
./scripts/test-api-compatibility.sh
```

## Common Issues

### 1. Health Check Returns 404

**Problem:**
```bash
$ curl http://localhost:8001/api/v1/health
404 Not Found
```

**Solution:**
Airbyte 2.0+ uses a different health endpoint:
```bash
$ curl http://localhost:8001/v1/health
{"available":true}
```

**Action Required:**
- Update Kubernetes liveness/readiness probes
- Update monitoring scripts
- Update health check tools

### 2. API Endpoint Returns 404

**Problem:**
```bash
$ curl http://localhost:8001/api/v1/workspaces
404 Not Found
```

**Solution:**
Use the new Public API endpoint:
```bash
$ curl -H "Authorization: Bearer YOUR_TOKEN" \
  http://localhost:8001/api/public/v1/workspaces
```

**Action Required:**
- Update all API calls to use `/api/public/v1` prefix
- Generate and use Bearer token for authentication

### 3. Backup Script Fails

**Problem:**
```bash
$ ./scripts/backup-airbyte.sh
ERROR: API endpoint not found
```

**Solution:**
Use the v2 backup script:
```bash
$ export AIRBYTE_API_TOKEN='your-token'
$ ./scripts/backup-airbyte-v2.sh
```

## Breaking Changes Summary

| What Changed | Old (< 2.0) | New (2.0+) |
|--------------|-------------|------------|
| Health Endpoint | `/api/v1/health` | `/v1/health` |
| API Base Path | `/api/v1/` | `/api/public/v1/` |
| Authentication | Basic auth (UI only) | Bearer token (required) |
| Workspaces API | `/api/v1/workspaces` | `/api/public/v1/workspaces` |
| Sources API | `/api/v1/sources` | `/api/public/v1/sources` |
| Destinations API | `/api/v1/destinations` | `/api/public/v1/destinations` |
| Connections API | `/api/v1/connections` | `/api/public/v1/connections` |

## How to Fix

### Step 1: Verify Your Airbyte Version

Check the version in the UI or via API:

```bash
# Access Airbyte UI
kubectl port-forward -n airbyte svc/airbyte-webapp-svc 8000:8000

# Open http://localhost:8000
# Check version in Settings
```

### Step 2: Generate API Token

If you're on Airbyte 2.0+, you'll need an API token:

1. Open Airbyte UI
2. Go to **Settings → Account → Applications**
3. Click **"New Application"**
4. Give it a name (e.g., "Scripts")
5. **Copy the generated token** (you won't see it again!)
6. Store securely

### Step 3: Update Your Scripts

**For backup/restore:**

```bash
# Set your API token
export AIRBYTE_API_TOKEN='your-token-here'

# Run v2 scripts
./scripts/backup-airbyte-v2.sh
./scripts/restore-airbyte-v2.sh backups/airbyte_backup_v2_*.tar.gz
```

**For custom scripts:**

```bash
# Old way (doesn't work)
curl http://localhost:8001/api/v1/workspaces

# New way (works)
curl -H "Authorization: Bearer $AIRBYTE_API_TOKEN" \
  http://localhost:8001/api/public/v1/workspaces
```

### Step 4: Update Kubernetes Manifests

Update health check probes in your deployments:

```yaml
# OLD - WILL FAIL
livenessProbe:
  httpGet:
    path: /api/v1/health  # ❌ Wrong
    port: 8001

# NEW - CORRECT
livenessProbe:
  httpGet:
    path: /v1/health  # ✅ Correct
    port: 8001
```

Apply the corrected manifests:

```bash
kubectl apply -f k8s/airbyte/server.yaml
kubectl apply -f k8s/airbyte/webapp.yaml
```

### Step 5: Update Automated Backups

If using CronJob for backups:

```bash
# Create API token secret
kubectl create secret generic airbyte-api-token \
  -n airbyte \
  --from-literal=token='your-api-token-here'

# Deploy v2 CronJob
kubectl apply -f k8s/airbyte/optional/backup-cronjob-v2.yaml
```

## Testing Your Changes

### Test Health Endpoint

```bash
# Should return: {"available":true}
curl http://localhost:8001/v1/health
```

### Test API Endpoint

```bash
export AIRBYTE_API_TOKEN='your-token'

# Should return workspace list
curl -H "Authorization: Bearer $AIRBYTE_API_TOKEN" \
  http://localhost:8001/api/public/v1/workspaces | jq .
```

### Test Backup Script

```bash
export AIRBYTE_API_TOKEN='your-token'

# Should create backup successfully
./scripts/backup-airbyte-v2.sh

# Check backup file
ls -lh backups/
```

## Impact on Different Components

### 1. Kubernetes Health Checks

**Status:** ⚠️ Critical

If using old health check path, pods will fail liveness/readiness probes.

**Fix:**
Update all deployments with new path: `/v1/health`

### 2. Monitoring Scripts

**Status:** ⚠️ High

Monitoring scripts using old health endpoint will report service as down.

**Fix:**
Update monitoring to use new endpoint.

### 3. Backup/Restore Scripts

**Status:** ⚠️ High

Old backup scripts will fail completely.

**Fix:**
Use v2 scripts with API token.

### 4. CI/CD Pipelines

**Status:** ⚠️ Medium

Any CI/CD automation using Airbyte API will break.

**Fix:**
- Generate service account token
- Update API endpoints
- Store token in secrets manager

### 5. Custom Integrations

**Status:** ⚠️ Medium

Custom scripts or tools using Airbyte API need updates.

**Fix:**
- Update API endpoints
- Implement Bearer token authentication
- Test thoroughly

## Rollback Strategy

If you need to rollback to a pre-2.0 version:

```bash
# Update image versions in manifests
# Change: image: airbyte/server:2.0.1
# To:     image: airbyte/server:0.50.x

# Apply changes
kubectl apply -f k8s/airbyte/

# Use v1 scripts
./scripts/backup-airbyte.sh  # Old script
```

**Note:** Rollback may cause data compatibility issues. Always backup first!

## Additional Resources

- **Full Migration Guide:** [V2_MIGRATION_GUIDE.md](V2_MIGRATION_GUIDE.md)
- **Airbyte 2.0 Release Notes:** https://docs.airbyte.com/release_notes/v-2.0
- **Public API Docs:** https://docs.airbyte.com/api-documentation
- **API Reference:** https://reference.airbyte.com/

## Need Help?

1. **Test your setup:**
   ```bash
   ./scripts/test-api-compatibility.sh
   ```

2. **Check logs:**
   ```bash
   kubectl logs -n airbyte deployment/airbyte-server --tail=100
   ```

3. **Verify health:**
   ```bash
   ./scripts/health-check.sh
   ```

4. **Review documentation:**
   - See [TROUBLESHOOTING.md](../TROUBLESHOOTING.md)
   - See [RUNBOOK.md](../RUNBOOK.md)

## Checklist for Migration

- [ ] Verified Airbyte version (2.0+)
- [ ] Generated API token
- [ ] Updated health check endpoints
- [ ] Updated API endpoints in scripts
- [ ] Tested backup script with token
- [ ] Tested restore script
- [ ] Updated Kubernetes manifests
- [ ] Updated monitoring scripts
- [ ] Updated CI/CD pipelines
- [ ] Tested all integrations
- [ ] Updated documentation

---

**Last Updated:** 2025-11-10
**Applies To:** Airbyte 2.0+
