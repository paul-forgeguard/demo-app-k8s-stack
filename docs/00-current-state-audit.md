# Current State Audit

> **Document Purpose:** Baseline snapshot before MicroCeph + Vault migration
> **Captured:** December 30, 2025
> **Cluster:** vx-app-00.adm.vx.home (single-node MicroK8s)

---

## Cluster Overview

| Property | Value |
|----------|-------|
| Kubernetes Version | v1.35.0 |
| Container Runtime | containerd 2.1.3 |
| OS | Rocky Linux 10.1 (Red Quartz) |
| Kernel | 6.12.0-124.20.1.el10_1.x86_64 |
| Node | vx-app-00.adm.vx.home |
| Internal IP | 10.0.3.5 |
| HA Mode | No (single node) |

---

## Namespaces

| Namespace | Purpose | Age |
|-----------|---------|-----|
| ai | AI stack applications | ~6d |
| cert-manager | TLS certificate automation | ~7d |
| gpu-operator | NVIDIA GPU management | ~5d |
| ingress | NGINX ingress controller | ~7d |
| portainer | Container management UI | ~7d |
| kube-system | Core Kubernetes services | ~7d |

---

## MicroK8s Addons

### Enabled
- `cert-manager` - Cloud native certificate management
- `dns` - CoreDNS
- `gpu` / `nvidia` - NVIDIA hardware support
- `helm3` - Helm package manager
- `hostpath-storage` - Local host directory storage
- `ingress` - NGINX ingress controller
- `ha-cluster` - High availability (configured but single-node)

### Disabled (Notable)
- `rook-ceph` - Will be enabled for MicroCeph integration
- `metallb` - LoadBalancer (not needed with Ingress)
- `metrics-server` - Optional for `kubectl top`
- `observability` - Prometheus/Grafana stack

---

## AI Namespace Resources

### Deployments

| Name | Replicas | Image | Status |
|------|----------|-------|--------|
| openwebui | 1/1 | ghcr.io/open-webui/open-webui:latest-slim | Running |
| kokoro | 1/1 | ghcr.io/remsky/kokoro-fastapi-gpu:latest | Running |
| faster-whisper | 1/1 | fedirz/faster-whisper-server:latest-cuda | Running |

### StatefulSets

| Name | Replicas | Image | Status |
|------|----------|-------|--------|
| pgvector | 1/1 | pgvector/pgvector:pg18 | Running |
| redis | 1/1 | redis:8-alpine | Running |

### Services

| Service | Type | Port | Selector |
|---------|------|------|----------|
| openwebui | ClusterIP | 80 | app=openwebui |
| pgvector | ClusterIP | 5432 | app=pgvector |
| redis | ClusterIP | 6379 | app=redis |
| kokoro | ClusterIP | 8880 | app=kokoro |
| faster-whisper | ClusterIP | 8000 | app=faster-whisper |

---

## Storage

### StorageClasses

| Name | Provisioner | Reclaim | Binding | Default |
|------|-------------|---------|---------|---------|
| microk8s-hostpath | microk8s.io/hostpath | Delete | WaitForFirstConsumer | Yes |

### PersistentVolumeClaims

| PVC | Capacity | Access | StorageClass | Status |
|-----|----------|--------|--------------|--------|
| openwebui-data | 50Gi | RWO | microk8s-hostpath | Bound |
| pgdata-pgvector-0 | 50Gi | RWO | microk8s-hostpath | Bound |
| redisdata-redis-0 | 10Gi | RWO | microk8s-hostpath | Bound |

**Total Storage Allocated:** 110Gi (all on hostpath)

**Location:** `/var/snap/microk8s/common/default-storage/`

---

## Secrets

### ai-secrets (Opaque)

Contains 7 keys:
- `DATABASE_URL` - PostgreSQL connection string
- `OPENAI_API_KEY` - OpenAI API credential
- `PGADMIN_DEFAULT_EMAIL` - PgAdmin login
- `PGADMIN_DEFAULT_PASSWORD` - PgAdmin password
- `POSTGRES_DB` - Database name
- `POSTGRES_PASSWORD` - Database password
- `POSTGRES_USER` - Database username

### openwebui-tls (kubernetes.io/tls)

TLS certificate for ai.vx.home (managed by cert-manager)

---

## Ingress Configuration

| Ingress | Namespace | Host | TLS | Class |
|---------|-----------|------|-----|-------|
| openwebui | ai | ai.vx.home | Yes | public |
| portainer | portainer | ptnr.adm.vx.home | Yes | nginx |

**Ingress Classes Available:**
- `public` - NGINX (for ai.vx.home)
- `nginx` - NGINX (for admin domains)

---

## Current Directory Structure

```
k8s/clusters/vx-home/
├── kustomization.yaml          # Main kustomization entry
├── namespace-ai.yaml           # AI namespace definition
├── cert-manager/               # ClusterIssuer config
├── ingress/                    # Ingress resources
└── apps/
    ├── ai-stack/              # Main applications
    │   ├── openwebui/         # Open WebUI deployment
    │   ├── pgvector/          # PostgreSQL with pgvector
    │   ├── redis/             # Redis cache
    │   ├── pgadmin/           # Database admin
    │   ├── kokoro/            # TTS service
    │   └── faster-whisper/    # STT service
    └── control-portal/        # Admin portal (nginx)
```

---

## What Will Change

### Storage Migration (MicroCeph)

| Current | After |
|---------|-------|
| hostpath-storage (local files) | CephFS (RWX) + RBD (RWO) |
| Single-node only | Multi-node capable |
| No redundancy | Configurable replication |
| `/var/snap/microk8s/...` | Ceph managed pools |

### Secrets Migration (Vault)

| Current | After |
|---------|-------|
| Kubernetes Secret (ai-secrets) | HashiCorp Vault KV v2 |
| Base64 encoded in etcd | Encrypted at rest |
| Manual rotation | Automated rotation capable |
| No audit trail | Full audit logging |
| secretKeyRef in deployments | Vault Agent Injector |

### Manifest Structure (Kustomize)

| Current | After |
|---------|-------|
| Single cluster directory | base/ + overlays/ |
| Hardcoded values | Patches and generators |
| One environment | Multi-environment ready |

---

## Backup Considerations

Before migration, consider backing up:

1. **PVC Data:**
   ```bash
   # Locations
   ls /var/snap/microk8s/common/default-storage/
   ```

2. **Secrets:**
   ```bash
   microk8s kubectl get secret ai-secrets -n ai -o yaml > ai-secrets-backup.yaml
   ```

3. **Current Manifests:**
   ```bash
   git status  # Ensure all changes committed
   git tag pre-ceph-vault-migration
   ```

---

## Verification Commands

```bash
# Cluster health
microk8s status

# All pods running
microk8s kubectl get pods -A

# PVC status
microk8s kubectl get pvc -n ai

# Secret keys
microk8s kubectl get secret ai-secrets -n ai -o jsonpath='{.data}' | jq 'keys'

# Ingress endpoints
microk8s kubectl get ingress -A

# Storage class
microk8s kubectl get sc
```
