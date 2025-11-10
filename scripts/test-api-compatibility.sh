#!/bin/bash

# Test Airbyte API Compatibility
# Tests both old (v1) and new (v2 Public API) endpoints

set -e

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Configuration
AIRBYTE_API_HOST="${AIRBYTE_API_HOST:-http://localhost:8001}"
AIRBYTE_API_TOKEN="${AIRBYTE_API_TOKEN:-}"

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

test_health_v1() {
    echo ""
    echo "Testing OLD health endpoint: /api/v1/health"

    response=$(curl -s -w "\n%{http_code}" "$AIRBYTE_API_HOST/api/v1/health" 2>/dev/null || echo -e "\n000")
    body=$(echo "$response" | head -n -1)
    http_code=$(echo "$response" | tail -n 1)

    if [ "$http_code" = "404" ]; then
        echo_warn "✗ OLD endpoint returns 404 (expected for Airbyte 2.0+)"
        echo_info "  This is correct for Airbyte 2.0+"
    elif [ "$http_code" = "200" ]; then
        echo_warn "✓ OLD endpoint still works (Airbyte < 2.0)"
        echo_info "  You may be running an older version"
    else
        echo_error "✗ Unexpected response: $http_code"
    fi
}

test_health_v2() {
    echo ""
    echo "Testing NEW health endpoint: /v1/health"

    response=$(curl -s -w "\n%{http_code}" "$AIRBYTE_API_HOST/v1/health" 2>/dev/null || echo -e "\n000")
    body=$(echo "$response" | head -n -1)
    http_code=$(echo "$response" | tail -n 1)

    if [ "$http_code" = "200" ]; then
        echo_info "✓ NEW endpoint works correctly"
        echo_info "  Response: $body"
    else
        echo_error "✗ NEW endpoint failed: $http_code"
        echo_error "  Check if server is running"
    fi
}

test_api_v1() {
    echo ""
    echo "Testing OLD API endpoint: /api/v1/workspaces"

    response=$(curl -s -w "\n%{http_code}" "$AIRBYTE_API_HOST/api/v1/workspaces" 2>/dev/null || echo -e "\n000")
    http_code=$(echo "$response" | tail -n 1)

    if [ "$http_code" = "404" ]; then
        echo_warn "✗ OLD API returns 404 (expected for Airbyte 2.0+)"
        echo_info "  Use /api/public/v1 instead"
    elif [ "$http_code" = "200" ] || [ "$http_code" = "401" ]; then
        echo_warn "✓ OLD API still accessible (Airbyte < 2.0)"
    else
        echo_error "✗ Unexpected response: $http_code"
    fi
}

test_api_v2() {
    echo ""
    echo "Testing NEW Public API: /api/public/v1/workspaces"

    if [ -z "$AIRBYTE_API_TOKEN" ]; then
        echo_warn "No API token provided, testing without authentication"

        response=$(curl -s -w "\n%{http_code}" "$AIRBYTE_API_HOST/api/public/v1/workspaces" 2>/dev/null || echo -e "\n000")
        http_code=$(echo "$response" | tail -n 1)

        if [ "$http_code" = "401" ]; then
            echo_info "✓ NEW API requires authentication (correct)"
            echo_info "  Set AIRBYTE_API_TOKEN to test with authentication"
        elif [ "$http_code" = "200" ]; then
            echo_warn "✓ NEW API accessible without auth (unusual)"
        else
            echo_error "✗ Unexpected response: $http_code"
        fi
    else
        echo_info "Testing with API token..."

        response=$(curl -s -w "\n%{http_code}" \
            -H "Authorization: Bearer $AIRBYTE_API_TOKEN" \
            "$AIRBYTE_API_HOST/api/public/v1/workspaces" 2>/dev/null || echo -e "\n000")

        body=$(echo "$response" | head -n -1)
        http_code=$(echo "$response" | tail -n 1)

        if [ "$http_code" = "200" ]; then
            echo_info "✓ NEW API works with authentication"
            workspace_count=$(echo "$body" | jq '.data | length' 2>/dev/null || echo "unknown")
            echo_info "  Found $workspace_count workspace(s)"
        elif [ "$http_code" = "401" ]; then
            echo_error "✗ Authentication failed"
            echo_error "  Check your API token"
        else
            echo_error "✗ Unexpected response: $http_code"
        fi
    fi
}

detect_version() {
    echo ""
    echo "Detecting Airbyte version..."

    response=$(curl -s "$AIRBYTE_API_HOST/v1/health" 2>/dev/null || echo "")

    if echo "$response" | grep -q "available"; then
        echo_info "✓ Airbyte 2.0+ detected"
        echo_info "  Health endpoint: /v1/health"
        echo_info "  API endpoint: /api/public/v1/*"
        echo_info "  Auth: Bearer token required"
    else
        echo_warn "Could not detect version"
        echo_info "  Check if server is accessible"
    fi
}

print_recommendations() {
    echo ""
    echo "========================================="
    echo_info "Recommendations for Airbyte 2.0+"
    echo "========================================="
    echo ""
    echo "1. Update health check endpoints:"
    echo "   OLD: /api/v1/health"
    echo "   NEW: /v1/health"
    echo ""
    echo "2. Update API endpoints:"
    echo "   OLD: /api/v1/*"
    echo "   NEW: /api/public/v1/*"
    echo ""
    echo "3. Use Bearer token authentication:"
    echo "   curl -H \"Authorization: Bearer \$TOKEN\" \\"
    echo "        http://localhost:8001/api/public/v1/workspaces"
    echo ""
    echo "4. Generate API token:"
    echo "   Settings → Account → Applications → New Application"
    echo ""
    echo "5. Update backup/restore scripts:"
    echo "   Use: backup-airbyte-v2.sh and restore-airbyte-v2.sh"
    echo ""
}

# Main execution
main() {
    echo "========================================="
    echo "Airbyte API Compatibility Test"
    echo "========================================="
    echo ""
    echo "Testing: $AIRBYTE_API_HOST"

    test_health_v1
    test_health_v2
    test_api_v1
    test_api_v2
    detect_version
    print_recommendations

    echo_info "Done!"
}

main "$@"
