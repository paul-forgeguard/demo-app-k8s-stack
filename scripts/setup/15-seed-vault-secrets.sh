#!/usr/bin/env bash
#
# Script: 15-seed-vault-secrets.sh
# Purpose: Migrate secrets from Kubernetes Secret to Vault
# Prerequisites: Vault configured (run 14-configure-vault-auth.sh first)
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
K8S_SECRET_NAME="ai-secrets"

print_header "Vault Secret Seeding"

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
    exit 1
fi
log_success "Vault is unsealed"

# Check source secret exists
if ! $KUBECTL get secret "$K8S_SECRET_NAME" -n "$AI_NAMESPACE" &>/dev/null; then
    log_error "Source secret '$K8S_SECRET_NAME' not found in namespace '$AI_NAMESPACE'"
    exit 1
fi
log_success "Source secret found"

echo ""

# ============================================================================
# Step 1: Login with Root Token
# ============================================================================

log_step "Logging in to Vault..."

ROOT_TOKEN=$(cat "$VAULT_KEYS_FILE" | jq -r '.root_token')
$KUBECTL exec -n "$VAULT_NAMESPACE" vault-0 -- vault login "$ROOT_TOKEN" > /dev/null

log_success "Logged in as root"

echo ""

# ============================================================================
# Step 2: Extract Secrets from Kubernetes
# ============================================================================

log_step "Extracting secrets from Kubernetes..."

# Get all secret keys
log_info "Extracting from $K8S_SECRET_NAME..."

# Extract each secret
OPENAI_API_KEY=$($KUBECTL get secret "$K8S_SECRET_NAME" -n "$AI_NAMESPACE" -o jsonpath='{.data.OPENAI_API_KEY}' | base64 -d)
DATABASE_URL=$($KUBECTL get secret "$K8S_SECRET_NAME" -n "$AI_NAMESPACE" -o jsonpath='{.data.DATABASE_URL}' | base64 -d)
POSTGRES_DB=$($KUBECTL get secret "$K8S_SECRET_NAME" -n "$AI_NAMESPACE" -o jsonpath='{.data.POSTGRES_DB}' | base64 -d)
POSTGRES_USER=$($KUBECTL get secret "$K8S_SECRET_NAME" -n "$AI_NAMESPACE" -o jsonpath='{.data.POSTGRES_USER}' | base64 -d)
POSTGRES_PASSWORD=$($KUBECTL get secret "$K8S_SECRET_NAME" -n "$AI_NAMESPACE" -o jsonpath='{.data.POSTGRES_PASSWORD}' | base64 -d)
PGADMIN_DEFAULT_EMAIL=$($KUBECTL get secret "$K8S_SECRET_NAME" -n "$AI_NAMESPACE" -o jsonpath='{.data.PGADMIN_DEFAULT_EMAIL}' | base64 -d)
PGADMIN_DEFAULT_PASSWORD=$($KUBECTL get secret "$K8S_SECRET_NAME" -n "$AI_NAMESPACE" -o jsonpath='{.data.PGADMIN_DEFAULT_PASSWORD}' | base64 -d)

log_success "Secrets extracted (values masked)"
echo "  - OPENAI_API_KEY: ${OPENAI_API_KEY:0:10}..."
echo "  - DATABASE_URL: ${DATABASE_URL:0:20}..."
echo "  - POSTGRES_DB: $POSTGRES_DB"
echo "  - POSTGRES_USER: $POSTGRES_USER"
echo "  - POSTGRES_PASSWORD: ****"
echo "  - PGADMIN_DEFAULT_EMAIL: $PGADMIN_DEFAULT_EMAIL"
echo "  - PGADMIN_DEFAULT_PASSWORD: ****"

echo ""

# ============================================================================
# Step 3: Write OpenWebUI Secrets
# ============================================================================

log_step "Writing OpenWebUI secrets to Vault..."

$KUBECTL exec -n "$VAULT_NAMESPACE" vault-0 -- vault kv put ai/openwebui \
    OPENAI_API_KEY="$OPENAI_API_KEY" \
    DATABASE_URL="$DATABASE_URL" \
    POSTGRES_DB="$POSTGRES_DB" \
    POSTGRES_USER="$POSTGRES_USER" \
    POSTGRES_PASSWORD="$POSTGRES_PASSWORD"

log_success "ai/openwebui secrets written"

echo ""

# ============================================================================
# Step 4: Write PgVector Secrets
# ============================================================================

log_step "Writing PgVector secrets to Vault..."

$KUBECTL exec -n "$VAULT_NAMESPACE" vault-0 -- vault kv put ai/pgvector \
    POSTGRES_DB="$POSTGRES_DB" \
    POSTGRES_USER="$POSTGRES_USER" \
    POSTGRES_PASSWORD="$POSTGRES_PASSWORD"

log_success "ai/pgvector secrets written"

echo ""

# ============================================================================
# Step 5: Write PgAdmin Secrets
# ============================================================================

log_step "Writing PgAdmin secrets to Vault..."

$KUBECTL exec -n "$VAULT_NAMESPACE" vault-0 -- vault kv put ai/pgadmin \
    PGADMIN_DEFAULT_EMAIL="$PGADMIN_DEFAULT_EMAIL" \
    PGADMIN_DEFAULT_PASSWORD="$PGADMIN_DEFAULT_PASSWORD"

log_success "ai/pgadmin secrets written"

echo ""

# ============================================================================
# Step 6: Verify Secrets
# ============================================================================

log_step "Verifying secrets in Vault..."

echo ""
log_info "Listing secrets at ai/:"
$KUBECTL exec -n "$VAULT_NAMESPACE" vault-0 -- vault kv list ai/

echo ""
log_info "OpenWebUI secret keys:"
$KUBECTL exec -n "$VAULT_NAMESPACE" vault-0 -- vault kv get -format=json ai/openwebui | jq '.data.data | keys'

echo ""
log_info "PgVector secret keys:"
$KUBECTL exec -n "$VAULT_NAMESPACE" vault-0 -- vault kv get -format=json ai/pgvector | jq '.data.data | keys'

echo ""
log_info "PgAdmin secret keys:"
$KUBECTL exec -n "$VAULT_NAMESPACE" vault-0 -- vault kv get -format=json ai/pgadmin | jq '.data.data | keys'

echo ""

# ============================================================================
# Final Status
# ============================================================================

print_header "Secret Seeding Complete"

log_success "All secrets migrated to Vault"
echo ""
log_info "Secrets stored:"
echo "  - ai/openwebui (5 keys)"
echo "  - ai/pgvector (3 keys)"
echo "  - ai/pgadmin (2 keys)"
echo ""
log_info "Next steps:"
echo "  1. Apply Vault Ingress: microk8s kubectl apply -f k8s/overlays/vx-home/platform/vault/ingress.yaml"
echo "  2. Update deployments to use Vault Agent Injector"
echo "  3. Test secret injection with a test pod"
echo ""
log_warn "Note: Original Kubernetes secret '$K8S_SECRET_NAME' still exists"
log_warn "Keep it until Vault injection is verified working"
echo ""
