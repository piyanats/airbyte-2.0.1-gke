#!/bin/bash

# Setup Workload Identity for Airbyte
# Configures binding between Kubernetes SA and Google SA

set -e

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Configuration
PROJECT_ID="${PROJECT_ID:-}"
NAMESPACE="${NAMESPACE:-airbyte}"
KSA_NAME="${KSA_NAME:-airbyte-sa}"
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

check_prerequisites() {
    echo_info "Checking prerequisites..."

    if [ -z "$PROJECT_ID" ]; then
        echo_error "PROJECT_ID environment variable not set"
        echo "Usage: export PROJECT_ID='your-project-id' && ./scripts/setup-workload-identity.sh"
        exit 1
    fi

    if ! command -v gcloud &> /dev/null; then
        echo_error "gcloud CLI not found"
        exit 1
    fi

    if ! command -v kubectl &> /dev/null; then
        echo_error "kubectl not found"
        exit 1
    fi

    gcloud config set project "$PROJECT_ID"

    echo_info "Prerequisites check passed"
}

create_google_service_account() {
    echo_info "Creating Google Service Account..."

    if gcloud iam service-accounts describe "${GSA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com" &>/dev/null; then
        echo_warn "Google Service Account already exists"
    else
        gcloud iam service-accounts create "$GSA_NAME" \
            --display-name="Airbyte GKE Service Account" \
            --project="$PROJECT_ID"

        echo_info "Google Service Account created"
    fi
}

create_kubernetes_service_account() {
    echo_info "Creating Kubernetes Service Account..."

    if kubectl get serviceaccount "$KSA_NAME" -n "$NAMESPACE" &>/dev/null; then
        echo_warn "Kubernetes Service Account already exists"
    else
        # Apply workload-identity.yaml which creates the KSA
        kubectl apply -f k8s/workload-identity.yaml

        echo_info "Kubernetes Service Account created"
    fi
}

bind_service_accounts() {
    echo_info "Binding Kubernetes SA to Google SA..."

    gcloud iam service-accounts add-iam-policy-binding \
        "${GSA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com" \
        --role roles/iam.workloadIdentityUser \
        --member "serviceAccount:${PROJECT_ID}.svc.id.goog[${NAMESPACE}/${KSA_NAME}]" \
        --project="$PROJECT_ID"

    echo_info "Service accounts bound successfully"
}

annotate_ksa() {
    echo_info "Annotating Kubernetes Service Account..."

    kubectl annotate serviceaccount "$KSA_NAME" \
        -n "$NAMESPACE" \
        iam.gke.io/gcp-service-account="${GSA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com" \
        --overwrite

    echo_info "Annotation applied"
}

grant_gcp_permissions() {
    echo_info "Granting GCP permissions..."

    echo_warn "Add any additional GCP permissions as needed. Examples:"
    echo ""
    echo "# For GCS access:"
    echo "gcloud projects add-iam-policy-binding $PROJECT_ID \\"
    echo "    --member=\"serviceAccount:${GSA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com\" \\"
    echo "    --role=\"roles/storage.objectAdmin\""
    echo ""
    echo "# For Cloud SQL access:"
    echo "gcloud projects add-iam-policy-binding $PROJECT_ID \\"
    echo "    --member=\"serviceAccount:${GSA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com\" \\"
    echo "    --role=\"roles/cloudsql.client\""
    echo ""
}

print_summary() {
    echo ""
    echo_info "========================================="
    echo_info "Workload Identity Setup Complete!"
    echo_info "========================================="
    echo ""
    echo_info "Configuration:"
    echo "  Project: $PROJECT_ID"
    echo "  Namespace: $NAMESPACE"
    echo "  KSA: $KSA_NAME"
    echo "  GSA: ${GSA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"
    echo ""
    echo_info "Pods using the '$KSA_NAME' service account can now"
    echo_info "authenticate to Google Cloud services without keys!"
    echo ""
}

# Main execution
main() {
    echo_info "Setting up Workload Identity for Airbyte..."
    echo ""

    check_prerequisites
    create_google_service_account
    create_kubernetes_service_account
    bind_service_accounts
    annotate_ksa
    grant_gcp_permissions
    print_summary

    echo_info "Done!"
}

main "$@"
