#!/bin/bash

# Cleanup Airbyte Resources
# This script removes Airbyte deployments and optionally the GKE cluster

set -e

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Configuration
PROJECT_ID="${PROJECT_ID:-}"
CLUSTER_NAME="${CLUSTER_NAME:-airbyte-cluster}"
ZONE="${ZONE:-us-central1-a}"
NAMESPACE="${NAMESPACE:-airbyte}"
GSA_NAME="${GSA_NAME:-airbyte-gsa}"

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

confirm_action() {
    local message="$1"
    echo_warn "$message"
    read -p "Are you sure? (yes/no): " confirm
    if [ "$confirm" != "yes" ]; then
        echo_info "Operation cancelled"
        exit 0
    fi
}

cleanup_namespace() {
    echo_info "Cleaning up Airbyte namespace..."

    if kubectl get namespace "$NAMESPACE" &>/dev/null; then
        confirm_action "This will delete the '$NAMESPACE' namespace and all resources in it"

        kubectl delete namespace "$NAMESPACE" --wait=true

        echo_info "Namespace '$NAMESPACE' deleted"
    else
        echo_warn "Namespace '$NAMESPACE' not found"
    fi
}

cleanup_google_service_account() {
    if [ -z "$PROJECT_ID" ]; then
        echo_warn "PROJECT_ID not set, skipping Google Service Account cleanup"
        return
    fi

    echo_info "Cleaning up Google Service Account..."

    if gcloud iam service-accounts describe "${GSA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com" &>/dev/null; then
        read -p "Delete Google Service Account ${GSA_NAME}? (yes/no): " confirm
        if [ "$confirm" = "yes" ]; then
            gcloud iam service-accounts delete "${GSA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com" --quiet
            echo_info "Google Service Account deleted"
        else
            echo_info "Keeping Google Service Account"
        fi
    else
        echo_warn "Google Service Account not found"
    fi
}

cleanup_cluster() {
    if [ -z "$PROJECT_ID" ]; then
        echo_warn "PROJECT_ID not set, skipping cluster cleanup"
        return
    fi

    echo ""
    read -p "Do you want to delete the GKE cluster '$CLUSTER_NAME'? (yes/no): " confirm

    if [ "$confirm" != "yes" ]; then
        echo_info "Keeping GKE cluster"
        return
    fi

    echo_info "Deleting GKE cluster..."

    if gcloud container clusters describe "$CLUSTER_NAME" --zone="$ZONE" &>/dev/null; then
        confirm_action "This will delete the cluster '$CLUSTER_NAME' and all its data"

        gcloud container clusters delete "$CLUSTER_NAME" --zone="$ZONE" --quiet

        echo_info "Cluster deleted"
    else
        echo_warn "Cluster '$CLUSTER_NAME' not found"
    fi
}

print_summary() {
    echo ""
    echo_info "========================================="
    echo_info "Cleanup Complete"
    echo_info "========================================="
    echo ""
    echo_info "What was cleaned up:"
    echo "  - Airbyte namespace and all resources"
    echo "  - (Optional) Google Service Account"
    echo "  - (Optional) GKE Cluster"
    echo ""
    echo_info "To redeploy Airbyte:"
    echo "  1. Run: ./scripts/create-cluster.sh"
    echo "  2. Deploy manifests: kubectl apply -f k8s/"
    echo ""
}

# Main execution
main() {
    echo_info "Starting Airbyte cleanup..."
    echo ""

    echo_warn "This script will remove Airbyte resources"
    echo ""

    cleanup_namespace
    cleanup_google_service_account
    cleanup_cluster
    print_summary

    echo_info "Done!"
}

main "$@"
