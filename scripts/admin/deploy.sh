#!/usr/bin/env bash
#
# Script: deploy.sh
# Purpose: Deploy or delete Kubernetes resources for VX Home AI Stack
# Usage: ./deploy.sh [apply|delete]
#

set -euo pipefail

# Source common functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

# ============================================================================
# HELP
# ============================================================================

show_help() {
    print_usage_header "./scripts/admin/deploy.sh" "Deploy or delete Kubernetes resources for the AI stack"

    echo -e "${BOLD}Commands:${NC}"
    echo "  apply           Deploy all Kubernetes resources"
    echo "  delete          Delete all resources (requires confirmation)"
    echo ""

    print_common_options

    echo -e "${BOLD}Examples:${NC}"
    echo "  ./scripts/admin/deploy.sh apply"
    echo "  ./scripts/admin/deploy.sh delete"
    echo ""
}

# ============================================================================
# FUNCTIONS
# ============================================================================

check_secrets() {
    local secrets_file="$K8S_DIR/apps/ai-stack/secrets.yaml"

    if [[ ! -f "$secrets_file" ]]; then
        log_error "secrets.yaml not found!"
        echo ""
        log_error "Expected location: $secrets_file"
        echo ""
        log_info "To create it, run:"
        echo "  ./scripts/admin/secrets.sh create"
        echo ""
        return 1
    fi

    log_debug "Found secrets.yaml at $secrets_file"
    return 0
}

do_apply() {
    log_step "Deploying Kubernetes resources..."
    echo ""

    # Check prerequisites
    check_microk8s_running || exit 1
    check_secrets || exit 1

    local kubectl
    kubectl=$(get_kubectl)

    # Apply kustomization
    log_info "Applying Kustomize manifests from: $K8S_DIR"
    echo ""

    if $kubectl apply -k "$K8S_DIR"; then
        echo ""
        log_success "Resources deployed successfully!"
        echo ""
        log_info "Check status with:"
        echo "  ./scripts/admin/status.sh"
        echo ""
        log_info "Watch pods start up with:"
        echo "  $kubectl get pods -n $AI_NAMESPACE -w"
        echo ""
    else
        log_error "Deployment failed!"
        echo ""
        log_error "Check for errors above and try again."
        log_error "Common issues:"
        echo "  - Invalid YAML syntax"
        echo "  - Missing secrets or configmaps"
        echo "  - Resource quota exceeded"
        echo ""
        exit 1
    fi
}

do_delete() {
    log_step "Deleting Kubernetes resources..."
    echo ""

    # Check prerequisites
    check_microk8s_running || exit 1

    local kubectl
    kubectl=$(get_kubectl)

    # Warning
    log_warn "This will delete ALL resources in the ai namespace!"
    log_warn "This includes:"
    echo "  - All Deployments and StatefulSets"
    echo "  - All Services"
    echo "  - All PersistentVolumeClaims (DATA WILL BE LOST!)"
    echo "  - All ConfigMaps and Secrets"
    echo ""

    # Show current resources
    log_info "Current resources that will be deleted:"
    $kubectl get all -n "$AI_NAMESPACE" 2>/dev/null || true
    echo ""

    # Confirm
    if ! confirm_action "Are you sure you want to delete all resources?"; then
        log_warn "Deletion cancelled."
        exit 0
    fi

    # Double confirm for data loss
    echo ""
    log_warn "This will permanently delete all data in PersistentVolumes!"
    if ! confirm_action "Type 'yes' to confirm data deletion (yes/NO):"; then
        log_warn "Deletion cancelled."
        exit 0
    fi

    # Delete
    echo ""
    log_info "Deleting resources..."

    if $kubectl delete -k "$K8S_DIR"; then
        echo ""
        log_success "Resources deleted successfully!"
    else
        log_warn "Some resources may not have been deleted."
        log_info "Check remaining resources with:"
        echo "  $kubectl get all -n $AI_NAMESPACE"
    fi
}

# ============================================================================
# MAIN
# ============================================================================

main() {
    local command="${1:-}"

    # Parse common args first
    parse_common_args "$@" || {
        if [[ $? -eq 2 ]]; then
            show_help
            exit 0
        fi
    }

    case "$command" in
        apply)
            do_apply
            ;;
        delete)
            do_delete
            ;;
        -h|--help|help|"")
            show_help
            exit 0
            ;;
        *)
            log_error "Unknown command: $command"
            echo ""
            show_help
            exit 1
            ;;
    esac
}

main "$@"
