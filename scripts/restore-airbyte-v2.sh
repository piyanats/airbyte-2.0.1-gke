#!/bin/bash

# Restore Airbyte Configuration using Public API (v2)
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
BACKUP_FILE="${1:-}"
RESTORE_DIR="/tmp/airbyte_restore_$$"

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
        echo "Usage: export AIRBYTE_API_TOKEN='your-token' && ./scripts/restore-airbyte-v2.sh <backup-file>"
        exit 1
    fi

    # Check if backup file provided
    if [ -z "$BACKUP_FILE" ]; then
        echo_error "Backup file not specified"
        echo "Usage: ./scripts/restore-airbyte-v2.sh <backup-file.tar.gz>"
        exit 1
    fi

    # Check if backup file exists
    if [ ! -f "$BACKUP_FILE" ]; then
        echo_error "Backup file not found: $BACKUP_FILE"
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
        exit 1
    fi

    echo_info "API connection successful"
}

extract_backup() {
    echo_info "Extracting backup archive..."

    mkdir -p "$RESTORE_DIR"
    tar -xzf "$BACKUP_FILE" -C "$RESTORE_DIR"

    echo_info "Backup extracted to: $RESTORE_DIR"
}

restore_workspaces() {
    echo_info "Restoring workspaces..."

    if [ ! -f "$RESTORE_DIR/workspaces.json" ]; then
        echo_warn "No workspaces file found, skipping"
        return
    fi

    workspace_count=0
    while IFS= read -r workspace; do
        name=$(echo "$workspace" | jq -r '.name')
        echo_info "Creating workspace: $name"

        curl -s -X POST \
            -H "Authorization: Bearer ${AIRBYTE_API_TOKEN}" \
            -H "Content-Type: application/json" \
            -d "$workspace" \
            "${AIRBYTE_API_HOST}/api/public/v1/workspaces" > /dev/null

        workspace_count=$((workspace_count + 1))
    done < <(jq -c '.data[]' "$RESTORE_DIR/workspaces.json")

    echo_info "Restored ${workspace_count} workspace(s)"
}

restore_sources() {
    echo_info "Restoring sources..."

    if [ ! -f "$RESTORE_DIR/sources.json" ]; then
        echo_warn "No sources file found, skipping"
        return
    fi

    source_count=0
    while IFS= read -r source; do
        name=$(echo "$source" | jq -r '.name')
        echo_info "Creating source: $name"

        curl -s -X POST \
            -H "Authorization: Bearer ${AIRBYTE_API_TOKEN}" \
            -H "Content-Type: application/json" \
            -d "$source" \
            "${AIRBYTE_API_HOST}/api/public/v1/sources" > /dev/null

        source_count=$((source_count + 1))
    done < <(jq -c '.data[]' "$RESTORE_DIR/sources.json")

    echo_info "Restored ${source_count} source(s)"
}

restore_destinations() {
    echo_info "Restoring destinations..."

    if [ ! -f "$RESTORE_DIR/destinations.json" ]; then
        echo_warn "No destinations file found, skipping"
        return
    fi

    dest_count=0
    while IFS= read -r dest; do
        name=$(echo "$dest" | jq -r '.name')
        echo_info "Creating destination: $name"

        curl -s -X POST \
            -H "Authorization: Bearer ${AIRBYTE_API_TOKEN}" \
            -H "Content-Type: application/json" \
            -d "$dest" \
            "${AIRBYTE_API_HOST}/api/public/v1/destinations" > /dev/null

        dest_count=$((dest_count + 1))
    done < <(jq -c '.data[]' "$RESTORE_DIR/destinations.json")

    echo_info "Restored ${dest_count} destination(s)"
}

restore_connections() {
    echo_info "Restoring connections..."

    if [ ! -f "$RESTORE_DIR/connections.json" ]; then
        echo_warn "No connections file found, skipping"
        return
    fi

    conn_count=0
    while IFS= read -r conn; do
        name=$(echo "$conn" | jq -r '.name')
        echo_info "Creating connection: $name"

        curl -s -X POST \
            -H "Authorization: Bearer ${AIRBYTE_API_TOKEN}" \
            -H "Content-Type: application/json" \
            -d "$conn" \
            "${AIRBYTE_API_HOST}/api/public/v1/connections" > /dev/null

        conn_count=$((conn_count + 1))
    done < <(jq -c '.data[]' "$RESTORE_DIR/connections.json")

    echo_info "Restored ${conn_count} connection(s)"
}

cleanup_temp() {
    echo_info "Cleaning up temporary files..."
    rm -rf "$RESTORE_DIR"
}

print_summary() {
    echo ""
    echo_info "========================================="
    echo_info "Restore Completed Successfully!"
    echo_info "========================================="
    echo ""
    echo_warn "Important Notes:"
    echo "  - New UUIDs were created for all entities"
    echo "  - Connections may need to be re-enabled"
    echo "  - OAuth tokens may need to be refreshed"
    echo "  - Test connections before enabling syncs"
    echo ""
}

# Main execution
main() {
    echo_info "Starting Airbyte restore (Public API v2)..."
    echo ""

    check_prerequisites
    test_api_connection
    extract_backup
    restore_workspaces
    restore_sources
    restore_destinations
    restore_connections
    cleanup_temp
    print_summary

    echo_info "Done!"
}

main "$@"
