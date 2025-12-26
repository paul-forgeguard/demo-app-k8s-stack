#!/usr/bin/env bash
#
# Script: clean.sh
# Purpose: Clean up failed and evicted pods
# Usage: ./clean.sh
#

set -euo pipefail

# Source common functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

# ============================================================================
# HELP
# ============================================================================

show_help() {
    print_usage_header "./scripts/admin/clean.sh" "Clean up failed and evicted pods"

    echo -e "${BOLD}Usage:${NC}"
    echo "  ./scripts/admin/clean.sh"
    echo ""

    print_common_options

    echo -e "${BOLD}What this does:${NC}"
    echo "  1. Deletes pods in 'Failed' state"
    echo "  2. Deletes pods in 'Evicted' state"
    echo "  3. Shows remaining pods"
    echo ""

    echo -e "${BOLD}When to use:${NC}"
    echo "  - After deployments with failed pods"
    echo "  - When disk pressure causes evictions"
    echo "  - General maintenance cleanup"
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

    log_step "Cleaning up failed and evicted pods..."
    echo ""

    check_microk8s_running || exit 1

    local kubectl
    kubectl=$(get_kubectl)

    # Count before
    local failed_count evicted_count

    failed_count=$($kubectl get pods -n "$AI_NAMESPACE" --field-selector=status.phase=Failed --no-headers 2>/dev/null | wc -l || echo "0")
    evicted_count=$($kubectl get pods -n "$AI_NAMESPACE" --no-headers 2>/dev/null | grep -c Evicted || echo "0")

    log_info "Found $failed_count failed pod(s)"
    log_info "Found $evicted_count evicted pod(s)"
    echo ""

    if [[ "$failed_count" -eq 0 ]] && [[ "$evicted_count" -eq 0 ]]; then
        log_success "No pods to clean up!"
        exit 0
    fi

    # Clean failed pods
    if [[ "$failed_count" -gt 0 ]]; then
        log_info "Deleting failed pods..."
        $kubectl delete pod --field-selector=status.phase=Failed -n "$AI_NAMESPACE" 2>/dev/null || true
    fi

    # Clean evicted pods
    if [[ "$evicted_count" -gt 0 ]]; then
        log_info "Deleting evicted pods..."
        $kubectl get pods -n "$AI_NAMESPACE" 2>/dev/null | grep Evicted | awk '{print $1}' | \
            xargs -r $kubectl delete pod -n "$AI_NAMESPACE" 2>/dev/null || true
    fi

    echo ""
    log_success "Cleanup complete!"
    echo ""

    # Show remaining pods
    log_info "Remaining pods:"
    $kubectl get pods -n "$AI_NAMESPACE" --no-headers 2>/dev/null || echo "  No pods found"
    echo ""
}

main "$@"
