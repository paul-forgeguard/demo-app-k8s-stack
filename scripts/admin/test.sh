#!/usr/bin/env bash
#
# Script: test.sh
# Purpose: Test DNS resolution and Ingress endpoints
# Usage: ./test.sh [dns|ingress|all]
#

set -euo pipefail

# Source common functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

# ============================================================================
# HELP
# ============================================================================

show_help() {
    print_usage_header "./scripts/admin/test.sh" "Test DNS resolution and Ingress endpoints"

    echo -e "${BOLD}Commands:${NC}"
    echo "  dns             Test DNS resolution from within cluster"
    echo "  ingress         Test Ingress endpoints"
    echo "  tls             Test TLS certificates"
    echo "  all             Run all tests (default)"
    echo ""

    print_common_options

    echo -e "${BOLD}Examples:${NC}"
    echo "  ./scripts/admin/test.sh"
    echo "  ./scripts/admin/test.sh dns"
    echo "  ./scripts/admin/test.sh ingress"
    echo ""
}

# ============================================================================
# FUNCTIONS
# ============================================================================

test_dns() {
    print_header "Testing DNS Resolution"

    check_microk8s_running || return 1

    local kubectl
    kubectl=$(get_kubectl)

    log_info "Launching temporary busybox pod for DNS testing..."
    echo ""

    local services=("pgvector" "redis" "openwebui" "kokoro" "faster-whisper")

    echo "Testing DNS resolution for services in '$AI_NAMESPACE' namespace:"
    echo ""

    # Run DNS lookups
    for svc in "${services[@]}"; do
        echo -n "  $svc: "
        if $kubectl run -it --rm dns-test-$$ --image=busybox --restart=Never -n "$AI_NAMESPACE" \
            -- nslookup "$svc" 2>/dev/null | grep -q "Address"; then
            echo -e "${GREEN}OK${NC}"
        else
            echo -e "${YELLOW}NOT FOUND${NC}"
        fi
    done 2>/dev/null || {
        log_warn "DNS test pod may have failed. Trying alternative method..."
        echo ""
        # Alternative: check if services exist
        for svc in "${services[@]}"; do
            echo -n "  $svc service: "
            if $kubectl get svc -n "$AI_NAMESPACE" "$svc" &>/dev/null; then
                echo -e "${GREEN}EXISTS${NC}"
            else
                echo -e "${YELLOW}NOT FOUND${NC}"
            fi
        done
    }

    echo ""
}

test_ingress() {
    print_header "Testing Ingress Endpoints"

    local node_ip
    node_ip=$(get_node_ip)

    log_info "Node IP: $node_ip"
    echo ""

    # Endpoints to test
    local -a endpoints=(
        "ai.adm.vx.home|Open WebUI"
        "control.adm.vx.home|Control Portal"
        "control.adm.vx.home/pgadmin|pgAdmin"
        "ptnr.adm.vx.home|Portainer"
    )

    echo "Testing HTTP endpoints (via Ingress):"
    echo ""

    for endpoint in "${endpoints[@]}"; do
        local host="${endpoint%%|*}"
        local name="${endpoint##*|}"

        echo -n "  $name ($host): "

        # Test HTTP
        local status
        status=$(curl -sI -H "Host: $host" "http://$node_ip" 2>/dev/null | head -1 | awk '{print $2}') || status="FAIL"

        if [[ "$status" =~ ^[23] ]]; then
            echo -e "${GREEN}HTTP $status${NC}"
        elif [[ "$status" == "FAIL" ]]; then
            echo -e "${RED}Connection failed${NC}"
        else
            echo -e "${YELLOW}HTTP $status${NC}"
        fi
    done

    echo ""
    log_info "Testing HTTPS endpoints:"
    echo ""

    for endpoint in "${endpoints[@]}"; do
        local host="${endpoint%%|*}"
        local name="${endpoint##*|}"

        echo -n "  $name (https://$host): "

        # Test HTTPS (ignore cert errors for self-signed)
        local status
        status=$(curl -skI "https://$host" 2>/dev/null | head -1 | awk '{print $2}') || status="FAIL"

        if [[ "$status" =~ ^[23] ]]; then
            echo -e "${GREEN}HTTPS $status${NC}"
        elif [[ "$status" == "FAIL" ]]; then
            echo -e "${RED}Connection failed${NC}"
        else
            echo -e "${YELLOW}HTTPS $status${NC}"
        fi
    done

    echo ""
}

test_tls() {
    print_header "Testing TLS Certificates"

    check_microk8s_running || return 1

    local kubectl
    kubectl=$(get_kubectl)

    log_info "Checking cert-manager certificates:"
    echo ""

    $kubectl get certificates -A 2>/dev/null || {
        log_warn "No certificates found or cert-manager not configured"
        return 1
    }

    echo ""
    log_info "Checking ClusterIssuers:"
    echo ""

    $kubectl get clusterissuers 2>/dev/null || {
        log_warn "No ClusterIssuers found"
    }

    echo ""
}

test_all() {
    test_dns
    test_ingress
    test_tls

    print_header "Summary"

    log_info "All tests completed."
    echo ""
    log_info "If endpoints are not accessible:"
    echo "  1. Check DNS entries in /etc/hosts"
    echo "  2. Check Ingress controller: microk8s kubectl get pods -n ingress"
    echo "  3. Check firewall: firewall-cmd --list-all"
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

    case "$command" in
        dns)
            test_dns
            ;;
        ingress|ing)
            test_ingress
            ;;
        tls|certs|certificates)
            test_tls
            ;;
        all|"")
            test_all
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
