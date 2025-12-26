#!/usr/bin/env bash
#
# Script: status.sh
# Purpose: Show status of all resources in the AI namespace
# Usage: ./status.sh [--pods|--services|--ingress|--pvc|--events]
#

set -euo pipefail

# Source common functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

# ============================================================================
# HELP
# ============================================================================

show_help() {
    print_usage_header "./scripts/admin/status.sh" "Show status of Kubernetes resources"

    echo -e "${BOLD}Commands:${NC}"
    echo "  (none)          Show all status (default)"
    echo "  pods            Show pods only"
    echo "  services        Show services only"
    echo "  ingress         Show ingress only"
    echo "  pvc             Show persistent volume claims only"
    echo "  events          Show recent events only"
    echo "  certificates    Show TLS certificates"
    echo ""

    print_common_options

    echo -e "${BOLD}Examples:${NC}"
    echo "  ./scripts/admin/status.sh"
    echo "  ./scripts/admin/status.sh pods"
    echo "  ./scripts/admin/status.sh events"
    echo ""
}

# ============================================================================
# FUNCTIONS
# ============================================================================

show_pods() {
    local kubectl
    kubectl=$(get_kubectl)

    print_header "Pods"
    $kubectl get pods -n "$AI_NAMESPACE" -o wide 2>/dev/null || echo "  No pods found"
}

show_services() {
    local kubectl
    kubectl=$(get_kubectl)

    print_header "Services"
    $kubectl get svc -n "$AI_NAMESPACE" 2>/dev/null || echo "  No services found"
}

show_ingress() {
    local kubectl
    kubectl=$(get_kubectl)

    print_header "Ingress"
    $kubectl get ingress -n "$AI_NAMESPACE" 2>/dev/null || echo "  No ingress found"
}

show_pvc() {
    local kubectl
    kubectl=$(get_kubectl)

    print_header "PersistentVolumeClaims"
    $kubectl get pvc -n "$AI_NAMESPACE" 2>/dev/null || echo "  No PVCs found"
}

show_events() {
    local kubectl
    kubectl=$(get_kubectl)

    print_header "Recent Events (last 10)"
    $kubectl get events -n "$AI_NAMESPACE" --sort-by='.lastTimestamp' 2>/dev/null | tail -10 || echo "  No events found"
}

show_certificates() {
    local kubectl
    kubectl=$(get_kubectl)

    print_header "TLS Certificates"
    $kubectl get certificates -A 2>/dev/null || echo "  No certificates found (cert-manager may not be configured)"
}

show_all() {
    local kubectl
    kubectl=$(get_kubectl)

    echo ""
    echo -e "${BOLD}VX Home AI Stack Status${NC}"
    echo "════════════════════════════════════════════════════"
    echo ""

    show_pods
    echo ""
    show_services
    echo ""
    show_ingress
    echo ""
    show_pvc
    echo ""
    show_events
    echo ""

    # Summary
    print_header "Summary"
    local running_pods=$($kubectl get pods -n "$AI_NAMESPACE" --no-headers 2>/dev/null | grep -c "Running" || echo "0")
    local total_pods=$($kubectl get pods -n "$AI_NAMESPACE" --no-headers 2>/dev/null | wc -l || echo "0")
    local bound_pvcs=$($kubectl get pvc -n "$AI_NAMESPACE" --no-headers 2>/dev/null | grep -c "Bound" || echo "0")
    local total_pvcs=$($kubectl get pvc -n "$AI_NAMESPACE" --no-headers 2>/dev/null | wc -l || echo "0")

    echo "  Pods:    $running_pods/$total_pods running"
    echo "  PVCs:    $bound_pvcs/$total_pvcs bound"

    if [[ "$running_pods" -eq "$total_pods" ]] && [[ "$total_pods" -gt 0 ]]; then
        echo ""
        log_success "All pods are running!"
    elif [[ "$total_pods" -eq 0 ]]; then
        echo ""
        log_warn "No pods deployed yet. Run: ./scripts/admin/deploy.sh apply"
    else
        echo ""
        log_warn "Some pods are not running. Check events for details."
    fi
    echo ""
}

# ============================================================================
# MAIN
# ============================================================================

main() {
    local command="${1:-all}"

    # Parse common args
    parse_common_args "$@" || {
        if [[ $? -eq 2 ]]; then
            show_help
            exit 0
        fi
    }

    # Check prerequisites
    check_microk8s_running || exit 1

    case "$command" in
        all|"")
            show_all
            ;;
        pods)
            show_pods
            ;;
        services|svc)
            show_services
            ;;
        ingress|ing)
            show_ingress
            ;;
        pvc|pvcs)
            show_pvc
            ;;
        events)
            show_events
            ;;
        certificates|certs)
            show_certificates
            ;;
        -h|--help|help)
            show_help
            ;;
        *)
            log_error "Unknown command: $command"
            show_help
            exit 1
            ;;
    esac
}

main "$@"
