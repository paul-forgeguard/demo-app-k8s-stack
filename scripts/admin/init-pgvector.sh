#!/usr/bin/env bash
#
# Script: init-pgvector.sh
# Purpose: Initialize pgvector extension in PostgreSQL
# Usage: ./init-pgvector.sh
#

set -euo pipefail

# Source common functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

# ============================================================================
# HELP
# ============================================================================

show_help() {
    print_usage_header "./scripts/admin/init-pgvector.sh" "Initialize pgvector extension in PostgreSQL"

    echo -e "${BOLD}Usage:${NC}"
    echo "  ./scripts/admin/init-pgvector.sh"
    echo ""

    print_common_options

    echo -e "${BOLD}What this does:${NC}"
    echo "  1. Connects to the pgvector pod"
    echo "  2. Runs: CREATE EXTENSION IF NOT EXISTS vector;"
    echo "  3. Verifies the extension is installed"
    echo ""

    echo -e "${BOLD}When to run:${NC}"
    echo "  After deploying the AI stack for the first time"
    echo "  (Step 11 in INSTALLATION-WALKTHROUGH.md)"
    echo ""
}

# ============================================================================
# MAIN
# ============================================================================

main() {
    # Parse args
    if [[ "${1:-}" == "-h" ]] || [[ "${1:-}" == "--help" ]] || [[ "${1:-}" == "help" ]]; then
        show_help
        exit 0
    fi

    log_step "Initializing pgvector extension..."
    echo ""

    # Check prerequisites
    check_microk8s_running || exit 1

    local kubectl
    kubectl=$(get_kubectl)

    # Find pgvector pod
    local pod_name
    pod_name=$(get_pod_name "pgvector")

    if [[ -z "$pod_name" ]]; then
        log_error "pgvector pod not found!"
        echo ""
        log_error "Current pods:"
        $kubectl get pods -n "$AI_NAMESPACE" --no-headers 2>/dev/null || echo "  No pods found"
        echo ""
        log_info "Deploy the AI stack first:"
        echo "  ./scripts/admin/deploy.sh apply"
        exit 1
    fi

    log_info "Found pod: $pod_name"

    # Check if pod is running
    local pod_status
    pod_status=$($kubectl get pod -n "$AI_NAMESPACE" "$pod_name" -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")

    if [[ "$pod_status" != "Running" ]]; then
        log_error "pgvector pod is not running (status: $pod_status)"
        echo ""
        log_info "Wait for it to start, then try again"
        echo "  $kubectl get pods -n $AI_NAMESPACE -w"
        exit 1
    fi

    # Create extension
    log_info "Creating pgvector extension..."
    echo ""

    if $kubectl exec -it -n "$AI_NAMESPACE" "$pod_name" -- \
        psql -U openwebui -d openwebui -c "CREATE EXTENSION IF NOT EXISTS vector;"; then

        echo ""
        log_success "Extension created (or already exists)"

        # Verify
        echo ""
        log_info "Verifying extension installation..."
        echo ""
        $kubectl exec -it -n "$AI_NAMESPACE" "$pod_name" -- \
            psql -U openwebui -d openwebui -c "\\dx"

        echo ""
        log_success "pgvector extension initialized!"
        echo ""
        log_info "The 'vector' extension should appear in the list above."
    else
        log_error "Failed to create extension"
        echo ""
        log_info "Check pgvector logs for errors:"
        echo "  ./scripts/admin/logs.sh pgvector"
        exit 1
    fi
}

main "$@"
