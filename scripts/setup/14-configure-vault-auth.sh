#!/usr/bin/env bash
#
# Script: 14-configure-vault-auth.sh
# Purpose: Configure Vault Kubernetes auth and KV engine
# Prerequisites: Vault initialized and unsealed (run 13-init-unseal-vault.sh first)
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
AI_NAMESPACE="ai"

print_header "Vault Auth Configuration"

# Get kubectl command
KUBECTL=$(get_kubectl) || exit 1

# ============================================================================
# Pre-checks
# ============================================================================

log_step "Running pre-checks..."

# Check Vault is unsealed
VAULT_STATUS=$($KUBECTL exec -n "$VAULT_NAMESPACE" vault-0 -- vault status -format=json 2>/dev/null || echo '{"sealed": true}')
SEALED=$(echo "$VAULT_STATUS" | jq -r '.sealed')

if [[ "$SEALED" == "true" ]]; then
    log_error "Vault is sealed"
    echo ""
    log_error "Please run 13-init-unseal-vault.sh first"
    exit 1
fi
log_success "Vault is unsealed"

# Check keys file exists
if [[ ! -f "$VAULT_KEYS_FILE" ]]; then
    log_error ".vault-keys file not found"
    exit 1
fi
log_success "Keys file found"

echo ""

# ============================================================================
# Step 1: Login with Root Token
# ============================================================================

log_step "Logging in with root token..."

ROOT_TOKEN=$(cat "$VAULT_KEYS_FILE" | jq -r '.root_token')

$KUBECTL exec -n "$VAULT_NAMESPACE" vault-0 -- vault login "$ROOT_TOKEN" > /dev/null

log_success "Logged in as root"

echo ""

# ============================================================================
# Step 2: Enable Kubernetes Auth
# ============================================================================

log_step "Enabling Kubernetes auth method..."

# Check if already enabled
AUTH_LIST=$($KUBECTL exec -n "$VAULT_NAMESPACE" vault-0 -- vault auth list -format=json 2>/dev/null || echo '{}')

if echo "$AUTH_LIST" | jq -e '.["kubernetes/"]' &>/dev/null; then
    log_warn "Kubernetes auth already enabled"
else
    $KUBECTL exec -n "$VAULT_NAMESPACE" vault-0 -- vault auth enable kubernetes
    log_success "Kubernetes auth enabled"
fi

echo ""

# ============================================================================
# Step 3: Configure Kubernetes Auth
# ============================================================================

log_step "Configuring Kubernetes auth..."

$KUBECTL exec -n "$VAULT_NAMESPACE" vault-0 -- vault write auth/kubernetes/config \
    kubernetes_host="https://kubernetes.default.svc:443"

log_success "Kubernetes auth configured"

echo ""

# ============================================================================
# Step 4: Enable KV Secrets Engine
# ============================================================================

log_step "Enabling KV v2 secrets engine..."

# Check if already enabled
SECRETS_LIST=$($KUBECTL exec -n "$VAULT_NAMESPACE" vault-0 -- vault secrets list -format=json 2>/dev/null || echo '{}')

if echo "$SECRETS_LIST" | jq -e '.["ai/"]' &>/dev/null; then
    log_warn "KV engine at 'ai/' already enabled"
else
    $KUBECTL exec -n "$VAULT_NAMESPACE" vault-0 -- vault secrets enable -path=ai kv-v2
    log_success "KV v2 engine enabled at 'ai/'"
fi

echo ""

# ============================================================================
# Step 5: Create Policies
# ============================================================================

log_step "Creating policies..."

# OpenWebUI policy
log_info "Creating openwebui-policy..."
echo 'path "ai/data/openwebui" {
  capabilities = ["read"]
}
path "ai/metadata/openwebui" {
  capabilities = ["read", "list"]
}' | $KUBECTL exec -i -n "$VAULT_NAMESPACE" vault-0 -- vault policy write openwebui-policy -
log_success "openwebui-policy created"

# PgVector policy
log_info "Creating pgvector-policy..."
echo 'path "ai/data/pgvector" {
  capabilities = ["read"]
}
path "ai/metadata/pgvector" {
  capabilities = ["read", "list"]
}' | $KUBECTL exec -i -n "$VAULT_NAMESPACE" vault-0 -- vault policy write pgvector-policy -
log_success "pgvector-policy created"

# PgAdmin policy
log_info "Creating pgadmin-policy..."
echo 'path "ai/data/pgadmin" {
  capabilities = ["read"]
}
path "ai/metadata/pgadmin" {
  capabilities = ["read", "list"]
}' | $KUBECTL exec -i -n "$VAULT_NAMESPACE" vault-0 -- vault policy write pgadmin-policy -
log_success "pgadmin-policy created"

echo ""

# ============================================================================
# Step 6: Create Roles
# ============================================================================

log_step "Creating Kubernetes auth roles..."

# OpenWebUI role
log_info "Creating openwebui-role..."
$KUBECTL exec -n "$VAULT_NAMESPACE" vault-0 -- vault write auth/kubernetes/role/openwebui-role \
    bound_service_account_names=openwebui \
    bound_service_account_namespaces="$AI_NAMESPACE" \
    policies=openwebui-policy \
    ttl=1h

log_success "openwebui-role created"

# PgVector role
log_info "Creating pgvector-role..."
$KUBECTL exec -n "$VAULT_NAMESPACE" vault-0 -- vault write auth/kubernetes/role/pgvector-role \
    bound_service_account_names=pgvector \
    bound_service_account_namespaces="$AI_NAMESPACE" \
    policies=pgvector-policy \
    ttl=1h

log_success "pgvector-role created"

# PgAdmin role
log_info "Creating pgadmin-role..."
$KUBECTL exec -n "$VAULT_NAMESPACE" vault-0 -- vault write auth/kubernetes/role/pgadmin-role \
    bound_service_account_names=pgadmin \
    bound_service_account_namespaces="$AI_NAMESPACE" \
    policies=pgadmin-policy \
    ttl=1h

log_success "pgadmin-role created"

echo ""

# ============================================================================
# Step 7: Verify Configuration
# ============================================================================

log_step "Verifying configuration..."

echo ""
log_info "Auth methods:"
$KUBECTL exec -n "$VAULT_NAMESPACE" vault-0 -- vault auth list

echo ""
log_info "Secrets engines:"
$KUBECTL exec -n "$VAULT_NAMESPACE" vault-0 -- vault secrets list

echo ""
log_info "Policies:"
$KUBECTL exec -n "$VAULT_NAMESPACE" vault-0 -- vault policy list

echo ""

# ============================================================================
# Final Status
# ============================================================================

print_header "Configuration Complete"

log_success "Vault auth configuration complete"
echo ""
log_info "Configured:"
echo "  - Kubernetes auth method"
echo "  - KV v2 secrets engine at 'ai/'"
echo "  - Policies: openwebui-policy, pgvector-policy, pgadmin-policy"
echo "  - Roles: openwebui-role, pgvector-role, pgadmin-role"
echo ""
log_info "Next steps:"
echo "  1. Run: sudo ./scripts/setup/15-seed-vault-secrets.sh"
echo ""
