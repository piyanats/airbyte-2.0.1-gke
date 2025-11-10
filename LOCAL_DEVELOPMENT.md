# Local Development Guide

This guide explains how to run Airbyte locally for development and testing purposes.

## ⚠️ Important: Docker Compose is NOT Functional

**Docker Compose was deprecated by Airbyte in August 2024.**

- Airbyte does NOT publish Docker images to Docker Hub
- The `docker-compose.yml` in this repo is **for reference only**
- It will **NOT work** if you try to run it

**For local development, use `abctl` (Airbyte's official CLI tool)**

---

## Using abctl (Recommended Method)

### What is abctl?

`abctl` is Airbyte's official command-line tool for running Airbyte locally. It:
- Automatically downloads and runs Airbyte
- Manages all dependencies
- Provides an easy setup process
- Works on Linux, macOS, and Windows

### Prerequisites

**System Requirements:**
- Docker installed and running
- At least 8GB RAM available
- At least 10GB free disk space
- 64-bit operating system

**Software Requirements:**
- Docker Desktop or Docker Engine
- Internet connection

### Installation

**Automatic Installation (Recommended):**

```bash
curl -LsfS https://get.airbyte.com | bash -
```

This script will:
1. Detect your operating system
2. Download the appropriate `abctl` binary
3. Install it to your PATH
4. Verify installation

**Manual Installation:**

**Linux:**
```bash
wget https://github.com/airbytehq/abctl/releases/latest/download/abctl-linux-amd64
chmod +x abctl-linux-amd64
sudo mv abctl-linux-amd64 /usr/local/bin/abctl
```

**macOS (Intel):**
```bash
wget https://github.com/airbytehq/abctl/releases/latest/download/abctl-darwin-amd64
chmod +x abctl-darwin-amd64
sudo mv abctl-darwin-amd64 /usr/local/bin/abctl
```

**macOS (Apple Silicon):**
```bash
wget https://github.com/airbytehq/abctl/releases/latest/download/abctl-darwin-arm64
chmod +x abctl-darwin-arm64
sudo mv abctl-darwin-arm64 /usr/local/bin/abctl
```

**Verify Installation:**
```bash
abctl version
```

### Starting Airbyte Locally

**Basic Start:**

```bash
abctl local install
```

This command will:
1. Download Airbyte components
2. Start all services
3. Initialize the database
4. Print access information

**Expected Output:**
```
Airbyte is starting...
✓ Server started
✓ Worker started
✓ Webapp started
✓ Database initialized

Airbyte is ready!

Access Airbyte at: http://localhost:8000
```

**Custom Port:**

```bash
abctl local install --port 9000
```

**Specify Version:**

```bash
abctl local install --version 2.0.1
```

### Getting Credentials

After installation, get the default credentials:

```bash
abctl local credentials
```

**Output:**
```
Airbyte Credentials:
  Email:    your-email@localhost
  Password: your-generated-password

Access URL: http://localhost:8000
```

### Accessing Airbyte

1. Open your browser
2. Navigate to: http://localhost:8000
3. Login with the credentials from `abctl local credentials`
4. Complete the initial setup wizard

### Stopping Airbyte

**Stop Airbyte (keeps data):**

```bash
abctl local stop
```

**Restart Airbyte:**

```bash
abctl local start
```

### Removing Airbyte

**Remove everything (including data):**

```bash
abctl local uninstall
```

**Warning:** This will delete all your local Airbyte data, including connections and sync history.

### Viewing Logs

**All logs:**

```bash
abctl local logs
```

**Specific component:**

```bash
abctl local logs --component server
abctl local logs --component worker
abctl local logs --component webapp
```

**Follow logs:**

```bash
abctl local logs -f
```

### Status Check

**Check if Airbyte is running:**

```bash
abctl local status
```

**Output Example:**
```
Airbyte Status:
  Server:  Running
  Worker:  Running
  Webapp:  Running
  Database: Running

Access URL: http://localhost:8000
```

---

## Troubleshooting abctl

### Issue: abctl command not found

**Solution:**

```bash
# Check if abctl is in PATH
which abctl

# If not found, add to PATH
export PATH=$PATH:/usr/local/bin

# Or reinstall
curl -LsfS https://get.airbyte.com | bash -
```

### Issue: Port Already in Use

**Error:**
```
ERROR: Port 8000 is already in use
```

**Solution:**

**Option 1: Stop other service using port 8000:**
```bash
# Find process using port 8000
lsof -i :8000
# or
sudo netstat -tulpn | grep 8000

# Kill the process
kill <PID>
```

**Option 2: Use different port:**
```bash
abctl local install --port 9000
```

### Issue: Docker Not Running

**Error:**
```
ERROR: Cannot connect to Docker daemon
```

**Solution:**

```bash
# Check Docker status
docker ps

# Start Docker
# For Docker Desktop: Start the application
# For Linux:
sudo systemctl start docker

# Verify Docker is running
docker ps
```

### Issue: Insufficient Resources

**Error:**
```
ERROR: Not enough memory available
```

**Solution:**

1. **Increase Docker resources:**
   - Docker Desktop → Settings → Resources
   - Increase Memory to at least 8GB
   - Increase CPUs to at least 4

2. **Close other applications:**
   - Free up system memory
   - Stop unnecessary Docker containers

3. **Clean up Docker:**
   ```bash
   docker system prune -a
   ```

### Issue: abctl install hangs or fails

**Symptoms:**
- Installation process stuck
- Download timeout
- Service won't start

**Solutions:**

**1. Check internet connection:**
```bash
ping get.airbyte.com
```

**2. Clean up and retry:**
```bash
# Uninstall current installation
abctl local uninstall

# Clear Docker resources
docker system prune -a -f

# Retry installation
abctl local install
```

**3. Check Docker logs:**
```bash
abctl local logs

# Or check Docker directly
docker ps -a
docker logs <container-id>
```

**4. Use verbose mode:**
```bash
abctl local install --verbose
```

### Issue: Cannot Access UI After Install

**Symptoms:**
- `abctl local status` shows services running
- Cannot access http://localhost:8000
- Connection refused or timeout

**Solutions:**

**1. Verify services are actually running:**
```bash
abctl local status
docker ps
```

**2. Check if port is accessible:**
```bash
curl http://localhost:8000
```

**3. Try different browser:**
- Clear browser cache
- Try incognito/private mode
- Try different browser

**4. Check firewall:**
```bash
# Temporarily disable firewall to test
# macOS:
sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setglobalstate off

# Linux (UFW):
sudo ufw disable

# Re-enable after testing!
```

**5. Restart abctl:**
```bash
abctl local stop
abctl local start
```

---

## Testing Against Local Airbyte

### API Access

**Health Check:**

```bash
curl http://localhost:8000/v1/health
```

**API Calls (requires token):**

1. Generate API token in UI:
   - Settings → Account → Applications → New Application

2. Use token:
   ```bash
   export AIRBYTE_API_TOKEN='your-token'

   curl -H "Authorization: Bearer $AIRBYTE_API_TOKEN" \
     http://localhost:8000/api/public/v1/workspaces
   ```

### Testing Backup/Restore Scripts

**Backup local instance:**

```bash
export AIRBYTE_API_TOKEN='your-token'
export AIRBYTE_API_HOST='http://localhost:8000'
./scripts/backup-airbyte-v2.sh
```

**Restore to local instance:**

```bash
export AIRBYTE_API_TOKEN='your-token'
export AIRBYTE_API_HOST='http://localhost:8000'
./scripts/restore-airbyte-v2.sh backups/airbyte_backup_v2_*.tar.gz
```

### Testing Kubernetes Manifests

While you can't directly test the Kubernetes manifests locally with `abctl`, you can:

1. **Validate YAML syntax:**
   ```bash
   kubectl apply --dry-run=client -f k8s/
   ```

2. **Use kind (Kubernetes in Docker):**
   ```bash
   # Install kind
   curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.20.0/kind-linux-amd64
   chmod +x ./kind
   sudo mv ./kind /usr/local/bin/kind

   # Create local cluster
   kind create cluster --name airbyte-test

   # Deploy Airbyte
   kubectl apply -f k8s/
   ```

3. **Use minikube:**
   ```bash
   # Start minikube
   minikube start --memory=8192 --cpus=4

   # Deploy Airbyte
   kubectl apply -f k8s/
   ```

---

## Comparing Local vs GKE Deployment

### Architecture Differences

**Local (abctl):**
- All components in Docker containers
- Single machine
- Development/testing only
- No high availability
- Limited scalability

**GKE Deployment:**
- Kubernetes pods
- Multi-node cluster
- Production-ready
- High availability
- Horizontal scalability
- Workload Identity
- Resource quotas

### Configuration Differences

**Local:**
- Default configuration
- SQLite or embedded PostgreSQL
- Local file storage
- Basic authentication
- No external integrations

**GKE:**
- Production configuration
- Cloud SQL or PV-backed PostgreSQL
- GCS or Minio storage
- Workload Identity
- Integration with GCP services

### When to Use Each

**Use Local (abctl) for:**
- Development and testing
- Learning Airbyte
- Testing connectors
- Quick experiments
- Validating configurations

**Use GKE for:**
- Production workloads
- Team collaboration
- Large-scale data syncs
- High availability requirements
- Integration with GCP services

---

## Development Workflow

### Recommended Workflow

1. **Develop locally:**
   ```bash
   # Start Airbyte
   abctl local install

   # Test your changes
   # Create connectors, test syncs, etc.
   ```

2. **Export configuration:**
   ```bash
   # Backup configuration
   export AIRBYTE_API_TOKEN='your-token'
   export AIRBYTE_API_HOST='http://localhost:8000'
   ./scripts/backup-airbyte-v2.sh
   ```

3. **Deploy to GKE:**
   ```bash
   # Deploy to GKE
   kubectl apply -f k8s/

   # Wait for ready
   kubectl get pods -n airbyte -w
   ```

4. **Restore configuration:**
   ```bash
   # Port-forward to GKE
   kubectl port-forward -n airbyte svc/airbyte-server-svc 8001:8001

   # Restore backup
   export AIRBYTE_API_TOKEN='your-gke-token'
   export AIRBYTE_API_HOST='http://localhost:8001'
   ./scripts/restore-airbyte-v2.sh backups/airbyte_backup_v2_*.tar.gz
   ```

---

## Advanced abctl Usage

### Custom Docker Network

```bash
abctl local install --docker-network custom-network
```

### Environment Variables

```bash
# Set custom environment variables
export AIRBYTE_PORT=9000
abctl local install
```

### Data Persistence

By default, `abctl` stores data in:
- Linux: `~/.airbyte/data`
- macOS: `~/Library/Application Support/abctl/data`
- Windows: `%APPDATA%\abctl\data`

**Backup data directory:**
```bash
tar -czf airbyte-local-backup.tar.gz ~/.airbyte/data
```

**Restore data directory:**
```bash
abctl local uninstall
tar -xzf airbyte-local-backup.tar.gz -C ~/
abctl local install
```

---

## Alternative: Docker Compose (Reference Only)

The `docker-compose.yml` file in this repository is **for reference only** and shows the expected architecture, but it **will not work** because:

1. Airbyte doesn't publish images to Docker Hub
2. The docker-compose.yml uses images that don't exist publicly
3. Docker Compose deployment was officially deprecated in August 2024

**If you see the docker-compose.yml file:**
- It's kept for reference to understand component relationships
- Don't try to run `docker-compose up`
- Use `abctl` instead

---

## Getting Help

### abctl Help

```bash
# General help
abctl --help

# Command-specific help
abctl local --help
abctl local install --help
```

### Community Resources

- **Documentation**: https://docs.airbyte.com/
- **Community Slack**: https://slack.airbyte.io/
- **GitHub Issues**: https://github.com/airbytehq/airbyte/issues
- **abctl Repository**: https://github.com/airbytehq/abctl

### Common Commands Reference

```bash
# Installation
abctl local install                 # Install Airbyte
abctl local install --port 9000     # Install on custom port
abctl local install --version 2.0.1 # Install specific version

# Management
abctl local status                  # Check status
abctl local credentials             # Get credentials
abctl local start                   # Start Airbyte
abctl local stop                    # Stop Airbyte
abctl local uninstall              # Uninstall Airbyte

# Debugging
abctl local logs                    # View all logs
abctl local logs -f                 # Follow logs
abctl local logs --component server # Component-specific logs
abctl version                       # Show abctl version
```

---

## FAQ

### Q: Can I use Docker Compose?
**A:** No, Docker Compose is not supported. Use `abctl` instead.

### Q: Can I run Airbyte in Kubernetes locally?
**A:** Yes, use kind or minikube. See "Testing Kubernetes Manifests" section above.

### Q: How do I upgrade Airbyte locally?
**A:**
```bash
abctl local uninstall
abctl local install --version 2.1.0
```

### Q: Can I connect local Airbyte to production databases?
**A:** Yes, but be careful. Use read-only credentials when possible.

### Q: How much disk space does local Airbyte use?
**A:** Typically 2-5GB, but can grow with sync history.

### Q: Can I run multiple Airbyte instances locally?
**A:** Yes, use different ports:
```bash
abctl local install --port 8000
abctl local install --port 9000
```

### Q: Where are logs stored?
**A:** Access logs via `abctl local logs` or check Docker container logs.

---

**Document Version**: 1.0
**Last Updated**: 2025-11-10
**Airbyte Version**: 2.0.1
