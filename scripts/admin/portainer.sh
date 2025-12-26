#!/usr/bin/env bash
#
# Script: portainer.sh
# Purpose: Install or uninstall Portainer CE via Helm
# Usage: ./portainer.sh [install|uninstall]
#

set -euo pipefail

# Source common functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

# Portainer configuration
PORTAINER_NAMESPACE="portainer"
PORTAINER_HOSTNAME="ptnr.adm.vx.home"

# ============================================================================
# HELP
# ============================================================================

show_help() {
    print_usage_header "./scripts/admin/portainer.sh" "Install or uninstall Portainer CE"

    echo -e "${BOLD}Commands:${NC}"
    echo "  install         Install Portainer CE via Helm (with TLS)"
    echo "  uninstall       Remove Portainer installation"
    echo "  status          Show Portainer status"
    echo ""

    print_common_options

    echo -e "${BOLD}Examples:${NC}"
    echo "  ./scripts/admin/portainer.sh install"
    echo "  ./scripts/admin/portainer.sh uninstall"
    echo "  ./scripts/admin/portainer.sh status"
    echo ""

    echo -e "${BOLD}Access:${NC}"
    echo "  URL:            https://$PORTAINER_HOSTNAME"
    echo "  First login:    Create admin account (12+ char password)"
    echo ""
}

# ============================================================================
# FUNCTIONS
# ============================================================================

do_install() {
    log_step "Installing Portainer CE via Helm..."
    echo ""

    # Check prerequisites
    check_microk8s_running || exit 1

    local kubectl helm
    kubectl=$(get_kubectl)
    helm=$(get_helm)

    # Check for IngressClass
    local ingress_class
    ingress_class=$($kubectl get ingressclass -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

    if [[ -z "$ingress_class" ]]; then
        log_error "No IngressClass found"
        echo ""
        log_error "Enable the ingress addon first:"
        echo "  microk8s enable ingress"
        echo ""
        exit 1
    fi

    log_info "Using IngressClass: $ingress_class"

    # Add Portainer Helm repo
    log_info "Adding Portainer Helm repository..."
    $helm repo add portainer https://portainer.github.io/k8s/ 2>/dev/null || true
    $helm repo update

    # Install Portainer with TLS
    log_info "Installing Portainer..."
    echo ""

    $helm upgrade --install --create-namespace -n "$PORTAINER_NAMESPACE" portainer portainer/portainer \
        --set service.type=ClusterIP \
        --set tls.force=true \
        --set image.tag=lts \
        --set ingress.enabled=true \
        --set ingress.ingressClassName="$ingress_class" \
        --set ingress.annotations."nginx\.ingress\.kubernetes\.io/backend-protocol"=HTTPS \
        --set ingress.annotations."cert-manager\.io/cluster-issuer"=vx-home-ca-issuer \
        --set ingress.tls[0].secretName=portainer-tls \
        --set ingress.tls[0].hosts[0]="$PORTAINER_HOSTNAME" \
        --set ingress.hosts[0].host="$PORTAINER_HOSTNAME" \
        --set ingress.hosts[0].paths[0].path="/"

    echo ""
    log_success "Portainer installed with TLS!"
    echo ""

    print_header "Access Information"
    echo "  URL:            https://$PORTAINER_HOSTNAME"
    echo ""
    echo "  First time setup:"
    echo "    1. Wait a few moments for the pod to start"
    echo "    2. Visit the URL above"
    echo "    3. Create admin account (password: 12+ characters)"
    echo ""

    log_warn "TLS Note:"
    echo "  The certificate is signed by vx-home-ca-issuer."
    echo "  To avoid browser warnings, trust the CA certificate."
    echo "  See: ./scripts/setup/06-configure-cert-manager.sh for instructions"
    echo ""

    log_info "Check status:"
    echo "  ./scripts/admin/portainer.sh status"
    echo ""
}

do_uninstall() {
    log_step "Uninstalling Portainer..."
    echo ""

    check_microk8s_running || exit 1

    local kubectl helm
    kubectl=$(get_kubectl)
    helm=$(get_helm)

    # Check if installed
    if ! $helm list -n "$PORTAINER_NAMESPACE" 2>/dev/null | grep -q portainer; then
        log_warn "Portainer doesn't appear to be installed via Helm"
        echo ""
        log_info "Checking for namespace..."
        if $kubectl get namespace "$PORTAINER_NAMESPACE" &>/dev/null; then
            log_info "Namespace exists. Attempting cleanup..."
        else
            log_info "Namespace doesn't exist. Nothing to uninstall."
            exit 0
        fi
    fi

    # Confirm
    if ! confirm_action "Uninstall Portainer and delete namespace?"; then
        log_warn "Uninstall cancelled."
        exit 0
    fi

    # Uninstall Helm release
    log_info "Removing Helm release..."
    $helm uninstall portainer -n "$PORTAINER_NAMESPACE" 2>/dev/null || true

    # Delete namespace
    log_info "Deleting namespace..."
    $kubectl delete namespace "$PORTAINER_NAMESPACE" 2>/dev/null || true

    echo ""
    log_success "Portainer uninstalled."
}

do_status() {
    check_microk8s_running || exit 1

    local kubectl
    kubectl=$(get_kubectl)

    print_header "Portainer Status"

    # Check namespace
    if ! $kubectl get namespace "$PORTAINER_NAMESPACE" &>/dev/null; then
        log_warn "Portainer namespace doesn't exist"
        log_info "Install with: ./scripts/admin/portainer.sh install"
        return
    fi

    echo ""
    echo "Pods:"
    $kubectl get pods -n "$PORTAINER_NAMESPACE" -o wide

    echo ""
    echo "Services:"
    $kubectl get svc -n "$PORTAINER_NAMESPACE"

    echo ""
    echo "Ingress:"
    $kubectl get ingress -n "$PORTAINER_NAMESPACE"

    echo ""
    echo "Certificate:"
    $kubectl get certificate -n "$PORTAINER_NAMESPACE" 2>/dev/null || echo "  No certificate found"

    echo ""
    log_info "Access URL: https://$PORTAINER_HOSTNAME"
}

# ============================================================================
# MAIN
# ============================================================================

main() {
    local command="${1:-}"

    # Parse common args
    parse_common_args "$@" || {
        if [[ $? -eq 2 ]]; then
            show_help
            exit 0
        fi
    }

    case "$command" in
        install)
            do_install
            ;;
        uninstall|remove)
            do_uninstall
            ;;
        status)
            do_status
            ;;
        -h|--help|help|"")
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
