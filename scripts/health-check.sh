#!/bin/bash

# Comprehensive Health Check for Airbyte on GKE

set -e

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Configuration
NAMESPACE="${NAMESPACE:-airbyte}"
EXIT_CODE=0

# Functions
echo_info() {
    echo -e "${GREEN}[✓]${NC} $1"
}

echo_warn() {
    echo -e "${YELLOW}[!]${NC} $1"
}

echo_error() {
    echo -e "${RED}[✗]${NC} $1"
    EXIT_CODE=1
}

check_kubectl() {
    if ! command -v kubectl &> /dev/null; then
        echo_error "kubectl not found"
        exit 1
    fi
}

check_namespace() {
    echo "Checking namespace..."

    if kubectl get namespace "$NAMESPACE" &>/dev/null; then
        echo_info "Namespace '$NAMESPACE' exists"
    else
        echo_error "Namespace '$NAMESPACE' not found"
    fi
}

check_pods() {
    echo ""
    echo "Checking pods..."

    pods=$(kubectl get pods -n "$NAMESPACE" --no-headers 2>/dev/null || echo "")

    if [ -z "$pods" ]; then
        echo_error "No pods found in namespace '$NAMESPACE'"
        return
    fi

    while IFS= read -r line; do
        name=$(echo "$line" | awk '{print $1}')
        ready=$(echo "$line" | awk '{print $2}')
        status=$(echo "$line" | awk '{print $3}')
        restarts=$(echo "$line" | awk '{print $4}')

        if [ "$status" = "Running" ] && [[ "$ready" == *"/"* ]]; then
            ready_count=$(echo "$ready" | cut -d'/' -f1)
            total_count=$(echo "$ready" | cut -d'/' -f2)

            if [ "$ready_count" = "$total_count" ]; then
                echo_info "Pod $name is running and ready ($ready)"
            else
                echo_warn "Pod $name is running but not ready ($ready)"
            fi
        else
            echo_error "Pod $name is not running (Status: $status, Ready: $ready)"
        fi

        if [ "$restarts" -gt 5 ]; then
            echo_warn "Pod $name has high restart count: $restarts"
        fi
    done <<< "$pods"
}

check_services() {
    echo ""
    echo "Checking services..."

    services=("airbyte-webapp-svc" "airbyte-server-svc" "airbyte-db-svc" "airbyte-minio-svc")

    for svc in "${services[@]}"; do
        if kubectl get svc "$svc" -n "$NAMESPACE" &>/dev/null; then
            endpoints=$(kubectl get endpoints "$svc" -n "$NAMESPACE" -o jsonpath='{.subsets[*].addresses[*].ip}' 2>/dev/null || echo "")
            if [ -n "$endpoints" ]; then
                echo_info "Service $svc is available (Endpoints: $endpoints)"
            else
                echo_warn "Service $svc has no endpoints"
            fi
        else
            echo_warn "Service $svc not found (may be optional)"
        fi
    done
}

check_statefulsets() {
    echo ""
    echo "Checking StatefulSets..."

    statefulsets=$(kubectl get statefulsets -n "$NAMESPACE" --no-headers 2>/dev/null || echo "")

    if [ -z "$statefulsets" ]; then
        echo_warn "No StatefulSets found"
        return
    fi

    while IFS= read -r line; do
        name=$(echo "$line" | awk '{print $1}')
        ready=$(echo "$line" | awk '{print $2}')
        desired=$(echo "$line" | cut -d'/' -f2 <<< "$ready")
        current=$(echo "$line" | cut -d'/' -f1 <<< "$ready")

        if [ "$current" = "$desired" ]; then
            echo_info "StatefulSet $name is ready ($ready)"
        else
            echo_error "StatefulSet $name is not ready ($ready)"
        fi
    done <<< "$statefulsets"
}

check_pvcs() {
    echo ""
    echo "Checking PersistentVolumeClaims..."

    pvcs=$(kubectl get pvc -n "$NAMESPACE" --no-headers 2>/dev/null || echo "")

    if [ -z "$pvcs" ]; then
        echo_warn "No PVCs found"
        return
    fi

    while IFS= read -r line; do
        name=$(echo "$line" | awk '{print $1}')
        status=$(echo "$line" | awk '{print $2}')
        volume=$(echo "$line" | awk '{print $3}')

        if [ "$status" = "Bound" ]; then
            echo_info "PVC $name is bound to volume $volume"
        else
            echo_error "PVC $name is not bound (Status: $status)"
        fi
    done <<< "$pvcs"
}

check_api_health() {
    echo ""
    echo "Checking Airbyte API health..."

    server_pod=$(kubectl get pods -n "$NAMESPACE" -l app=airbyte-server -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

    if [ -z "$server_pod" ]; then
        echo_error "Server pod not found, cannot check API health"
        return
    fi

    health=$(kubectl exec -n "$NAMESPACE" "$server_pod" -- curl -s http://localhost:8001/v1/health 2>/dev/null || echo "")

    if echo "$health" | grep -q "available"; then
        echo_info "API health endpoint is responding"
    else
        echo_error "API health endpoint is not responding correctly"
    fi
}

check_database_connectivity() {
    echo ""
    echo "Checking database connectivity..."

    db_pod=$(kubectl get pods -n "$NAMESPACE" -l app=airbyte-db -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

    if [ -z "$db_pod" ]; then
        echo_warn "Database pod not found (may be using external database)"
        return
    fi

    if kubectl exec -n "$NAMESPACE" "$db_pod" -- pg_isready -U airbyte &>/dev/null; then
        echo_info "Database is accepting connections"
    else
        echo_error "Database is not accepting connections"
    fi
}

check_resource_quota() {
    echo ""
    echo "Checking resource quota..."

    if kubectl get resourcequota -n "$NAMESPACE" &>/dev/null; then
        quota=$(kubectl get resourcequota -n "$NAMESPACE" -o json 2>/dev/null)

        if [ -n "$quota" ]; then
            echo_info "Resource quota configured"
            # Could add more detailed quota checks here
        fi
    else
        echo_warn "No resource quota found"
    fi
}

print_summary() {
    echo ""
    echo "========================================="
    if [ $EXIT_CODE -eq 0 ]; then
        echo_info "Health Check PASSED"
    else
        echo_error "Health Check FAILED"
        echo "Review the errors above and check logs:"
        echo "  kubectl logs -n $NAMESPACE deployment/airbyte-server"
        echo "  kubectl logs -n $NAMESPACE deployment/airbyte-worker"
        echo "  kubectl describe pod -n $NAMESPACE <pod-name>"
    fi
    echo "========================================="
    echo ""
}

# Main execution
main() {
    echo "========================================="
    echo "Airbyte Health Check"
    echo "Namespace: $NAMESPACE"
    echo "========================================="
    echo ""

    check_kubectl
    check_namespace
    check_pods
    check_services
    check_statefulsets
    check_pvcs
    check_api_health
    check_database_connectivity
    check_resource_quota
    print_summary

    exit $EXIT_CODE
}

main "$@"
