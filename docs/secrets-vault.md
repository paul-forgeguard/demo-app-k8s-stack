# HashiCorp Vault Secrets Management

> **Document Purpose:** Vault installation, configuration, and operations guide
> **Installation Method:** Helm chart (in-cluster, standalone mode)
> **Authentication:** Kubernetes auth method
> **Secret Injection:** Vault Agent Injector

---

## Overview

HashiCorp Vault provides centralized secrets management with:

- **Encrypted storage**: Secrets encrypted at rest and in transit
- **Dynamic secrets**: Generate credentials on-demand (future capability)
- **Audit logging**: Full audit trail of secret access
- **Access policies**: Fine-grained RBAC per application
- **Kubernetes native**: Automatic secret injection via annotations

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│                            MicroK8s Cluster                              │
│                                                                          │
│  ┌─────────────────────────────────────────────────────────────────────┐ │
│  │                         vault namespace                              │ │
│  │  ┌─────────────────────┐     ┌─────────────────────────────────────┐│ │
│  │  │     vault-0 Pod     │     │      Vault Agent Injector          ││ │
│  │  │  ┌───────────────┐  │     │  (Mutating Webhook)                 ││ │
│  │  │  │  Vault Server │  │     │                                     ││ │
│  │  │  │  (Standalone) │  │     │  Watches for pods with:             ││ │
│  │  │  └───────┬───────┘  │     │  vault.hashicorp.com/agent-inject  ││ │
│  │  │          │          │     └─────────────────────────────────────┘│ │
│  │  │  ┌───────▼───────┐  │                                            │ │
│  │  │  │  PVC (ceph-rbd)│  │                                            │ │
│  │  │  │    10Gi       │  │                                            │ │
│  │  │  └───────────────┘  │                                            │ │
│  │  └─────────────────────┘                                            │ │
│  └─────────────────────────────────────────────────────────────────────┘ │
│                                     │                                    │
│                                     │ Kubernetes Auth                    │
│                                     ▼                                    │
│  ┌─────────────────────────────────────────────────────────────────────┐ │
│  │                          ai namespace                                │ │
│  │  ┌────────────────────────────────────────────────────────────────┐ │ │
│  │  │                    openwebui Pod                                │ │ │
│  │  │  ┌────────────────────┐  ┌────────────────────────────────────┐│ │ │
│  │  │  │ vault-agent-init   │  │         openwebui container        ││ │ │
│  │  │  │ (init container)   │  │                                    ││ │ │
│  │  │  │                    │  │  /vault/secrets/env                ││ │ │
│  │  │  │  Fetches secrets   │──▶│  (injected secrets file)          ││ │ │
│  │  │  │  from Vault        │  │                                    ││ │ │
│  │  │  └────────────────────┘  └────────────────────────────────────┘│ │ │
│  │  └────────────────────────────────────────────────────────────────┘ │ │
│  └─────────────────────────────────────────────────────────────────────┘ │
└──────────────────────────────────────────────────────────────────────────┘
```

---

## Secrets Organization

### KV v2 Engine Structure

```
ai/                           # KV v2 secrets engine
├── openwebui                 # OpenWebUI secrets
│   ├── OPENAI_API_KEY
│   ├── DATABASE_URL
│   ├── POSTGRES_USER
│   ├── POSTGRES_PASSWORD
│   └── POSTGRES_DB
├── pgvector                  # PostgreSQL secrets
│   ├── POSTGRES_USER
│   ├── POSTGRES_PASSWORD
│   └── POSTGRES_DB
├── pgadmin                   # PgAdmin secrets
│   ├── PGADMIN_DEFAULT_EMAIL
│   └── PGADMIN_DEFAULT_PASSWORD
└── redis                     # Redis secrets (if auth enabled)
    └── REDIS_PASSWORD
```

---

## Access Control

### Policies

Each application gets a dedicated policy:

```hcl
# openwebui-policy
path "ai/data/openwebui" {
  capabilities = ["read"]
}
path "ai/metadata/openwebui" {
  capabilities = ["read", "list"]
}
```

### Roles

Kubernetes auth roles bind ServiceAccounts to policies:

| Role | ServiceAccount | Namespace | Policy |
|------|----------------|-----------|--------|
| openwebui-role | openwebui | ai | openwebui-policy |
| pgvector-role | pgvector | ai | pgvector-policy |
| pgadmin-role | pgadmin | ai | pgadmin-policy |

---

## Installation Steps

### Prerequisites

- MicroK8s with helm3 addon
- MicroCeph storage (ceph-rbd StorageClass)
- `vault` namespace created

### Step 1: Add Helm Repository

```bash
microk8s helm3 repo add hashicorp https://helm.releases.hashicorp.com
microk8s helm3 repo update
```

### Step 2: Create Namespace

```bash
microk8s kubectl create namespace vault
```

### Step 3: Install Vault via Helm

```bash
microk8s helm3 install vault hashicorp/vault \
  --namespace vault \
  -f helm-values/vault-values.yaml
```

### Step 4: Wait for Pod (Sealed State)

```bash
microk8s kubectl get pods -n vault -w
```

The pod will show `0/1 Ready` until initialized.

### Step 5: Initialize Vault

```bash
microk8s kubectl exec -n vault vault-0 -- vault operator init \
  -key-shares=1 \
  -key-threshold=1 \
  -format=json > .vault-keys
```

**CRITICAL**: Back up `.vault-keys` securely. Contains unseal key and root token.

### Step 6: Unseal Vault

```bash
UNSEAL_KEY=$(cat .vault-keys | jq -r '.unseal_keys_b64[0]')
microk8s kubectl exec -n vault vault-0 -- vault operator unseal $UNSEAL_KEY
```

### Step 7: Verify Status

```bash
microk8s kubectl exec -n vault vault-0 -- vault status
```

Expected: `Sealed: false`

---

## Configuration Steps

### Step 1: Login with Root Token

```bash
ROOT_TOKEN=$(cat .vault-keys | jq -r '.root_token')
microk8s kubectl exec -n vault vault-0 -- vault login $ROOT_TOKEN
```

### Step 2: Enable Kubernetes Auth

```bash
microk8s kubectl exec -n vault vault-0 -- vault auth enable kubernetes

microk8s kubectl exec -n vault vault-0 -- vault write auth/kubernetes/config \
  kubernetes_host="https://kubernetes.default.svc:443"
```

### Step 3: Enable KV Secrets Engine

```bash
microk8s kubectl exec -n vault vault-0 -- vault secrets enable -path=ai kv-v2
```

### Step 4: Create Policies

```bash
# OpenWebUI policy
microk8s kubectl exec -n vault vault-0 -- vault policy write openwebui-policy - <<EOF
path "ai/data/openwebui" {
  capabilities = ["read"]
}
path "ai/metadata/openwebui" {
  capabilities = ["read", "list"]
}
EOF

# Repeat for other applications...
```

### Step 5: Create Roles

```bash
microk8s kubectl exec -n vault vault-0 -- vault write auth/kubernetes/role/openwebui-role \
  bound_service_account_names=openwebui \
  bound_service_account_namespaces=ai \
  policies=openwebui-policy \
  ttl=1h
```

### Step 6: Seed Secrets

```bash
# Get existing secrets from Kubernetes
OPENAI_KEY=$(microk8s kubectl get secret ai-secrets -n ai -o jsonpath='{.data.OPENAI_API_KEY}' | base64 -d)
DATABASE_URL=$(microk8s kubectl get secret ai-secrets -n ai -o jsonpath='{.data.DATABASE_URL}' | base64 -d)
# ... etc

# Write to Vault
microk8s kubectl exec -n vault vault-0 -- vault kv put ai/openwebui \
  OPENAI_API_KEY="$OPENAI_KEY" \
  DATABASE_URL="$DATABASE_URL"
```

---

## Using Vault in Deployments

### Vault Agent Injector Pattern

Add annotations to pod spec:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: openwebui
spec:
  template:
    metadata:
      annotations:
        vault.hashicorp.com/agent-inject: "true"
        vault.hashicorp.com/role: "openwebui-role"
        vault.hashicorp.com/agent-inject-secret-env: "ai/data/openwebui"
        vault.hashicorp.com/agent-inject-template-env: |
          {{- with secret "ai/data/openwebui" -}}
          export OPENAI_API_KEY="{{ .Data.data.OPENAI_API_KEY }}"
          export DATABASE_URL="{{ .Data.data.DATABASE_URL }}"
          export POSTGRES_USER="{{ .Data.data.POSTGRES_USER }}"
          export POSTGRES_PASSWORD="{{ .Data.data.POSTGRES_PASSWORD }}"
          export POSTGRES_DB="{{ .Data.data.POSTGRES_DB }}"
          {{- end -}}
    spec:
      serviceAccountName: openwebui  # Must match role binding
      containers:
      - name: openwebui
        # Remove secretKeyRef, use sourced file instead
        command: ["/bin/sh", "-c"]
        args:
          - source /vault/secrets/env && exec /app/start.sh
```

### What Happens

1. **Pod Creation**: Vault Agent Injector mutates the pod spec
2. **Init Container**: `vault-agent-init` authenticates and fetches secrets
3. **Secret File**: Secrets written to `/vault/secrets/env`
4. **Application Start**: Container sources the file before starting

---

## Common Commands

### Vault Status

```bash
# Check sealed status
microk8s kubectl exec -n vault vault-0 -- vault status

# Check auth methods
microk8s kubectl exec -n vault vault-0 -- vault auth list

# Check secrets engines
microk8s kubectl exec -n vault vault-0 -- vault secrets list
```

### Secret Operations

```bash
# Read a secret
microk8s kubectl exec -n vault vault-0 -- vault kv get ai/openwebui

# List secrets
microk8s kubectl exec -n vault vault-0 -- vault kv list ai/

# Update a secret
microk8s kubectl exec -n vault vault-0 -- vault kv put ai/openwebui \
  OPENAI_API_KEY="new-key"

# Delete a secret
microk8s kubectl exec -n vault vault-0 -- vault kv delete ai/openwebui
```

### Policy Management

```bash
# List policies
microk8s kubectl exec -n vault vault-0 -- vault policy list

# Read a policy
microk8s kubectl exec -n vault vault-0 -- vault policy read openwebui-policy
```

---

## Troubleshooting

### Vault Pod Not Ready

1. Check if initialized:
   ```bash
   microk8s kubectl exec -n vault vault-0 -- vault status
   ```

2. If sealed, unseal:
   ```bash
   UNSEAL_KEY=$(cat .vault-keys | jq -r '.unseal_keys_b64[0]')
   microk8s kubectl exec -n vault vault-0 -- vault operator unseal $UNSEAL_KEY
   ```

### Agent Inject Not Working

1. Check injector pod:
   ```bash
   microk8s kubectl get pods -n vault -l app.kubernetes.io/name=vault-agent-injector
   ```

2. Check injector logs:
   ```bash
   microk8s kubectl logs -n vault -l app.kubernetes.io/name=vault-agent-injector
   ```

3. Verify annotations are correct in pod

4. Check ServiceAccount exists and matches role

### Permission Denied

1. Verify role exists:
   ```bash
   microk8s kubectl exec -n vault vault-0 -- vault read auth/kubernetes/role/openwebui-role
   ```

2. Check ServiceAccount matches:
   ```bash
   microk8s kubectl get sa -n ai
   ```

3. Test policy:
   ```bash
   # Login as the role
   microk8s kubectl exec -n vault vault-0 -- vault login -method=kubernetes role=openwebui-role

   # Try to read
   microk8s kubectl exec -n vault vault-0 -- vault kv get ai/openwebui
   ```

### Secrets Not Appearing in Pod

1. Check init container logs:
   ```bash
   microk8s kubectl logs <pod-name> -n ai -c vault-agent-init
   ```

2. Exec into pod and check file:
   ```bash
   microk8s kubectl exec -n ai <pod-name> -- cat /vault/secrets/env
   ```

---

## Security Best Practices

### Unseal Keys

- Store `.vault-keys` in a secure location (not in git)
- Consider using auto-unseal with cloud KMS for production
- Back up to encrypted storage

### Root Token

- Only use for initial setup
- Create admin user with appropriate policy
- Revoke root token after setup (optional for homelab)

### Policies

- Follow principle of least privilege
- Each app should only read its own secrets
- No write access for application roles

### Audit Logging

```bash
# Enable file audit (optional)
microk8s kubectl exec -n vault vault-0 -- vault audit enable file file_path=/vault/logs/audit.log
```

---

## Backup and Recovery

### Backup Secrets

```bash
# Export all secrets (for backup)
microk8s kubectl exec -n vault vault-0 -- vault kv get -format=json ai/openwebui > backup-openwebui.json
```

### Disaster Recovery

1. Redeploy Vault with same PVC
2. Unseal with saved unseal key
3. Secrets persist in PVC

---

## UI Access

### Via Ingress

Access Vault UI at: `https://vault.adm.vx.home`

Login with:
- **Method**: Token
- **Token**: Root token from `.vault-keys`

### Port Forward (Alternative)

```bash
microk8s kubectl port-forward -n vault vault-0 8200:8200
# Access at http://localhost:8200
```

---

## References

- [Vault Documentation](https://developer.hashicorp.com/vault/docs)
- [Vault Helm Chart](https://github.com/hashicorp/vault-helm)
- [Vault Agent Injector](https://developer.hashicorp.com/vault/docs/platform/k8s/injector)
- [Kubernetes Auth Method](https://developer.hashicorp.com/vault/docs/auth/kubernetes)
