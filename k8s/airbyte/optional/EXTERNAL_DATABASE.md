# Using External Database with Airbyte

This guide explains how to configure Airbyte to use an external PostgreSQL database instead of the internal StatefulSet deployment.

## Why Use External Database?

**Benefits:**
- **High Availability**: Automatic failover and replication
- **Managed Backups**: Automated backup and point-in-time recovery
- **Better Performance**: Optimized configuration and SSD storage
- **Automatic Updates**: Managed patches and upgrades
- **Scalability**: Easy vertical scaling without downtime
- **Monitoring**: Built-in monitoring and alerting

**Recommended for:**
- Production deployments
- High-availability requirements
- Large-scale data syncs
- Compliance requirements

## Option 1: Google Cloud SQL

### Step 1: Create Cloud SQL Instance

```bash
# Set variables
export PROJECT_ID="your-project-id"
export INSTANCE_NAME="airbyte-db"
export REGION="us-central1"
export DATABASE_VERSION="POSTGRES_13"

# Create Cloud SQL instance
gcloud sql instances create ${INSTANCE_NAME} \
  --database-version=${DATABASE_VERSION} \
  --tier=db-custom-2-7680 \
  --region=${REGION} \
  --network=default \
  --no-assign-ip \
  --enable-bin-log \
  --backup-start-time=02:00 \
  --maintenance-window-day=SUN \
  --maintenance-window-hour=03 \
  --maintenance-release-channel=production

# Note: This creates a private IP instance (more secure)
# For VPC peering or private service access, see Cloud SQL documentation
```

**Instance Sizing Guidelines:**

| Workload | vCPUs | Memory | Storage |
|----------|-------|--------|---------|
| Small    | 1     | 3.75GB | 50GB    |
| Medium   | 2     | 7.5GB  | 100GB   |
| Large    | 4     | 15GB   | 200GB   |
| X-Large  | 8     | 30GB   | 500GB   |

### Step 2: Create Database and User

```bash
# Get Cloud SQL instance connection name
gcloud sql instances describe ${INSTANCE_NAME} --format='value(connectionName)'

# Set root password
gcloud sql users set-password postgres \
  --instance=${INSTANCE_NAME} \
  --password='temporary-root-password'

# Connect to Cloud SQL
gcloud sql connect ${INSTANCE_NAME} --user=postgres

# In psql prompt:
CREATE DATABASE airbyte;
CREATE USER airbyte WITH PASSWORD 'your-secure-password';
GRANT ALL PRIVILEGES ON DATABASE airbyte TO airbyte;
\q
```

### Step 3: Get Private IP Address

```bash
# Get private IP
gcloud sql instances describe ${INSTANCE_NAME} \
  --format='value(ipAddresses[0].ipAddress)'

# Example output: 10.1.2.3
# Use this IP in the next step
```

### Step 4: Update Kubernetes Configuration

**Update ConfigMap:**

Create `k8s/examples/configmap-external-database.yaml`:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: airbyte-env
  namespace: airbyte
data:
  # ... (other config remains the same)

  # Database Configuration - Cloud SQL
  DATABASE_HOST: "10.1.2.3"  # Cloud SQL private IP
  DATABASE_PORT: "5432"
```

**Update Secrets:**

Create `k8s/examples/secrets-external-database.yaml`:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: airbyte-secrets
  namespace: airbyte
type: Opaque
stringData:
  DATABASE_USER: "airbyte"
  DATABASE_PASSWORD: "your-secure-password"  # From Step 2
  DATABASE_DB: "airbyte"
  # ... (other secrets remain the same)
```

### Step 5: Deploy Airbyte

```bash
# Apply base configuration
kubectl apply -f k8s/namespace.yaml
kubectl apply -f k8s/workload-identity.yaml
kubectl apply -f k8s/examples/secrets-external-database.yaml
kubectl apply -f k8s/examples/configmap-external-database.yaml

# Deploy Airbyte components (skip postgres.yaml)
kubectl apply -f k8s/airbyte/server.yaml
kubectl apply -f k8s/airbyte/worker.yaml
kubectl apply -f k8s/airbyte/webapp.yaml
kubectl apply -f k8s/airbyte/services.yaml
kubectl apply -f k8s/airbyte/minio.yaml
kubectl apply -f k8s/airbyte/pod-disruption-budgets.yaml

# Verify pods are running
kubectl get pods -n airbyte
```

### Step 6: Verify Connection

```bash
# Check server logs for successful database connection
kubectl logs -n airbyte deployment/airbyte-server | grep -i database

# Test connection manually
kubectl exec -it -n airbyte deployment/airbyte-server -- sh
# Inside pod:
# apt-get update && apt-get install -y postgresql-client
# psql -h 10.1.2.3 -U airbyte -d airbyte
```

## Option 2: Cloud SQL with Cloud SQL Proxy

For additional security, use Cloud SQL Proxy sidecar.

### Cloud SQL Proxy Sidecar

Add to server deployment:

```yaml
# Add to k8s/airbyte/server.yaml
spec:
  template:
    spec:
      containers:
      # ... existing server container ...

      # Add Cloud SQL Proxy sidecar
      - name: cloud-sql-proxy
        image: gcr.io/cloudsql-docker/gce-proxy:latest
        command:
        - "/cloud_sql_proxy"
        - "-instances=PROJECT_ID:REGION:INSTANCE_NAME=tcp:5432"
        securityContext:
          runAsNonRoot: true
        resources:
          requests:
            cpu: "100m"
            memory: "128Mi"
          limits:
            cpu: "500m"
            memory: "512Mi"
```

**Update DATABASE_HOST:**
```yaml
DATABASE_HOST: "127.0.0.1"  # localhost via proxy
```

**Benefits:**
- Encrypted connection
- IAM authentication (optional)
- Automatic credential rotation
- No need to whitelist IPs

## Option 3: External PostgreSQL (Non-Cloud SQL)

### Prerequisites

- PostgreSQL 13+ instance accessible from GKE
- Network connectivity configured (firewall rules, VPC peering, etc.)
- Database and user created

### Steps

1. **Create database and user:**
   ```sql
   CREATE DATABASE airbyte;
   CREATE USER airbyte WITH PASSWORD 'your-password';
   GRANT ALL PRIVILEGES ON DATABASE airbyte TO airbyte;
   ```

2. **Configure PostgreSQL for remote access:**
   ```
   # postgresql.conf
   listen_addresses = '*'

   # pg_hba.conf
   host    airbyte    airbyte    10.0.0.0/8    md5
   ```

3. **Update Kubernetes config:**
   - Set `DATABASE_HOST` to external PostgreSQL hostname/IP
   - Update credentials in secrets

4. **Test connectivity:**
   ```bash
   kubectl run -it --rm debug --image=postgres:13-alpine --restart=Never -- \
     psql -h <DB_HOST> -U airbyte -d airbyte
   ```

## Database Tuning for Airbyte

### Recommended PostgreSQL Settings

```sql
-- Connection settings
max_connections = 200

-- Memory settings
shared_buffers = 2GB
effective_cache_size = 6GB
maintenance_work_mem = 512MB
work_mem = 10MB

-- Write ahead log
wal_buffers = 16MB
min_wal_size = 1GB
max_wal_size = 4GB

-- Query planning
random_page_cost = 1.1  # For SSD
effective_io_concurrency = 200

-- Maintenance
autovacuum = on
autovacuum_max_workers = 4
```

**Apply settings:**

For Cloud SQL:
```bash
gcloud sql instances patch ${INSTANCE_NAME} \
  --database-flags=max_connections=200,shared_buffers=2097152
```

For self-managed:
```
# Edit postgresql.conf
# Restart PostgreSQL
```

## Backup Strategy

### Cloud SQL Automated Backups

```bash
# Enable automated backups (if not already enabled)
gcloud sql instances patch ${INSTANCE_NAME} \
  --backup-start-time=02:00 \
  --enable-bin-log

# Create on-demand backup
gcloud sql backups create \
  --instance=${INSTANCE_NAME}

# List backups
gcloud sql backups list \
  --instance=${INSTANCE_NAME}

# Restore from backup
gcloud sql backups restore BACKUP_ID \
  --backup-instance=${INSTANCE_NAME} \
  --restore-instance=${INSTANCE_NAME}
```

### External PostgreSQL Backups

```bash
# pg_dump backup
kubectl run -it --rm pg-backup \
  --image=postgres:13-alpine \
  --restart=Never \
  -- pg_dump -h <DB_HOST> -U airbyte airbyte > airbyte_backup.sql

# Restore
kubectl run -it --rm pg-restore \
  --image=postgres:13-alpine \
  --restart=Never \
  -- psql -h <DB_HOST> -U airbyte airbyte < airbyte_backup.sql
```

## High Availability Configuration

### Cloud SQL HA Setup

```bash
# Enable high availability
gcloud sql instances patch ${INSTANCE_NAME} \
  --availability-type=REGIONAL

# This provides:
# - Automatic failover
# - Synchronous replication
# - Regional redundancy
```

### Read Replicas (Optional)

```bash
# Create read replica (for read scaling)
gcloud sql instances create ${INSTANCE_NAME}-replica \
  --master-instance-name=${INSTANCE_NAME} \
  --tier=db-custom-2-7680 \
  --region=${REGION}
```

## Monitoring

### Cloud SQL Monitoring

```bash
# View metrics in Cloud Console:
# https://console.cloud.google.com/sql/instances/${INSTANCE_NAME}/monitoring

# Or use gcloud:
gcloud sql operations list --instance=${INSTANCE_NAME}
```

**Key Metrics to Monitor:**
- CPU utilization
- Memory utilization
- Database connections
- Query performance
- Replication lag (if using HA)

### Connection Pooling

For high connection counts, consider using PgBouncer:

```yaml
# pgbouncer-deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: pgbouncer
  namespace: airbyte
spec:
  replicas: 1
  selector:
    matchLabels:
      app: pgbouncer
  template:
    metadata:
      labels:
        app: pgbouncer
    spec:
      containers:
      - name: pgbouncer
        image: edoburu/pgbouncer:latest
        env:
        - name: DATABASE_URL
          value: "postgres://airbyte:password@10.1.2.3:5432/airbyte"
        - name: POOL_MODE
          value: "transaction"
        - name: MAX_CLIENT_CONN
          value: "1000"
        - name: DEFAULT_POOL_SIZE
          value: "20"
```

## Troubleshooting

### Connection Issues

```bash
# Test network connectivity
kubectl run -it --rm debug --image=busybox --restart=Never -- \
  telnet 10.1.2.3 5432

# Check PostgreSQL logs (Cloud SQL)
gcloud sql operations list --instance=${INSTANCE_NAME} --limit=10

# Check Airbyte server logs
kubectl logs -n airbyte deployment/airbyte-server | grep -i "database\|connection"
```

### Permission Issues

```sql
-- Verify user permissions
\du airbyte

-- Grant additional permissions if needed
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO airbyte;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO airbyte;
```

## Cost Optimization

### Cloud SQL Cost Tips

1. **Right-size your instance:**
   - Start small, scale up as needed
   - Monitor CPU and memory usage

2. **Use committed use discounts:**
   ```bash
   gcloud sql instances patch ${INSTANCE_NAME} \
     --pricing-plan=PACKAGE
   ```

3. **Enable automatic storage increase:**
   ```bash
   gcloud sql instances patch ${INSTANCE_NAME} \
     --storage-auto-increase
   ```

4. **Schedule backups during off-peak hours**

5. **Use standard storage instead of SSD for development**

## Migration from Internal to External Database

1. **Backup current data:**
   ```bash
   kubectl exec -it -n airbyte statefulset/airbyte-db -- \
     pg_dump -U airbyte airbyte > airbyte_backup.sql
   ```

2. **Create Cloud SQL instance** (see steps above)

3. **Restore data to Cloud SQL:**
   ```bash
   cat airbyte_backup.sql | gcloud sql connect ${INSTANCE_NAME} \
     --user=airbyte --database=airbyte
   ```

4. **Update Kubernetes configuration** (see Step 4 above)

5. **Deploy Airbyte with new configuration**

6. **Verify and delete old database:**
   ```bash
   kubectl delete statefulset airbyte-db -n airbyte
   kubectl delete pvc data-airbyte-db-0 -n airbyte
   ```

---

**Recommendation**: Use Cloud SQL for production deployments. It provides the best balance of reliability, performance, and operational simplicity.

For questions or issues, see:
- Cloud SQL Documentation: https://cloud.google.com/sql/docs
- PostgreSQL Documentation: https://www.postgresql.org/docs/
- Airbyte Database Documentation: https://docs.airbyte.com/
