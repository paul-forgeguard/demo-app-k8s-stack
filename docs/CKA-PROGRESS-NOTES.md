# CKA Homelab Progress Notes

> **Project:** MicroK8s AI Stack Homelab
> **Period:** December 22-24, 2025
> **Purpose:** Hands-on Kubernetes practice alongside CKA certification course

---

## Executive Summary

Built a production-grade single-node Kubernetes cluster on Rocky Linux running an AI application stack. This homelab project provides practical experience with core CKA exam domains while creating a functional AI chat interface with vector database support, text-to-speech, and speech-to-text capabilities.

**Key Metrics:**
- 4 git commits with ~12,000 lines of code/configuration
- 56 configuration and documentation files
- 18 automation scripts (8 setup + 10 admin)
- 13 comprehensive documentation files

---

## CKA Domain Coverage

| CKA Domain | Exam Weight | Skills Demonstrated |
|------------|-------------|---------------------|
| **Cluster Architecture, Installation & Configuration** | 25% | MicroK8s installation, addon management, SELinux configuration, kubeconfig, node setup |
| **Workloads & Scheduling** | 15% | Deployments, StatefulSets, nodeSelector, resource management, rolling updates |
| **Services & Networking** | 20% | Ingress controller, TLS termination, ClusterIP services, path-based routing, DNS |
| **Storage** | 10% | PersistentVolumeClaims, StorageClasses, hostpath provisioner, StatefulSet volume templates |
| **Troubleshooting** | 30% | Pod debugging, log analysis, event inspection, network connectivity testing |

---

## Technical Accomplishments

### 1. Cluster Setup & Configuration

**Completed Tasks:**
- Installed MicroK8s 1.32/stable on Rocky Linux
- Configured SELinux for container runtime compatibility
- Enabled and configured essential addons:
  - `dns` (CoreDNS for service discovery)
  - `ingress` (NGINX Ingress controller)
  - `hostpath-storage` (PersistentVolume provisioner)
  - `helm3` (Package manager)
  - `cert-manager` (TLS certificate management)
- Configured firewalld rules for Kubernetes ports

**kubectl Commands Used:**
```bash
kubectl get nodes
kubectl get pods -n kube-system
kubectl get storageclass
kubectl describe node <node-name>
kubectl label node <node-name> ai-stt-tts=true
```

### 2. Workload Deployment

**Deployments Created:**
- `openwebui` - AI chat interface (Deployment)
- `pgadmin` - Database administration UI (Deployment)
- `kokoro` - Text-to-speech service (Deployment)
- `faster-whisper` - Speech-to-text service (Deployment)
- `control-portal-nginx` - Static portal page (Deployment)

**StatefulSets Created:**
- `pgvector` - PostgreSQL with vector extension (StatefulSet with PVC template)
- `redis` - Cache and session store (StatefulSet with PVC template)

**Key Manifest Patterns:**
- Used `nodeSelector` for GPU-capable workload placement
- Configured `resources.requests` and `resources.limits`
- Implemented `readinessProbe` and `livenessProbe`
- Used `envFrom` with `secretRef` for secure configuration

**kubectl Commands Used:**
```bash
kubectl apply -k k8s/clusters/vx-home/
kubectl get deployments -n ai
kubectl get statefulsets -n ai
kubectl rollout restart deployment/openwebui -n ai
kubectl rollout status deployment/openwebui -n ai
kubectl describe pod <pod-name> -n ai
```

### 3. Services & Networking

**Services Created:**
- 7 ClusterIP services for internal communication
- Path-based Ingress routing for multiple applications
- TLS termination with cert-manager certificates

**Ingress Configuration:**
- Host-based routing: `ai.adm.vx.home`, `control.adm.vx.home`, `ptnr.adm.vx.home`
- Path-based routing: `/pgadmin` prefix stripping for pgAdmin
- TLS certificates issued by self-signed CA (vx-home-ca-issuer)

**kubectl Commands Used:**
```bash
kubectl get svc -n ai
kubectl get ingress -n ai
kubectl get endpoints -n ai
kubectl describe ingress openwebui-ingress -n ai
kubectl get certificates -A
kubectl get clusterissuers
```

### 4. Storage Management

**PersistentVolumeClaims:**
- `pgvector-data` - 10Gi for PostgreSQL database
- `redis-data` - 1Gi for Redis persistence
- `openwebui-data` - 5Gi for Open WebUI file storage

**Storage Patterns:**
- Used `volumeClaimTemplates` in StatefulSets for stable storage identity
- Configured `storageClassName: microk8s-hostpath` as default
- Implemented proper `volumeMounts` for data persistence

**kubectl Commands Used:**
```bash
kubectl get pv,pvc -n ai
kubectl describe pvc pgvector-data-pgvector-0 -n ai
kubectl get storageclass
```

### 5. Configuration & Secrets

**Created:**
- Namespace `ai` for workload isolation
- Secret with PostgreSQL credentials, API keys, DATABASE_URL
- ConfigMap for pgAdmin server configuration
- Kustomize overlays for environment-specific configuration

**kubectl Commands Used:**
```bash
kubectl create namespace ai
kubectl create secret generic ai-stack-secrets --from-file=...
kubectl get secrets -n ai
kubectl describe secret ai-stack-secrets -n ai
```

### 6. Troubleshooting Workflows

**Documented and practiced:**
- Pod status investigation (`kubectl describe pod`)
- Log analysis (`kubectl logs -f`, `kubectl logs --previous`)
- Event monitoring (`kubectl get events --sort-by=.lastTimestamp`)
- Service endpoint verification (`kubectl get endpoints`)
- Network connectivity testing (DNS resolution, curl from pods)
- Certificate troubleshooting (`kubectl describe certificate`)

---

## Automation Developed

### Setup Scripts (One-Time)
| Script | Purpose |
|--------|---------|
| `01-selinux-config.sh` | Configure SELinux for MicroK8s |
| `02-install-snapd.sh` | Install snap package manager |
| `03-install-microk8s.sh` | Install and configure MicroK8s |
| `04-install-kubectl-helm.sh` | System-wide kubectl and helm |
| `05-enable-addons.sh` | Enable MicroK8s addons |
| `06-configure-cert-manager.sh` | Setup TLS CA infrastructure |
| `07-configure-firewall.sh` | Configure firewalld rules |
| `08-label-node.sh` | Label node for workload scheduling |

### Admin Scripts (Day-to-Day)
| Script | Purpose |
|--------|---------|
| `deploy.sh` | Apply/delete Kubernetes manifests |
| `status.sh` | View cluster and workload status |
| `logs.sh` | Stream application logs |
| `restart.sh` | Restart deployments/statefulsets |
| `portainer.sh` | Install/uninstall Portainer via Helm |
| `secrets.sh` | Manage secrets and credentials |
| `init-pgvector.sh` | Initialize pgvector extension |
| `test.sh` | Test DNS, Ingress, TLS |
| `clean.sh` | Clean failed/evicted pods |

### Interactive Menu
- `vx-admin.sh` - Main admin interface with submenus
- Supports both interactive selection and CLI arguments
- Color-coded output for readability

---

## Components Deployed

| Component | Type | Purpose |
|-----------|------|---------|
| Open WebUI | Deployment | ChatGPT-like AI interface with RAG support |
| PostgreSQL + pgvector | StatefulSet | Vector database for embeddings/semantic search |
| Redis | StatefulSet | Session management and caching |
| Kokoro | Deployment | High-quality text-to-speech (CPU) |
| Faster-Whisper | Deployment | Speech-to-text transcription (CPU) |
| pgAdmin | Deployment | Database administration interface |
| Portainer CE | Helm Release | Kubernetes cluster management UI |
| NGINX Ingress | DaemonSet | HTTP/HTTPS traffic routing |
| cert-manager | Deployment | TLS certificate lifecycle management |

---

## Documentation Created

1. **Architecture Overview** (`00-overview.md`) - System design and component relationships
2. **Installation Guide** (`10-microk8s-install.md`) - Detailed MicroK8s setup
3. **cert-manager Guide** (`15-cert-manager.md`) - TLS certificate configuration
4. **Portainer Setup** (`20-portainer.md`) - Cluster management UI
5. **AI Stack Config** (`30-ai-stack-openwebui.md`) - Application configuration
6. **GPU Notes** (`40-gpu-notes.md`) - Future GPU enablement planning
7. **Terraform Future** (`50-terraform-future.md`) - IaC migration path
8. **Troubleshooting** (`90-troubleshooting.md`) - Common issues and solutions
9. **Installation Walkthrough** (`INSTALLATION-WALKTHROUGH.md`) - Step-by-step commands
10. **Maintenance Guide** (`claude.md`) - Repository maintenance procedures
11. **Manual Deployment Walkthrough** (`MANUAL-DEPLOYMENT-WALKTHROUGH.md`) - Hands-on kubectl deployment guide

---

## Key Learning Outcomes

### Kubernetes Fundamentals
- Understand difference between Deployments (stateless) and StatefulSets (stateful)
- Configure pod scheduling with nodeSelector and labels
- Manage application lifecycle with rollout commands
- Use namespaces for resource isolation

### Networking
- Configure Ingress resources for external access
- Implement TLS termination with cert-manager
- Understand Service types (ClusterIP vs LoadBalancer)
- Debug DNS resolution and network connectivity

### Storage
- Provision persistent storage with PVCs
- Use volumeClaimTemplates for StatefulSet storage
- Understand StorageClass and dynamic provisioning

### Operations
- Write idempotent automation scripts
- Implement proper error handling and logging
- Create documentation for reproducibility
- Use Kustomize for configuration management

---

## Repository Statistics

```
Total Files:        54 (scripts, manifests, documentation)
Lines of Code:      ~11,900
Git Commits:        3
Scripts Created:    18
Documentation:      ~150KB
```

**Git History:**
1. `c117655` - Initial commit: Full stack infrastructure (~8,000 lines)
2. `5ece312` - Fix: MicroK8s installation script
3. `a4ed80c` - Refactor: Replace Makefile with modular shell scripts (+3,900/-355 lines)

---

---

## Session: December 24, 2025

### Completed: Manual Deployment Walkthrough

Successfully deployed the full AI stack manually using individual `kubectl` commands instead of automation scripts. This hands-on approach reinforced understanding of each Kubernetes resource type and their relationships.

**Created:** `docs/MANUAL-DEPLOYMENT-WALKTHROUGH.md` - 450+ line step-by-step guide with explanations.

### Key Concepts Learned

#### Imperative vs Declarative Commands
```bash
# Imperative - quick, no tracking
kubectl create namespace ai

# Declarative - tracked, GitOps-friendly
kubectl apply -f namespace-ai.yaml
```
The `last-applied-configuration` annotation enables 3-way merges for `kubectl apply`.

#### Setting Default Namespace Context
```bash
kubectl config set-context --current --namespace=ai
```
Eliminates need for `-n ai` on every command. Useful for CKA exam efficiency.

#### Replica Scaling and High Availability
- **Replicas alone don't guarantee HA** - pods can land on same node by default
- Requires explicit configuration:
  - `podAntiAffinity` - prevent co-location on same node
  - `topologySpreadConstraints` - even distribution across nodes
- Single-node cluster: replicas provide pod-crash resilience only, not node-failure resilience

#### PostgreSQL Major Version Upgrades
- Upgraded from PostgreSQL 16 → PostgreSQL 18
- **Key learning:** Major versions are NOT data-compatible
- PG18 cannot read PG16 data files directly
- Requires `pg_dump`/`pg_restore` or `pg_upgrade` for data migration
- Fresh install is simplest when no data exists yet

#### PVC Deletion and Finalizers
- PVCs protected by finalizers won't delete while pods reference them
- Must delete StatefulSet/Deployment first, then PVC releases
- Force delete stuck PVC: `kubectl patch pvc <name> -p '{"metadata":{"finalizers":null}}'`

#### Namespace Isolation Scope

**What namespaces DO isolate:**
- Resource naming (same name, different namespace = different resource)
- RBAC access control (with RoleBindings)
- Resource quotas and limit ranges
- Service account scope
- DNS short names (must use FQDN cross-namespace)

**What namespaces DON'T isolate (by default):**
- Network traffic (all pods can reach all pods without NetworkPolicy)
- Node resources (shared compute across all namespaces)
- Cluster-scoped resources (ClusterRoles, PVs, Nodes, StorageClasses)

#### NetworkPolicies for Network Segmentation
```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: deny-other-namespaces
  namespace: ai
spec:
  podSelector: {}
  ingress:
    - from:
        - podSelector: {}  # Same namespace only
```
Required for true network isolation between namespaces.

#### Container Image Pulling Methods
- Kubernetes pulls images automatically when scheduling pods
- Pre-pull options:
  - Temporary pod: `kubectl run pull-test --image=<image> --command -- sleep 1`
  - DaemonSet for all nodes
  - Direct runtime: `microk8s ctr image pull <image>`

### Configuration Changes Made

| Component | Change | Reason |
|-----------|--------|--------|
| pgvector | pg16 → pg18 | PostgreSQL 18 async I/O performance improvements |
| kokoro | v0.2.4 → latest | Latest TTS features |
| openwebui ingress | ai.adm.vx.home → ai.vx.home | Simplified domain structure |

### kubectl Commands Practiced

```bash
# Namespace context management
kubectl config set-context --current --namespace=ai
kubectl config view --minify | grep namespace

# Resource deletion with finalizers
kubectl patch pvc <name> -p '{"metadata":{"finalizers":null}}'

# Watch pod startup in real-time
kubectl get pods -w

# Check API resource scope (namespaced vs cluster-scoped)
kubectl api-resources --namespaced=true
kubectl api-resources --namespaced=false
```

---

## Next Steps

1. **GPU Enablement** - Configure NVIDIA device plugin for TTS/STT acceleration
2. **Monitoring** - Add Prometheus/Grafana for observability
3. **Multi-node** - Expand to HA cluster with Longhorn storage
4. **GitOps** - Implement FluxCD for automated deployments
5. **Network Policies** - Add pod-to-pod security rules

---

*Last Updated: December 24, 2025*
