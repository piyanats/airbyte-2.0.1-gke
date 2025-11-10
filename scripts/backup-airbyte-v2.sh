#!/bin/bash

# Backup Airbyte Configuration using Public API (v2)
# Requires Airbyte 2.0+ and API token

set -e

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Configuration
AIRBYTE_API_TOKEN="${AIRBYTE_API_TOKEN:-}"
AIRBYTE_API_HOST="${AIRBYTE_API_HOST:-http://localhost:8001}"
BACKUP_DIR="${BACKUP_DIR:-./backups}"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="${BACKUP_DIR}/airbyte_backup_v2_${TIMESTAMP}.tar.gz"

# Functions
echo_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

echo_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

echo_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

check_prerequisites() {
    echo_info "Checking prerequisites..."

    # Check if jq is installed
    if ! command -v jq &> /dev/null; then
        echo_error "jq is required but not installed"
        echo "Install: apt-get install jq (Ubuntu/Debian) or brew install jq (macOS)"
        exit 1
    fi

    # Check if curl is installed
    if ! command -v curl &> /dev/null; then
        echo_error "curl is required but not installed"
        exit 1
    fi

    # Check if API token is set
    if [ -z "$AIRBYTE_API_TOKEN" ]; then
        echo_error "AIRBYTE_API_TOKEN environment variable not set"
        echo "Generate token in Airbyte UI: Settings → Account → Applications"
        echo "Usage: export AIRBYTE_API_TOKEN='your-token' && ./scripts/backup-airbyte-v2.sh"
        exit 1
    fi

    echo_info "Prerequisites check passed"
}

test_api_connection() {
    echo_info "Testing API connection..."

    response=$(curl -s -w "\n%{http_code}" -H "Authorization: Bearer ${AIRBYTE_API_TOKEN}" \
        "${AIRBYTE_API_HOST}/v1/health" 2>/dev/null || echo "000")

    http_code=$(echo "$response" | tail -n1)

    if [ "$http_code" != "200" ]; then
        echo_error "Cannot connect to Airbyte API at ${AIRBYTE_API_HOST}"
        echo "HTTP Status: $http_code"
        echo "Ensure server is accessible and port-forward is running:"
        echo "  kubectl port-forward -n airbyte svc/airbyte-server-svc 8001:8001"
        exit 1
    fi

    echo_info "API connection successful"
}

create_backup_dir() {
    mkdir -p "${BACKUP_DIR}/tmp"
    echo_info "Backup directory: ${BACKUP_DIR}"
}

export_workspaces() {
    echo_info "Exporting workspaces..."

    curl -s -H "Authorization: Bearer ${AIRBYTE_API_TOKEN}" \
        "${AIRBYTE_API_HOST}/api/public/v1/workspaces" \
        > "${BACKUP_DIR}/tmp/workspaces.json"

    workspace_count=$(jq '.data | length' "${BACKUP_DIR}/tmp/workspaces.json" 2>/dev/null || echo "0")
    echo_info "Exported ${workspace_count} workspace(s)"
}

export_sources() {
    echo_info "Exporting sources..."

    curl -s -H "Authorization: Bearer ${AIRBYTE_API_TOKEN}" \
        "${AIRBYTE_API_HOST}/api/public/v1/sources" \
        > "${BACKUP_DIR}/tmp/sources.json"

    source_count=$(jq '.data | length' "${BACKUP_DIR}/tmp/sources.json" 2>/dev/null || echo "0")
    echo_info "Exported ${source_count} source(s)"
}

export_destinations() {
    echo_info "Exporting destinations..."

    curl -s -H "Authorization: Bearer ${AIRBYTE_API_TOKEN}" \
        "${AIRBYTE_API_HOST}/api/public/v1/destinations" \
        > "${BACKUP_DIR}/tmp/destinations.json"

    dest_count=$(jq '.data | length' "${BACKUP_DIR}/tmp/destinations.json" 2>/dev/null || echo "0")
    echo_info "Exported ${dest_count} destination(s)"
}

export_connections() {
    echo_info "Exporting connections..."

    curl -s -H "Authorization: Bearer ${AIRBYTE_API_TOKEN}" \
        "${AIRBYTE_API_HOST}/api/public/v1/connections" \
        > "${BACKUP_DIR}/tmp/connections.json"

    conn_count=$(jq '.data | length' "${BACKUP_DIR}/tmp/connections.json" 2>/dev/null || echo "0")
    echo_info "Exported ${conn_count} connection(s)"
}

export_source_definitions() {
    echo_info "Exporting source definitions..."

    curl -s -H "Authorization: Bearer ${AIRBYTE_API_TOKEN}" \
        "${AIRBYTE_API_HOST}/api/public/v1/source_definitions" \
        > "${BACKUP_DIR}/tmp/source_definitions.json" 2>/dev/null || true

    echo_info "Exported source definitions"
}

export_destination_definitions() {
    echo_info "Exporting destination definitions..."

    curl -s -H "Authorization: Bearer ${AIRBYTE_API_TOKEN}" \
        "${AIRBYTE_API_HOST}/api/public/v1/destination_definitions" \
        > "${BACKUP_DIR}/tmp/destination_definitions.json" 2>/dev/null || true

    echo_info "Exported destination definitions"
}

create_archive() {
    echo_info "Creating backup archive..."

    cd "${BACKUP_DIR}/tmp"
    tar -czf "${BACKUP_FILE}" *.json
    cd - > /dev/null

    echo_info "Backup archive created: ${BACKUP_FILE}"
}

cleanup_temp() {
    echo_info "Cleaning up temporary files..."
    rm -rf "${BACKUP_DIR}/tmp"
}

print_summary() {
    backup_size=$(du -h "${BACKUP_FILE}" | cut -f1)

    echo ""
    echo_info "========================================="
    echo_info "Backup Completed Successfully!"
    echo_info "========================================="
    echo ""
    echo_info "Backup File: ${BACKUP_FILE}"
    echo_info "Size: ${backup_size}"
    echo ""
    echo_info "To restore this backup:"
    echo "  export AIRBYTE_API_TOKEN='your-token'"
    echo "  ./scripts/restore-airbyte-v2.sh ${BACKUP_FILE}"
    echo ""
}

# Main execution
main() {
    echo_info "Starting Airbyte backup (Public API v2)..."
    echo ""

    check_prerequisites
    test_api_connection
    create_backup_dir
    export_workspaces
    export_sources
    export_destinations
    export_connections
    export_source_definitions
    export_destination_definitions
    create_archive
    cleanup_temp
    print_summary

    echo_info "Done!"
}

main "$@"
