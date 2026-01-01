#!/usr/bin/env bash
#
# Script: 13-init-unseal-vault.sh
# Purpose: Initialize and unseal HashiCorp Vault
# Prerequisites: Vault installed (run 12-install-vault.sh first)
# Author: VX Home Infrastructure
#

set -euo pipefail

# Source common functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

# Configuration
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
VAULT_KEYS_FILE="$PROJECT_ROOT/.vault-keys"
VAULT_NAMESPACE="vault"

print_header "Vault Initialization & Unseal"

# Get kubectl command
KUBECTL=$(get_kubectl) || exit 1

# ============================================================================
# Pre-checks
# ============================================================================

log_step "Running pre-checks..."

# Check Vault pod exists and is running
if ! $KUBECTL get pod vault-0 -n "$VAULT_NAMESPACE" &>/dev/null; then
    log_error "Vault pod not found"
    echo ""
    log_error "Please run 12-install-vault.sh first"
    exit 1
fi

POD_STATUS=$($KUBECTL get pod vault-0 -n "$VAULT_NAMESPACE" -o jsonpath='{.status.phase}')
if [[ "$POD_STATUS" != "Running" ]]; then
    log_error "Vault pod is not running (status: $POD_STATUS)"
    exit 1
fi
log_success "Vault pod is running"

echo ""

# ============================================================================
# Step 1: Check Current Status
# ============================================================================

log_step "Checking Vault status..."

VAULT_STATUS=$($KUBECTL exec -n "$VAULT_NAMESPACE" vault-0 -- vault status -format=json 2>/dev/null || echo '{"sealed": true, "initialized": false}')

INITIALIZED=$(echo "$VAULT_STATUS" | jq -r '.initialized')
SEALED=$(echo "$VAULT_STATUS" | jq -r '.sealed')

log_info "Current status:"
echo "  Initialized: $INITIALIZED"
echo "  Sealed: $SEALED"

echo ""

# ============================================================================
# Step 2: Initialize Vault (if needed)
# ============================================================================

log_step "Initializing Vault..."

if [[ "$INITIALIZED" == "true" ]]; then
    log_warn "Vault is already initialized"

    if [[ ! -f "$VAULT_KEYS_FILE" ]]; then
        log_error "Vault is initialized but .vault-keys file not found"
        log_error "You need the original keys file to unseal"
        exit 1
    fi
else
    # Check if keys file already exists (from previous attempt)
    if [[ -f "$VAULT_KEYS_FILE" ]]; then
        log_warn "Found existing .vault-keys file"
        if confirm_action "Delete existing keys and re-initialize?" "n"; then
            rm -f "$VAULT_KEYS_FILE"
        else
            log_error "Cannot initialize - keys file exists"
            exit 1
        fi
    fi

    log_info "Initializing Vault with 1 key share, 1 threshold..."

    $KUBECTL exec -n "$VAULT_NAMESPACE" vault-0 -- vault operator init \
        -key-shares=1 \
        -key-threshold=1 \
        -format=json > "$VAULT_KEYS_FILE"

    # Set restrictive permissions
    chmod 600 "$VAULT_KEYS_FILE"

    log_success "Vault initialized"
    echo ""

    # Display keys (once)
    log_warn "========================================="
    log_warn "IMPORTANT: SAVE THESE VALUES SECURELY"
    log_warn "========================================="
    echo ""
    log_info "Unseal Key:"
    cat "$VAULT_KEYS_FILE" | jq -r '.unseal_keys_b64[0]'
    echo ""
    log_info "Root Token:"
    cat "$VAULT_KEYS_FILE" | jq -r '.root_token'
    echo ""
    log_warn "Keys saved to: $VAULT_KEYS_FILE"
    log_warn "Back up this file immediately!"
    log_warn "========================================="
    echo ""
fi

# ============================================================================
# Step 3: Unseal Vault
# ============================================================================

log_step "Unsealing Vault..."

# Re-check status
VAULT_STATUS=$($KUBECTL exec -n "$VAULT_NAMESPACE" vault-0 -- vault status -format=json 2>/dev/null || echo '{"sealed": true}')
SEALED=$(echo "$VAULT_STATUS" | jq -r '.sealed')

if [[ "$SEALED" == "false" ]]; then
    log_warn "Vault is already unsealed"
else
    if [[ ! -f "$VAULT_KEYS_FILE" ]]; then
        log_error "Cannot unseal - .vault-keys file not found"
        exit 1
    fi

    UNSEAL_KEY=$(cat "$VAULT_KEYS_FILE" | jq -r '.unseal_keys_b64[0]')

    log_info "Unsealing with key..."
    $KUBECTL exec -n "$VAULT_NAMESPACE" vault-0 -- vault operator unseal "$UNSEAL_KEY"

    log_success "Vault unsealed"
fi

echo ""

# ============================================================================
# Step 4: Verify Status
# ============================================================================

log_step "Verifying Vault status..."

sleep 3

VAULT_STATUS=$($KUBECTL exec -n "$VAULT_NAMESPACE" vault-0 -- vault status -format=json 2>/dev/null)

echo "$VAULT_STATUS" | jq '.'

SEALED=$(echo "$VAULT_STATUS" | jq -r '.sealed')
VERSION=$(echo "$VAULT_STATUS" | jq -r '.version')

echo ""

# ============================================================================
# Final Status
# ============================================================================

print_header "Initialization Complete"

if [[ "$SEALED" == "false" ]]; then
    log_success "Vault is initialized and unsealed"
    log_info "Version: $VERSION"
    echo ""
    log_info "Vault pod status:"
    $KUBECTL get pods -n "$VAULT_NAMESPACE"
    echo ""
    log_info "Next steps:"
    echo "  1. Run: sudo ./scripts/setup/14-configure-vault-auth.sh"
    echo ""
    log_warn "Remember:"
    echo "  - Back up .vault-keys to secure location"
    echo "  - Vault will need to be unsealed after pod restarts"
    echo ""
else
    log_error "Vault is still sealed"
    echo ""
    log_info "Troubleshooting:"
    echo "  - Check Vault logs: microk8s kubectl logs -n vault vault-0"
    echo "  - Verify .vault-keys file exists and contains valid keys"
    exit 1
fi
