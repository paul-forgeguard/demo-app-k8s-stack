#!/usr/bin/env bash
#
# Script: verify-cluster.sh
# Purpose: Comprehensive cluster health check
# Author: VX Home Infrastructure
#

set -euo pipefail

# Source common functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

# Track results
declare -A COMPONENT_STATUS

check_component() {
    local name="$1"
    local status="$2"
    COMPONENT_STATUS["$name"]="$status"
}

print_status_line() {
    local name="$1"
    local status="$2"
    local details="${3:-}"

    if [[ "$status" == "ok" ]]; then
        printf "  ${GREEN}✓${NC} %-25s %s\n" "$name" "$details"
    elif [[ "$status" == "warn" ]]; then
        printf "  ${YELLOW}!${NC} %-25s %s\n" "$name" "$details"
    else
        printf "  ${RED}✗${NC} %-25s %s\n" "$name" "$details"
    fi
}

print_header "VX Home Cluster Verification"

# Get kubectl command
KUBECTL=$(get_kubectl) || exit 1

echo ""

# ============================================================================
# MicroK8s Status
# ============================================================================

log_step "MicroK8s Status"

if microk8s status 2>/dev/null | grep -q "microk8s is running"; then
    print_status_line "MicroK8s" "ok" "running"
    check_component "microk8s" "ok"
else
    print_status_line "MicroK8s" "fail" "not running"
    check_component "microk8s" "fail"
fi

# Node status
NODE_STATUS=$($KUBECTL get nodes --no-headers 2>/dev/null | awk '{print $2}')
if [[ "$NODE_STATUS" == "Ready" ]]; then
    NODE_NAME=$($KUBECTL get nodes --no-headers 2>/dev/null | awk '{print $1}')
    print_status_line "Node" "ok" "$NODE_NAME"
    check_component "node" "ok"
else
    print_status_line "Node" "fail" "$NODE_STATUS"
    check_component "node" "fail"
fi

echo ""

# ============================================================================
# Core Addons
# ============================================================================

log_step "Core Addons"

# DNS
if $KUBECTL get pods -n kube-system -l k8s-app=kube-dns --no-headers 2>/dev/null | grep -q Running; then
    print_status_line "DNS (CoreDNS)" "ok" "running"
    check_component "dns" "ok"
else
    print_status_line "DNS (CoreDNS)" "fail" "not running"
    check_component "dns" "fail"
fi

# Ingress
INGRESS_PODS=$($KUBECTL get pods -n ingress --no-headers 2>/dev/null | grep -c Running || echo "0")
if [[ "$INGRESS_PODS" -gt 0 ]]; then
    print_status_line "Ingress Controller" "ok" "$INGRESS_PODS pod(s)"
    check_component "ingress" "ok"
else
    print_status_line "Ingress Controller" "fail" "no running pods"
    check_component "ingress" "fail"
fi

# cert-manager
if $KUBECTL get pods -n cert-manager --no-headers 2>/dev/null | grep -q Running; then
    print_status_line "cert-manager" "ok" "running"
    check_component "cert-manager" "ok"
else
    print_status_line "cert-manager" "warn" "not running"
    check_component "cert-manager" "warn"
fi

echo ""

# ============================================================================
# Storage
# ============================================================================

log_step "Storage"

# Check hostpath-storage
if $KUBECTL get sc microk8s-hostpath &>/dev/null; then
    print_status_line "hostpath-storage" "ok" "available"
    check_component "hostpath" "ok"
else
    print_status_line "hostpath-storage" "warn" "not available"
    check_component "hostpath" "warn"
fi

# Check MicroCeph / rook-ceph
if $KUBECTL get sc ceph-rbd &>/dev/null; then
    print_status_line "ceph-rbd" "ok" "available"
    check_component "ceph-rbd" "ok"
else
    print_status_line "ceph-rbd" "warn" "not available"
    check_component "ceph-rbd" "warn"
fi

if $KUBECTL get sc cephfs &>/dev/null; then
    print_status_line "cephfs" "ok" "available"
    check_component "cephfs" "ok"
else
    print_status_line "cephfs" "warn" "not available"
    check_component "cephfs" "warn"
fi

# MicroCeph status (if installed)
if command -v microceph &>/dev/null; then
    CEPH_HEALTH=$(microceph.ceph health 2>/dev/null || echo "ERROR")
    if [[ "$CEPH_HEALTH" == "HEALTH_OK" ]]; then
        print_status_line "MicroCeph" "ok" "$CEPH_HEALTH"
        check_component "microceph" "ok"
    elif [[ "$CEPH_HEALTH" == "HEALTH_WARN" ]]; then
        print_status_line "MicroCeph" "warn" "$CEPH_HEALTH"
        check_component "microceph" "warn"
    else
        print_status_line "MicroCeph" "fail" "$CEPH_HEALTH"
        check_component "microceph" "fail"
    fi
fi

echo ""

# ============================================================================
# Vault
# ============================================================================

log_step "HashiCorp Vault"

if $KUBECTL get namespace vault &>/dev/null; then
    # Check pod
    VAULT_POD_STATUS=$($KUBECTL get pod vault-0 -n vault -o jsonpath='{.status.phase}' 2>/dev/null || echo "NotFound")

    if [[ "$VAULT_POD_STATUS" == "Running" ]]; then
        # Check sealed status
        VAULT_STATUS=$($KUBECTL exec -n vault vault-0 -- vault status -format=json 2>/dev/null || echo '{"sealed": true}')
        SEALED=$(echo "$VAULT_STATUS" | jq -r '.sealed')

        if [[ "$SEALED" == "false" ]]; then
            print_status_line "Vault" "ok" "running, unsealed"
            check_component "vault" "ok"
        else
            print_status_line "Vault" "warn" "running, SEALED"
            check_component "vault" "warn"
        fi
    else
        print_status_line "Vault" "fail" "pod: $VAULT_POD_STATUS"
        check_component "vault" "fail"
    fi

    # Check injector
    INJECTOR_STATUS=$($KUBECTL get pods -n vault -l app.kubernetes.io/name=vault-agent-injector --no-headers 2>/dev/null | grep -c Running || echo "0")
    if [[ "$INJECTOR_STATUS" -gt 0 ]]; then
        print_status_line "Vault Agent Injector" "ok" "running"
        check_component "vault-injector" "ok"
    else
        print_status_line "Vault Agent Injector" "warn" "not running"
        check_component "vault-injector" "warn"
    fi
else
    print_status_line "Vault" "warn" "not installed"
    check_component "vault" "warn"
fi

echo ""

# ============================================================================
# GPU
# ============================================================================

log_step "GPU Support"

if $KUBECTL get namespace gpu-operator &>/dev/null; then
    GPU_PODS=$($KUBECTL get pods -n gpu-operator --no-headers 2>/dev/null | grep -c Running || echo "0")
    if [[ "$GPU_PODS" -gt 0 ]]; then
        print_status_line "GPU Operator" "ok" "$GPU_PODS pod(s)"
        check_component "gpu-operator" "ok"
    else
        print_status_line "GPU Operator" "warn" "no running pods"
        check_component "gpu-operator" "warn"
    fi

    # Check for GPU nodes
    GPU_NODES=$($KUBECTL get nodes -o jsonpath='{.items[*].status.allocatable.nvidia\.com/gpu}' 2>/dev/null | tr ' ' '\n' | grep -v '^$' | wc -l || echo "0")
    if [[ "$GPU_NODES" -gt 0 ]]; then
        GPU_COUNT=$($KUBECTL get nodes -o jsonpath='{.items[0].status.allocatable.nvidia\.com/gpu}' 2>/dev/null || echo "0")
        print_status_line "GPU Resources" "ok" "$GPU_COUNT GPU(s) available"
        check_component "gpu" "ok"
    else
        print_status_line "GPU Resources" "warn" "none detected"
        check_component "gpu" "warn"
    fi
else
    print_status_line "GPU Operator" "warn" "not installed"
    check_component "gpu-operator" "warn"
fi

echo ""

# ============================================================================
# AI Stack Applications
# ============================================================================

log_step "AI Stack (namespace: ai)"

for app in openwebui pgvector redis kokoro faster-whisper; do
    POD_STATUS=$($KUBECTL get pods -n ai -l app=$app --no-headers 2>/dev/null | head -1)

    if [[ -n "$POD_STATUS" ]]; then
        STATUS=$(echo "$POD_STATUS" | awk '{print $3}')
        READY=$(echo "$POD_STATUS" | awk '{print $2}')

        if [[ "$STATUS" == "Running" ]]; then
            print_status_line "$app" "ok" "$READY ready"
            check_component "$app" "ok"
        else
            print_status_line "$app" "warn" "$STATUS ($READY)"
            check_component "$app" "warn"
        fi
    else
        print_status_line "$app" "warn" "not deployed"
        check_component "$app" "warn"
    fi
done

echo ""

# ============================================================================
# Ingress Endpoints
# ============================================================================

log_step "Ingress Endpoints"

INGRESSES=$($KUBECTL get ingress -A --no-headers 2>/dev/null)

if [[ -n "$INGRESSES" ]]; then
    while IFS= read -r line; do
        NS=$(echo "$line" | awk '{print $1}')
        NAME=$(echo "$line" | awk '{print $2}')
        HOSTS=$(echo "$line" | awk '{print $4}')

        print_status_line "$NAME" "ok" "$HOSTS"
    done <<< "$INGRESSES"
else
    print_status_line "Ingresses" "warn" "none configured"
fi

echo ""

# ============================================================================
# PVC Status
# ============================================================================

log_step "Persistent Volume Claims (ai namespace)"

PVCS=$($KUBECTL get pvc -n ai --no-headers 2>/dev/null)

if [[ -n "$PVCS" ]]; then
    while IFS= read -r line; do
        NAME=$(echo "$line" | awk '{print $1}')
        STATUS=$(echo "$line" | awk '{print $2}')
        CAPACITY=$(echo "$line" | awk '{print $4}')
        SC=$(echo "$line" | awk '{print $6}')

        if [[ "$STATUS" == "Bound" ]]; then
            print_status_line "$NAME" "ok" "$CAPACITY ($SC)"
        else
            print_status_line "$NAME" "warn" "$STATUS"
        fi
    done <<< "$PVCS"
else
    print_status_line "PVCs" "warn" "none found"
fi

echo ""

# ============================================================================
# Summary
# ============================================================================

print_header "Summary"

OK_COUNT=0
WARN_COUNT=0
FAIL_COUNT=0

for component in "${!COMPONENT_STATUS[@]}"; do
    case "${COMPONENT_STATUS[$component]}" in
        ok) ((OK_COUNT++)) ;;
        warn) ((WARN_COUNT++)) ;;
        fail) ((FAIL_COUNT++)) ;;
    esac
done

echo ""
printf "  ${GREEN}✓ OK:${NC}     %d components\n" "$OK_COUNT"
printf "  ${YELLOW}! WARN:${NC}   %d components\n" "$WARN_COUNT"
printf "  ${RED}✗ FAIL:${NC}   %d components\n" "$FAIL_COUNT"
echo ""

if [[ $FAIL_COUNT -eq 0 ]]; then
    if [[ $WARN_COUNT -eq 0 ]]; then
        log_success "Cluster is healthy!"
    else
        log_warn "Cluster has warnings but is functional"
    fi
else
    log_error "Cluster has failures that need attention"
    exit 1
fi

echo ""
