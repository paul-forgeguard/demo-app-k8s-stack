#!/usr/bin/env bash
#
# Script: 12-install-vault.sh
# Purpose: Install HashiCorp Vault via Helm
# Prerequisites: MicroCeph configured (run 10-enable-microceph.sh first)
# Author: VX Home Infrastructure
#

set -euo pipefail

# Source common functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

# Configuration
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
VAULT_VALUES="$PROJECT_ROOT/helm-values/vault-values.yaml"
VAULT_NAMESPACE="vault"

print_header "Vault Installation"

# Get kubectl and helm commands
KUBECTL=$(get_kubectl) || exit 1
HELM=$(get_helm) || exit 1

# ============================================================================
# Pre-checks
# ============================================================================

log_step "Running pre-checks..."

# Check ceph-rbd StorageClass exists
if ! $KUBECTL get sc ceph-rbd &>/dev/null; then
    log_error "ceph-rbd StorageClass not found"
    echo ""
    log_error "Please run 10-enable-microceph.sh first"
    exit 1
fi
log_success "ceph-rbd StorageClass available"

# Check values file exists
if [[ ! -f "$VAULT_VALUES" ]]; then
    log_error "Vault values file not found: $VAULT_VALUES"
    exit 1
fi
log_success "Vault values file found"

echo ""

# ============================================================================
# Step 1: Add Helm Repository
# ============================================================================

log_step "Adding HashiCorp Helm repository..."

if $HELM repo list 2>/dev/null | grep -q hashicorp; then
    log_warn "HashiCorp repo already added"
else
    $HELM repo add hashicorp https://helm.releases.hashicorp.com
    log_success "HashiCorp repo added"
fi

$HELM repo update
log_success "Helm repos updated"

echo ""

# ============================================================================
# Step 2: Create Namespace
# ============================================================================

log_step "Creating vault namespace..."

if $KUBECTL get namespace "$VAULT_NAMESPACE" &>/dev/null; then
    log_warn "Namespace $VAULT_NAMESPACE already exists"
else
    $KUBECTL create namespace "$VAULT_NAMESPACE"
    log_success "Namespace $VAULT_NAMESPACE created"
fi

echo ""

# ============================================================================
# Step 3: Install Vault via Helm
# ============================================================================

log_step "Installing Vault..."

if $HELM list -n "$VAULT_NAMESPACE" 2>/dev/null | grep -q vault; then
    log_warn "Vault release already exists"
    log_info "Current status:"
    $HELM status vault -n "$VAULT_NAMESPACE" | head -20
else
    log_info "Installing Vault with values from: $VAULT_VALUES"
    $HELM install vault hashicorp/vault \
        --namespace "$VAULT_NAMESPACE" \
        -f "$VAULT_VALUES"
    log_success "Vault Helm release installed"
fi

echo ""

# ============================================================================
# Step 4: Wait for Pod
# ============================================================================

log_step "Waiting for Vault pod..."

log_info "Note: Pod will show 0/1 Ready until initialized and unsealed"
echo ""

# Wait for pod to exist
TIMEOUT=120
ELAPSED=0
while [[ $ELAPSED -lt $TIMEOUT ]]; do
    if $KUBECTL get pods -n "$VAULT_NAMESPACE" vault-0 &>/dev/null; then
        break
    fi
    sleep 5
    ((ELAPSED+=5))
    echo -n "."
done
echo ""

# Wait for Running status (even if not Ready)
log_info "Waiting for pod to be Running..."
ELAPSED=0
while [[ $ELAPSED -lt $TIMEOUT ]]; do
    STATUS=$($KUBECTL get pod vault-0 -n "$VAULT_NAMESPACE" -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")
    if [[ "$STATUS" == "Running" ]]; then
        break
    fi
    sleep 5
    ((ELAPSED+=5))
    echo -n "."
done
echo ""

# Show current status
$KUBECTL get pods -n "$VAULT_NAMESPACE"

echo ""

# ============================================================================
# Step 5: Check Vault Status
# ============================================================================

log_step "Checking Vault status..."

# Give it a moment to start the process
sleep 5

VAULT_STATUS=$($KUBECTL exec -n "$VAULT_NAMESPACE" vault-0 -- vault status -format=json 2>/dev/null || echo '{"sealed": true, "initialized": false}')

INITIALIZED=$(echo "$VAULT_STATUS" | jq -r '.initialized')
SEALED=$(echo "$VAULT_STATUS" | jq -r '.sealed')

log_info "Vault status:"
echo "  Initialized: $INITIALIZED"
echo "  Sealed: $SEALED"

echo ""

# ============================================================================
# Final Status
# ============================================================================

print_header "Installation Complete"

if [[ "$INITIALIZED" == "false" ]]; then
    log_success "Vault installed but NOT initialized"
    echo ""
    log_info "Next steps:"
    echo "  1. Run: sudo ./scripts/setup/13-init-unseal-vault.sh"
    echo ""
    log_warn "IMPORTANT: The init script will create .vault-keys file"
    log_warn "Back up this file securely - it contains unseal keys and root token"
else
    log_success "Vault already initialized"
    if [[ "$SEALED" == "true" ]]; then
        log_warn "Vault is sealed - needs to be unsealed"
        echo ""
        log_info "To unseal manually:"
        echo "  UNSEAL_KEY=\$(cat .vault-keys | jq -r '.unseal_keys_b64[0]')"
        echo "  microk8s kubectl exec -n vault vault-0 -- vault operator unseal \$UNSEAL_KEY"
    else
        log_success "Vault is unsealed and ready"
        echo ""
        log_info "Next steps:"
        echo "  1. Run: sudo ./scripts/setup/14-configure-vault-auth.sh"
    fi
fi

echo ""
log_info "Vault pods:"
$KUBECTL get pods -n "$VAULT_NAMESPACE"
echo ""
