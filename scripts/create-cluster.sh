#!/bin/bash

# Create GKE Cluster with Workload Identity for Airbyte
# This script creates a GKE cluster and configures Workload Identity

set -e

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
PROJECT_ID="${PROJECT_ID:-}"
CLUSTER_NAME="${CLUSTER_NAME:-airbyte-cluster}"
ZONE="${ZONE:-us-central1-a}"
MACHINE_TYPE="${MACHINE_TYPE:-n1-standard-4}"
NUM_NODES="${NUM_NODES:-3}"
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

    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        echo_error "gcloud CLI not found. Please install it: https://cloud.google.com/sdk/docs/install"
        exit 1
    fi

    # Check if kubectl is installed
    if ! command -v kubectl &> /dev/null; then
        echo_error "kubectl not found. Please install it: https://kubernetes.io/docs/tasks/tools/"
        exit 1
    fi

    # Check if PROJECT_ID is set
    if [ -z "$PROJECT_ID" ]; then
        echo_error "PROJECT_ID environment variable not set"
        echo "Usage: export PROJECT_ID='your-project-id' && ./scripts/create-cluster.sh"
        exit 1
    fi

    # Set gcloud project
    gcloud config set project "$PROJECT_ID"

    echo_info "Prerequisites check passed"
}

check_existing_cluster() {
    echo_info "Checking for existing cluster..."

    if gcloud container clusters describe "$CLUSTER_NAME" --zone="$ZONE" &>/dev/null; then
        echo_warn "Cluster '$CLUSTER_NAME' already exists in zone '$ZONE'"
        read -p "Do you want to delete it and create a new one? (yes/no): " confirm
        if [ "$confirm" = "yes" ]; then
            echo_info "Deleting existing cluster..."
            gcloud container clusters delete "$CLUSTER_NAME" --zone="$ZONE" --quiet
            echo_info "Cluster deleted"
        else
            echo_info "Using existing cluster"
            return 0
        fi
    fi
}

create_cluster() {
    echo_info "Creating GKE cluster '$CLUSTER_NAME'..."

    gcloud container clusters create "$CLUSTER_NAME" \
        --zone="$ZONE" \
        --machine-type="$MACHINE_TYPE" \
        --num-nodes="$NUM_NODES" \
        --enable-cloud-logging \
        --enable-cloud-monitoring \
        --enable-ip-alias \
        --network="default" \
        --subnetwork="default" \
        --workload-pool="$PROJECT_ID.svc.id.goog" \
        --enable-stackdriver-kubernetes \
        --addons=HorizontalPodAutoscaling,HttpLoadBalancing,GcePersistentDiskCsiDriver \
        --no-enable-basic-auth \
        --no-issue-client-certificate \
        --enable-autorepair \
        --enable-autoupgrade

    echo_info "Cluster created successfully"
}

get_credentials() {
    echo_info "Getting cluster credentials..."

    gcloud container clusters get-credentials "$CLUSTER_NAME" --zone="$ZONE"

    # Verify access
    kubectl cluster-info

    echo_info "Credentials configured"
}

create_google_service_account() {
    echo_info "Creating Google Service Account..."

    # Check if GSA exists
    if gcloud iam service-accounts describe "${GSA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com" &>/dev/null; then
        echo_warn "Google Service Account already exists"
    else
        gcloud iam service-accounts create "$GSA_NAME" \
            --display-name="Airbyte GKE Service Account"
        echo_info "Google Service Account created"
    fi
}

configure_workload_identity() {
    echo_info "Configuring Workload Identity..."

    # Bind Kubernetes SA to Google SA
    gcloud iam service-accounts add-iam-policy-binding \
        "${GSA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com" \
        --role roles/iam.workloadIdentityUser \
        --member "serviceAccount:${PROJECT_ID}.svc.id.goog[${NAMESPACE}/${KSA_NAME}]"

    echo_info "Workload Identity configured"
}

grant_permissions() {
    echo_info "Granting GCP permissions to service account..."

    # Example: Grant storage admin role (uncomment if using GCS)
    # gcloud projects add-iam-policy-binding "$PROJECT_ID" \
    #     --member="serviceAccount:${GSA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com" \
    #     --role="roles/storage.objectAdmin"

    echo_info "Permissions configured (customize as needed)"
}

print_summary() {
    echo ""
    echo_info "========================================="
    echo_info "GKE Cluster Created Successfully!"
    echo_info "========================================="
    echo ""
    echo_info "Cluster Name: $CLUSTER_NAME"
    echo_info "Zone: $ZONE"
    echo_info "Project: $PROJECT_ID"
    echo_info "Machine Type: $MACHINE_TYPE"
    echo_info "Number of Nodes: $NUM_NODES"
    echo ""
    echo_info "Google Service Account: ${GSA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"
    echo_info "Kubernetes Service Account: $KSA_NAME (namespace: $NAMESPACE)"
    echo ""
    echo_info "Next Steps:"
    echo "  1. Deploy Airbyte:"
    echo "     kubectl apply -f k8s/namespace.yaml"
    echo "     kubectl apply -f k8s/workload-identity.yaml"
    echo "     kubectl apply -f k8s/secrets.yaml"
    echo "     kubectl apply -f k8s/resource-quota.yaml"
    echo "     kubectl apply -f k8s/airbyte/optional/postgres.yaml"
    echo "     kubectl apply -f k8s/airbyte/"
    echo ""
    echo "  2. Check pod status:"
    echo "     kubectl get pods -n airbyte -w"
    echo ""
    echo "  3. Access Airbyte:"
    echo "     kubectl port-forward -n airbyte svc/airbyte-webapp-svc 8000:8000"
    echo "     Open http://localhost:8000"
    echo ""
}

# Main execution
main() {
    echo_info "Starting GKE cluster creation for Airbyte..."
    echo ""

    check_prerequisites
    check_existing_cluster
    create_cluster
    get_credentials
    create_google_service_account
    configure_workload_identity
    grant_permissions
    print_summary

    echo_info "Done!"
}

main "$@"
