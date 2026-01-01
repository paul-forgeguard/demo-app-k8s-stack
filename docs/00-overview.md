# Architecture Overview

## Introduction

This document provides a deep-dive into the architectural decisions and design rationale for the VX Home MicroK8s AI Stack. It's written with CKA (Certified Kubernetes Administrator) learners in mind, explaining **why** certain choices were made alongside **what** was implemented.

## System Architecture

### High-Level Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                     External Access Layer                            │
│  ┌──────────────────────────────────────────────────────────┐       │
│  │  DNS / /etc/hosts                                        │       │
│  │    • ai.vx.home        → Node IP                        │       │
│  │    • ptnr.adm.vx.home  → Node IP                        │       │
│  └──────────────────────────────────────────────────────────┘       │
└─────────────────────────────────────────────────────────────────────┘
                                  │
                                  ▼
┌─────────────────────────────────────────────────────────────────────┐
│                      MicroK8s Node (Rocky Linux)                     │
│  ┌──────────────────────────────────────────────────────────┐       │
│  │  NGINX Ingress Controller                                │       │
│  │    ├─ Host: ai.vx.home → Service: openwebui:80         │       │
│  │    └─ Host: ptnr.adm.vx.home → Service: portainer:9443 │       │
│  └──────────────────────────────────────────────────────────┘       │
│                                                                      │
│  ┌──────────────────────────────────────────────────────────┐       │
│  │  Namespace: portainer                                    │       │
│  │    └─ Portainer CE (Cluster Management UI)              │       │
│  └──────────────────────────────────────────────────────────┘       │
│                                                                      │
│  ┌──────────────────────────────────────────────────────────┐       │
│  │  Namespace: ai                                           │       │
│  │                                                          │       │
│  │  ┌────────────────────────────────────────────┐         │       │
│  │  │  Frontend Layer                            │         │       │
│  │  │    • Open WebUI (Deployment, 1 replica)    │         │       │
│  │  │      - Port: 8080                          │         │       │
│  │  │      - PVC: 20Gi (hostpath)                │         │       │
│  │  └────────────────────────────────────────────┘         │       │
│  │              │          │          │                     │       │
│  │              │          │          │                     │       │
│  │  ┌───────────┴──┐  ┌───┴─────┐  ┌─┴──────────┐         │       │
│  │  │              │  │         │  │            │         │       │
│  │  │  Database    │  │ Cache   │  │  Admin UI  │         │       │
│  │  │  pgvector    │  │ Redis   │  │  pgAdmin   │         │       │
│  │  │ (StatefulSet)│  │(StatefulSet)│ (Deployment) │      │       │
│  │  │  Port: 5432  │  │Port:6379│  │  Port: 80  │         │       │
│  │  │  PVC: 50Gi   │  │PVC:10Gi │  │            │         │       │
│  │  └──────────────┘  └─────────┘  └────────────┘         │       │
│  │                                                          │       │
│  │  ┌───────────────────────────────────────┐              │       │
│  │  │  AI Services Layer                     │              │       │
│  │  │  (nodeSelector: gpu=true)             │              │       │
│  │  │                                        │              │       │
│  │  │  ┌──────────────┐  ┌───────────────┐ │              │       │
│  │  │  │   Kokoro     │  │ Faster-Whisper│ │              │       │
│  │  │  │    (TTS)     │  │     (STT)     │ │              │       │
│  │  │  │ Port: 8880   │  │  Port: 8000   │ │              │       │
│  │  │  │  CPU-only    │  │   CPU-only    │ │              │       │
│  │  │  └──────────────┘  └───────────────┘ │              │       │
│  │  └───────────────────────────────────────┘              │       │
│  └──────────────────────────────────────────────────────────┘       │
│                                                                      │
│  ┌──────────────────────────────────────────────────────────┐       │
│  │  Storage Layer (hostpath-storage addon)                  │       │
│  │    • Default storage class: microk8s-hostpath            │       │
│  │    • Location: /var/snap/microk8s/common/default-storage│       │
│  │    • Provisioner: microk8s.io/hostpath                   │       │
│  └──────────────────────────────────────────────────────────┘       │
│                                                                      │
│  ┌──────────────────────────────────────────────────────────┐       │
│  │  Network Layer                                           │       │
│  │    • CNI: Calico (MicroK8s default)                      │       │
│  │    • Pod CIDR: 10.1.0.0/16                               │       │
│  │    • Service CIDR: 10.152.183.0/24                       │       │
│  └──────────────────────────────────────────────────────────┘       │
└─────────────────────────────────────────────────────────────────────┘
```

## Design Rationale

### Why MicroK8s?

**Chosen over**: k3s, kubeadm, kind, minikube

**Reasons**:
1. **CKA Alignment**: MicroK8s closely resembles full Kubernetes, unlike lighter-weight alternatives
2. **Addon Ecosystem**: One-command addons (dns, ingress, storage) simplify setup
3. **Snap Distribution**: Easy updates and rollbacks on RHEL/Rocky systems
4. **Production-Ready**: Can scale from single-node to multi-node clusters
5. **GPU Support**: Built-in GPU addon for future Phase 2 enablement

**Trade-offs Accepted**:
- Requires snapd (not native package management)
- SELinux permissive mode required on RHEL/Rocky
- Less lightweight than k3s (but better learning platform for CKA)

### Why Kustomize Over Helm?

**Chosen over**: Raw YAML, Helm charts, Ansible

**Reasons**:
1. **Native kubectl Integration**: Kustomize is built into kubectl (kubectl apply -k)
2. **CKA Exam Relevance**: CKA tests raw YAML and kubectl knowledge, not Helm
3. **Learning Curve**: Easier to understand than Helm's templating language
4. **Transparency**: Can see exact YAML being applied (kubectl kustomize)
5. **Composition Model**: Bases + overlays pattern is intuitive for environment management

**Exception**: Portainer is installed via Helm because:
- Official installation method is Helm-based
- Demonstrates real-world hybrid approach
- Helm is still widely used in production

**Trade-offs Accepted**:
- More verbose than Helm for complex deployments
- Less powerful templating capabilities
- Community charts ecosystem is Helm-focused

### Why StatefulSets for Databases?

**Deployments vs StatefulSets Comparison**:

| Feature | Deployment | StatefulSet | Our Choice |
|---------|-----------|-------------|------------|
| Pod Identity | Random hash (openwebui-7d8f9-abc12) | Stable ordinal (pgvector-0) | StatefulSet for DBs |
| Network Identity | Unstable | Stable DNS (pgvector-0.pgvector) | StatefulSet for DBs |
| Storage | Shared PVC or separate | Dedicated PVC per pod | StatefulSet for DBs |
| Ordering | Parallel start/stop | Sequential ordered start/stop | StatefulSet for DBs |
| Scaling | Stateless scaling | Stateful scaling with guarantees | StatefulSet for DBs |

**For pgvector and Redis, we chose StatefulSets because**:
- **Stable pod names**: pgvector-0, redis-0 (easier to identify and troubleshoot)
- **Persistent identity**: Pod name stays the same across restarts
- **Ordered startup**: Database must be ready before dependent services
- **Storage binding**: PVC follows the pod (pgvector-0 always gets same PVC)

**For Open WebUI, Kokoro, Faster-Whisper, we chose Deployments because**:
- **Stateless workloads**: Can be scaled horizontally without coordination
- **Rolling updates**: Can update without downtime
- **Pod replaceability**: Any pod can serve any request (for Open WebUI with Redis)

**CKA Exam Note**: StatefulSet troubleshooting is a common exam scenario. Understanding pod naming (`<statefulset>-<ordinal>`) and PVC binding is critical.

### Why NodeSelector Over NodeAffinity?

**Comparison**:

```yaml
# NodeSelector (simple, our choice)
nodeSelector:
  gpu: "true"

# NodeAffinity (complex, more powerful)
affinity:
  nodeAffinity:
    requiredDuringSchedulingIgnoredDuringExecution:
      nodeSelectorTerms:
      - matchExpressions:
        - key: gpu
          operator: In
          values:
          - "true"
```

**We chose NodeSelector because**:
- **Simplicity**: One line vs multi-line YAML
- **Readability**: Intent is immediately clear
- **CKA Exam**: Easier to write quickly under time pressure
- **Sufficient**: Single-node setup doesn't need complex affinity rules

**When to Use NodeAffinity Instead**:
- Multiple node types with preferences (not requirements)
- "Prefer this node, but allow others" scenarios
- Complex multi-constraint scheduling
- Anti-affinity rules (spread pods across nodes)

**Migration Path**: When adding more nodes, we can replace nodeSelector with nodeAffinity for more flexibility.

### Why hostpath-storage for Single-Node?

**Storage Class Options Compared**:

| Storage Class | Use Case | Multi-Node | Shared Storage | Our Choice |
|---------------|----------|------------|----------------|------------|
| hostpath-storage | Single-node dev/homelab | ❌ No | ❌ No | ✅ Current |
| Longhorn | Production multi-node | ✅ Yes | ✅ Yes | 🔮 Phase 2 |
| NFS | Shared filesystem | ✅ Yes | ✅ Yes | 🔮 Alternative |
| Local Path | Single-node, node-tied | ⚠️ Limited | ❌ No | ❌ No benefit |
| Rook/Ceph | Large-scale storage | ✅ Yes | ✅ Yes | ❌ Overkill |

**We chose hostpath-storage because**:
- **Built-in**: MicroK8s addon, no extra setup
- **Automatic provisioning**: PVCs automatically get PVs
- **Performance**: Local disk I/O (no network overhead)
- **CKA Alignment**: Understanding PV/PVC lifecycle is tested

**Critical Limitations**:
- **Node-bound**: PVC tied to specific node (pod can't move to other nodes)
- **No size enforcement**: Volumes can grow beyond PVC capacity
- **Data loss risk**: If node dies, data is lost (no replication)

**Monitoring Requirement**:
```bash
# Check disk usage regularly
df -h /var/snap/microk8s/common/default-storage

# List PVCs and their capacity
microk8s kubectl get pvc -n ai
```

**Migration to Longhorn (Phase 2)**:
1. Install Longhorn via MicroK8s addon or Helm
2. Create new StorageClass (longhorn)
3. Backup existing data from hostpath PVCs
4. Re-create PVCs with longhorn StorageClass
5. Restore data to new PVCs
6. Update deployments to use new PVCs

### Why Separate Services Architecture?

**Monolithic vs Microservices Comparison**:

```
Monolithic (NOT our choice):
┌────────────────────────────┐
│  Single Container:         │
│   • Open WebUI             │
│   • Postgres               │
│   • Redis                  │
│   • TTS                    │
│   • STT                    │
└────────────────────────────┘
Problems:
- Can't scale components independently
- Updates require restarting everything
- Resource limits apply to entire pod
- Hard to troubleshoot failures

Microservices (Our choice):
┌─────────┐  ┌──────────┐  ┌───────┐
│ WebUI   │  │ Postgres │  │ Redis │
└─────────┘  └──────────┘  └───────┘
     │            │             │
     └─────┬──────┴─────────────┘
           │
     ┌─────┴──────┐
     │ TTS + STT  │
     └────────────┘
Benefits:
- Independent scaling
- Isolated failures
- Resource optimization
- Service-level updates
```

**We chose separate services because**:
- **Scalability**: Can scale Open WebUI replicas without scaling databases
- **Resource Management**: Can apply different resource limits per service
- **Failure Isolation**: Postgres restart doesn't affect Redis
- **CKA Alignment**: Service discovery, DNS, networking concepts are tested

**Service Discovery in Kubernetes**:

When Open WebUI connects to `postgresql://openwebui:password@pgvector:5432/openwebui`:
1. DNS query for "pgvector" → CoreDNS
2. CoreDNS resolves `pgvector.ai.svc.cluster.local` → Service ClusterIP
3. Service forwards to pod IP via iptables/IPVS
4. Connection established to pgvector-0 pod

This is fundamental K8s networking that CKA tests extensively.

### Why CPU-Only for Most Services?

**Resource Allocation Strategy**:

| Service | CPU/GPU | Reason |
|---------|---------|--------|
| Open WebUI | CPU | Lightweight web interface, GPU not beneficial |
| pgvector | CPU | Database operations, CPU-bound for queries |
| Redis | CPU | In-memory cache, CPU-bound for operations |
| pgAdmin | CPU | Admin UI, minimal resources needed |
| Kokoro TTS | CPU now, GPU Phase 2 | Pinned to gpu node for future GPU |
| Faster-Whisper STT | CPU now, GPU Phase 2 | Pinned to gpu node for future GPU |

**GPU Challenges on A2 (Single GPU)**:
- Default K8s scheduling: entire GPU to one pod
- Running both TTS + STT on GPU requires:
  - GPU time-slicing (complex NVIDIA setup), OR
  - MIG (Multi-Instance GPU, A2 doesn't support), OR
  - Serial scheduling (only one at a time)

**Phase 2 GPU Strategy** (documented in [40-gpu-notes.md](40-gpu-notes.md)):
1. Enable MicroK8s GPU addon
2. Choose ONE service (TTS or STT) for GPU
3. OR implement NVIDIA time-slicing for sharing
4. Add resource limits: `nvidia.com/gpu: 1`

**CKA Note**: Resource limits and requests are heavily tested. Understanding CPU/memory/GPU scheduling is critical.

## Networking Architecture

### Service Types Explained

| Service Type | Use Case | Our Usage |
|--------------|----------|-----------|
| ClusterIP (default) | Internal-only access | pgvector, redis, pgadmin, kokoro, faster-whisper, openwebui |
| NodePort | External access via node IP:port | Not used (Ingress is cleaner) |
| LoadBalancer | Cloud load balancer or MetalLB | Portainer (could use for Open WebUI) |
| ExternalName | CNAME to external service | Not needed |

**Why ClusterIP for Almost Everything**:
- **Security**: Services not exposed outside cluster
- **Ingress Abstraction**: Single entry point (NGINX) handles external routing
- **DNS**: Services accessible via stable DNS names internally
- **CKA Pattern**: Most real-world K8s uses ClusterIP + Ingress

**How Ingress Works**:

```
User → http://ai.vx.home → Ingress Controller (NGINX)
  → Ingress Rule (host: ai.vx.home)
  → Service (openwebui:80)
  → Pod (openwebui-*)
```

**CKA Exam Tip**: Be able to troubleshoot Ingress issues:
```bash
# Check Ingress resource
kubectl get ingress -n ai
kubectl describe ingress openwebui -n ai

# Check Ingress controller pods
kubectl get pods -n ingress

# Check Service endpoints
kubectl get endpoints -n ai
```

### Network Policies (Not Yet Implemented)

**Future Enhancement**:

```yaml
# Example: Restrict pgvector to only accept from Open WebUI
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: pgvector-policy
  namespace: ai
spec:
  podSelector:
    matchLabels:
      app: pgvector
  policyTypes:
  - Ingress
  ingress:
  - from:
    - podSelector:
        matchLabels:
          app: openwebui
    ports:
    - protocol: TCP
      port: 5432
```

**Why Not Implemented Yet**:
- Single-node homelab (less security risk)
- CKA focuses on NetworkPolicy concepts, not production-level policies
- Can be added incrementally for learning

## Configuration Management

### Why ConfigMaps for pgAdmin Servers.json?

**ConfigMap vs Secret Comparison**:

| Data Type | Storage | Our Usage |
|-----------|---------|-----------|
| ConfigMap | Plain text config | pgadmin servers.json (no secrets) |
| Secret | Base64-encoded sensitive data | Passwords, API keys |

**pgAdmin servers.json in ConfigMap**:
```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: pgadmin-servers
data:
  servers.json: |
    {
      "Servers": {
        "1": {
          "Name": "pgvector",
          "Host": "pgvector",  # K8s Service DNS
          "Port": 5432,
          "Username": "openwebui"  # Password prompted at runtime
        }
      }
    }
```

**Why ConfigMap, not Secret**:
- **No sensitive data**: Server connection info is not secret (passwords come from env vars)
- **Easier to edit**: `kubectl edit configmap pgadmin-servers`
- **Transparency**: Plain text, easier to debug

**When to Use Secrets Instead**:
- Database passwords
- API keys (OpenAI, etc.)
- TLS certificates
- Authentication tokens

**CKA Exam Tip**: Understand ConfigMap vs Secret use cases and how to mount them:
```yaml
# ConfigMap as volume
volumes:
- name: config
  configMap:
    name: pgadmin-servers

# Secret as environment variable
env:
- name: DB_PASSWORD
  valueFrom:
    secretKeyRef:
      name: ai-secrets
      key: POSTGRES_PASSWORD
```

### Why secrets.example.yaml Pattern?

**Secrets Management Strategy**:

1. **secrets.example.yaml** (tracked in Git):
   - Template with placeholder values
   - Documents required secrets
   - No real credentials

2. **secrets.yaml** (gitignored):
   - Real secrets (copied from example)
   - User edits with actual passwords/keys
   - Never committed to Git

3. **.gitignore** entry:
   ```
   secrets.yaml
   ```

**Workflow**:
```bash
# User creates real secrets from template
cp k8s/clusters/vx-home/apps/ai-stack/secrets.example.yaml \
   k8s/clusters/vx-home/apps/ai-stack/secrets.yaml

# Edit with real values
vim k8s/clusters/vx-home/apps/ai-stack/secrets.yaml

# Apply (Git never sees real secrets)
kubectl apply -f k8s/clusters/vx-home/apps/ai-stack/secrets.yaml
```

**Production Alternatives** (Phase 2+):
- **Sealed Secrets**: Encrypt secrets for Git storage
- **External Secrets Operator**: Sync from Vault/AWS Secrets Manager
- **Helm Secrets**: SOPS-encrypted values files
- **GitOps with Vault**: FluxCD + Vault integration

## Observability & Monitoring (Future)

**Current State**: Basic kubectl commands

**Phase 2 Enhancements**:

1. **Metrics Server**:
   ```bash
   microk8s enable metrics-server
   microk8s kubectl top nodes
   microk8s kubectl top pods -n ai
   ```

2. **Prometheus + Grafana**:
   ```bash
   microk8s enable observability
   # Provides Prometheus, Grafana, Loki
   ```

3. **Logging**:
   - Loki for log aggregation
   - FluentBit for log shipping
   - Grafana for visualization

4. **Alerting**:
   - PrometheusRule for alert definitions
   - Alertmanager for routing
   - Slack/email notifications

## Security Hardening (Future)

**Current State**: Basic security (secrets, network isolation)

**Phase 2 Security Enhancements**:

1. **Pod Security Standards**:
   ```yaml
   apiVersion: v1
   kind: Namespace
   metadata:
     name: ai
     labels:
       pod-security.kubernetes.io/enforce: baseline
   ```

2. **Network Policies**: Restrict pod-to-pod communication

3. **RBAC**: Least-privilege service accounts

4. **TLS**:
   - cert-manager for Let's Encrypt certificates
   - Ingress TLS termination
   - Internal TLS for databases

5. **Image Security**:
   - Image scanning (Trivy)
   - Admission controllers (OPA Gatekeeper)
   - Image signing verification

## Learning Objectives (CKA Alignment)

This architecture demonstrates these CKA exam domains:

### Cluster Architecture, Installation & Configuration (25%)
- ✓ MicroK8s installation and configuration
- ✓ Addon management
- ✓ Storage class configuration

### Workloads & Scheduling (15%)
- ✓ Deployments vs StatefulSets
- ✓ NodeSelector for pod placement
- ✓ Resource limits and requests

### Services & Networking (20%)
- ✓ Service types (ClusterIP, LoadBalancer)
- ✓ Ingress configuration
- ✓ DNS service discovery
- ✓ Network troubleshooting

### Storage (10%)
- ✓ PersistentVolume and PersistentVolumeClaim
- ✓ StorageClass and dynamic provisioning
- ✓ Volume modes and access modes

### Troubleshooting (30%)
- ✓ Pod logs (kubectl logs)
- ✓ Resource status (kubectl get, describe)
- ✓ Network debugging
- ✓ Storage issues

## Conclusion

This architecture balances **learning value** (CKA preparation) with **practical utility** (functional AI homelab). Design decisions prioritize:

1. **Simplicity**: Clear, understandable patterns (nodeSelector over nodeAffinity)
2. **CKA Alignment**: Real-world K8s patterns tested in the exam
3. **Scalability**: Migration path to multi-node documented
4. **Reproducibility**: GitOps-friendly, declarative configuration

The next steps are in [10-microk8s-install.md](10-microk8s-install.md) for installation and [30-ai-stack-openwebui.md](30-ai-stack-openwebui.md) for application configuration.
