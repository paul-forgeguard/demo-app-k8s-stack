#!/usr/bin/env bash
#
# Script: restart.sh
# Purpose: Restart an application deployment/statefulset
# Usage: ./restart.sh <app-name>
#

set -euo pipefail

# Source common functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

# ============================================================================
# HELP
# ============================================================================

show_help() {
    print_usage_header "./scripts/admin/restart.sh" "Restart an application (rolling restart)"

    echo -e "${BOLD}Usage:${NC}"
    echo "  ./scripts/admin/restart.sh <app-name>"
    echo ""

    echo -e "${BOLD}Arguments:${NC}"
    echo "  app-name        Name of the application to restart"
    echo ""

    print_common_options

    echo -e "${BOLD}Available apps:${NC}"
    for app in "${AVAILABLE_APPS[@]}"; do
        echo "  - $app"
    done
    echo ""

    echo -e "${BOLD}Examples:${NC}"
    echo "  ./scripts/admin/restart.sh openwebui"
    echo "  ./scripts/admin/restart.sh pgvector"
    echo ""

    echo -e "${BOLD}Notes:${NC}"
    echo "  - Uses 'kubectl rollout restart' for zero-downtime restarts"
    echo "  - Works with both Deployments and StatefulSets"
    echo "  - StatefulSets (pgvector, redis) may have brief downtime"
    echo ""
}

# ============================================================================
# MAIN
# ============================================================================

main() {
    local app_name=""

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help|help)
                show_help
                exit 0
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
        show_available_apps
        show_help
        exit 1
    fi

    if ! is_valid_app "$app_name"; then
        log_error "Invalid app name: $app_name"
        echo ""
        show_available_apps
        exit 1
    fi

    # Check prerequisites
    check_microk8s_running || exit 1

    local kubectl
    kubectl=$(get_kubectl)

    log_step "Restarting $app_name..."

    # Check if it's a Deployment or StatefulSet
    if $kubectl get deployment -n "$AI_NAMESPACE" "$app_name" &>/dev/null; then
        log_info "Found Deployment: $app_name"
        if $kubectl rollout restart -n "$AI_NAMESPACE" deployment/"$app_name"; then
            echo ""
            log_success "Restart initiated for deployment/$app_name"
            echo ""
            log_info "Watch rollout status with:"
            echo "  $kubectl rollout status -n $AI_NAMESPACE deployment/$app_name"
        else
            log_error "Failed to restart deployment/$app_name"
            exit 1
        fi

    elif $kubectl get statefulset -n "$AI_NAMESPACE" "$app_name" &>/dev/null; then
        log_info "Found StatefulSet: $app_name"
        log_warn "StatefulSets may have brief downtime during restart"

        if $kubectl rollout restart -n "$AI_NAMESPACE" statefulset/"$app_name"; then
            echo ""
            log_success "Restart initiated for statefulset/$app_name"
            echo ""
            log_info "Watch rollout status with:"
            echo "  $kubectl rollout status -n $AI_NAMESPACE statefulset/$app_name"
        else
            log_error "Failed to restart statefulset/$app_name"
            exit 1
        fi

    else
        log_error "No deployment or statefulset found for: $app_name"
        echo ""
        log_info "Current deployments in '$AI_NAMESPACE':"
        $kubectl get deployments -n "$AI_NAMESPACE" --no-headers 2>/dev/null || echo "  None found"
        echo ""
        log_info "Current statefulsets in '$AI_NAMESPACE':"
        $kubectl get statefulsets -n "$AI_NAMESPACE" --no-headers 2>/dev/null || echo "  None found"
        echo ""
        exit 1
    fi
}

main "$@"
