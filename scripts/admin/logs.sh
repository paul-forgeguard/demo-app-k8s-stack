#!/usr/bin/env bash
#
# Script: logs.sh
# Purpose: Stream logs from an application pod
# Usage: ./logs.sh <app-name> [--tail N] [--previous]
#

set -euo pipefail

# Source common functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

# ============================================================================
# HELP
# ============================================================================

show_help() {
    print_usage_header "./scripts/admin/logs.sh" "Stream logs from an application pod"

    echo -e "${BOLD}Usage:${NC}"
    echo "  ./scripts/admin/logs.sh <app-name> [OPTIONS]"
    echo ""

    echo -e "${BOLD}Arguments:${NC}"
    echo "  app-name        Name of the application (see available apps below)"
    echo ""

    echo -e "${BOLD}Options:${NC}"
    echo "  -f, --follow    Follow log output (default)"
    echo "  -n, --tail N    Show last N lines (default: all)"
    echo "  -p, --previous  Show logs from previous container instance"
    echo "  -h, --help      Show this help message"
    echo ""

    echo -e "${BOLD}Available apps:${NC}"
    for app in "${AVAILABLE_APPS[@]}"; do
        echo "  - $app"
    done
    echo ""

    echo -e "${BOLD}Examples:${NC}"
    echo "  ./scripts/admin/logs.sh openwebui"
    echo "  ./scripts/admin/logs.sh pgvector --tail 100"
    echo "  ./scripts/admin/logs.sh openwebui --previous"
    echo ""
}

# ============================================================================
# MAIN
# ============================================================================

main() {
    local app_name=""
    local follow="-f"
    local tail_lines=""
    local previous=""

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help|help)
                show_help
                exit 0
                ;;
            -f|--follow)
                follow="-f"
                shift
                ;;
            --no-follow)
                follow=""
                shift
                ;;
            -n|--tail)
                tail_lines="--tail=$2"
                shift 2
                ;;
            -p|--previous)
                previous="--previous"
                shift
                ;;
            -v|--verbose)
                VERBOSE=1
                shift
                ;;
            -*)
                log_error "Unknown option: $1"
                show_help
                exit 1
                ;;
            *)
                if [[ -z "$app_name" ]]; then
                    app_name="$1"
                fi
                shift
                ;;
        esac
    done

    # Validate app name
    if [[ -z "$app_name" ]]; then
        log_error "No app name specified"
        echo ""
        show_help
        exit 1
    fi

    if ! is_valid_app "$app_name"; then
        log_error "Invalid app name: $app_name"
        echo ""
        echo "Available apps:"
        for app in "${AVAILABLE_APPS[@]}"; do
            echo "  - $app"
        done
        echo ""
        exit 1
    fi

    # Check prerequisites
    check_microk8s_running || exit 1

    local kubectl
    kubectl=$(get_kubectl)

    # Get pod name
    local pod_name
    pod_name=$(get_pod_name "$app_name")

    if [[ -z "$pod_name" ]]; then
        log_error "No pod found for app: $app_name"
        echo ""

        # Show current pods for context
        log_info "Current pods in '$AI_NAMESPACE' namespace:"
        $kubectl get pods -n "$AI_NAMESPACE" --no-headers 2>/dev/null || echo "  No pods found"
        echo ""

        log_info "The app may not be deployed yet. Deploy with:"
        echo "  ./scripts/admin/deploy.sh apply"
        echo ""
        exit 1
    fi

    log_info "Streaming logs for: $pod_name"
    log_info "Press Ctrl+C to stop"
    echo ""

    # Stream logs
    $kubectl logs -n "$AI_NAMESPACE" "$pod_name" $follow $tail_lines $previous
}

main "$@"
