# Airbyte API v2 Migration Guide

## Overview

Airbyte 2.0 introduced a new Public API (`/api/public/v1`) that replaces the old internal API (`/api/v1`). This guide explains the changes and how to migrate your backup/restore workflows.

## What Changed in Airbyte 2.0?

### API Endpoints

**Old (Deprecated):**
```
/api/v1/workspaces
/api/v1/sources
/api/v1/destinations
/api/v1/connections
```

**New (Current):**
```
/api/public/v1/workspaces
/api/public/v1/sources
/api/public/v1/destinations
/api/public/v1/connections
```

### Health Check Endpoint

**Old:**
```
/api/v1/health
```

**New:**
```
/v1/health
```

### Authentication

**Old:**
- Basic authentication worked on API endpoints
- No token required for some operations

**New:**
- **Bearer token authentication required** for all API operations
- Generate token in UI: Settings → Account → Applications
- Token format: `Authorization: Bearer YOUR_TOKEN`

## Migration Steps

### 1. Update Health Checks

If you have monitoring or health check scripts:

**Old:**
```bash
curl http://localhost:8001/api/v1/health
```

**New:**
```bash
curl http://localhost:8001/v1/health
```

### 2. Generate API Token

1. Open Airbyte UI
2. Go to Settings → Account → Applications
3. Click "New Application"
4. Give it a name (e.g., "Backup Script")
5. Copy the generated token
6. Store securely (e.g., in environment variable)

### 3. Update Backup Scripts

**Old Script (v1):**
```bash
./scripts/backup-airbyte.sh  # Old, won't work with 2.0+
```

**New Script (v2):**
```bash
export AIRBYTE_API_TOKEN='your-token-here'
./scripts/backup-airbyte-v2.sh
```

### 4. Update Restore Scripts

**Old Script (v1):**
```bash
./scripts/restore-airbyte.sh backup.tar.gz  # Old
```

**New Script (v2):**
```bash
export AIRBYTE_API_TOKEN='your-token-here'
./scripts/restore-airbyte-v2.sh backups/airbyte_backup_v2_20240101_120000.tar.gz
```

### 5. Update Kubernetes Manifests

Update health check probes in deployments:

**server.yaml - OLD:**
```yaml
livenessProbe:
  httpGet:
    path: /api/v1/health  # Wrong
    port: 8001
```

**server.yaml - NEW:**
```yaml
livenessProbe:
  httpGet:
    path: /v1/health  # Correct
    port: 8001
```

### 6. Update API Calls in Scripts

**Old:**
```bash
curl http://localhost:8001/api/v1/workspaces
```

**New:**
```bash
curl -H "Authorization: Bearer $AIRBYTE_API_TOKEN" \
  http://localhost:8001/api/public/v1/workspaces
```

## Backup/Restore Changes

### What's Different?

| Feature | v1 (Old) | v2 (New) |
|---------|----------|----------|
| API Endpoint | `/api/v1/*` | `/api/public/v1/*` |
| Authentication | Basic auth | Bearer token |
| Token Required | No | Yes |
| Script Name | `backup-airbyte.sh` | `backup-airbyte-v2.sh` |
| Restore Script | `restore-airbyte.sh` | `restore-airbyte-v2.sh` |

### Backup Workflow

**1. Generate API Token (one-time):**
```bash
# In Airbyte UI: Settings → Account → Applications → New Application
# Copy the token
```

**2. Set Environment Variable:**
```bash
export AIRBYTE_API_TOKEN='abcd1234...'
```

**3. Run Backup:**
```bash
./scripts/backup-airbyte-v2.sh
```

**4. Backup Location:**
```
backups/airbyte_backup_v2_YYYYMMDD_HHMMSS.tar.gz
```

### Restore Workflow

**1. Ensure API Token is Set:**
```bash
export AIRBYTE_API_TOKEN='abcd1234...'
```

**2. Ensure Server is Accessible:**
```bash
# If using kubectl port-forward:
kubectl port-forward -n airbyte svc/airbyte-server-svc 8001:8001 &

# Test connection:
curl http://localhost:8001/v1/health
```

**3. Run Restore:**
```bash
./scripts/restore-airbyte-v2.sh backups/airbyte_backup_v2_20240101_120000.tar.gz
```

**4. Post-Restore Steps:**
- Verify workspaces in UI
- Check sources and destinations
- Test connections
- Re-enable connections (they're created disabled)
- Refresh OAuth tokens if needed

## Automated Backups (CronJob)

### Setup API Token Secret

```bash
# Create secret with API token
kubectl create secret generic airbyte-api-token \
  -n airbyte \
  --from-literal=token='your-api-token-here'
```

### Deploy CronJob

```bash
kubectl apply -f k8s/airbyte/optional/backup-cronjob-v2.yaml
```

### Verify CronJob

```bash
# Check CronJob
kubectl get cronjobs -n airbyte

# Test manually
kubectl create job --from=cronjob/airbyte-backup-v2 test-backup -n airbyte

# Check logs
kubectl logs -n airbyte job/test-backup
```

## Testing API Compatibility

Run the compatibility test script to check your Airbyte version:

```bash
./scripts/test-api-compatibility.sh
```

**With API token:**
```bash
export AIRBYTE_API_TOKEN='your-token'
./scripts/test-api-compatibility.sh
```

This will test:
- Old health endpoint (`/api/v1/health`)
- New health endpoint (`/v1/health`)
- Old API endpoint (`/api/v1/workspaces`)
- New API endpoint (`/api/public/v1/workspaces`)
- Version detection

## Common Migration Issues

### Issue 1: Health Check Returns 404

**Problem:**
```
GET /api/v1/health → 404 Not Found
```

**Solution:**
Update to new endpoint:
```
GET /v1/health → 200 OK
```

### Issue 2: API Returns 401 Unauthorized

**Problem:**
```bash
curl http://localhost:8001/api/public/v1/workspaces
# Returns: 401 Unauthorized
```

**Solution:**
Add Bearer token:
```bash
curl -H "Authorization: Bearer YOUR_TOKEN" \
  http://localhost:8001/api/public/v1/workspaces
```

### Issue 3: Backup Script Fails

**Problem:**
```
ERROR: AIRBYTE_API_TOKEN not set
```

**Solution:**
```bash
export AIRBYTE_API_TOKEN='your-token-here'
./scripts/backup-airbyte-v2.sh
```

### Issue 4: Old Backup File Won't Restore

**Problem:**
Backup created with v1 script won't restore with v2 script.

**Solution:**
- V1 and v2 backup formats may differ
- Create new backup with v2 script
- Or manually migrate data structure

## Best Practices

### 1. Secure Token Storage

**Don't:**
```bash
# Hard-coded in script (insecure)
AIRBYTE_API_TOKEN="abc123..."
```

**Do:**
```bash
# From environment variable
export AIRBYTE_API_TOKEN='abc123...'

# Or from file (chmod 600)
export AIRBYTE_API_TOKEN=$(cat ~/.airbyte-token)

# Or from secret manager
export AIRBYTE_API_TOKEN=$(gcloud secrets versions access latest --secret="airbyte-api-token")
```

### 2. Token Rotation

- Generate new tokens periodically
- Revoke old tokens after migration
- Update all scripts and CronJobs with new token

### 3. Backup Validation

After backup:
```bash
# Verify backup file exists
ls -lh backups/airbyte_backup_v2_*.tar.gz

# Check backup contents
tar -tzf backups/airbyte_backup_v2_latest.tar.gz

# Test restore in development environment
```

### 4. Monitoring

Set up monitoring for:
- Backup CronJob success/failure
- Backup file creation
- Backup file size (should be > 0)
- API token expiration

## Additional Resources

- **Airbyte 2.0 Release Notes:** https://docs.airbyte.com/release_notes/v-2.0
- **Public API Documentation:** https://docs.airbyte.com/api-documentation
- **API Reference:** https://reference.airbyte.com/
- **Migration FAQ:** https://docs.airbyte.com/migration/v2

## Quick Reference

### v1 to v2 Mapping

| v1 (Old) | v2 (New) |
|----------|----------|
| `/api/v1/health` | `/v1/health` |
| `/api/v1/workspaces` | `/api/public/v1/workspaces` |
| `/api/v1/sources` | `/api/public/v1/sources` |
| `/api/v1/destinations` | `/api/public/v1/destinations` |
| `/api/v1/connections` | `/api/public/v1/connections` |
| Basic auth | Bearer token |
| `backup-airbyte.sh` | `backup-airbyte-v2.sh` |
| `restore-airbyte.sh` | `restore-airbyte-v2.sh` |

### Environment Variables

```bash
# Required for v2 scripts
export AIRBYTE_API_TOKEN='your-token-here'

# Optional configuration
export AIRBYTE_API_HOST='http://localhost:8001'  # Default
export BACKUP_DIR='./backups'                    # Default
```

---

**Last Updated:** 2025-11-10
**Airbyte Version:** 2.0.1+
