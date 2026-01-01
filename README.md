# VX Home Infrastructure - MicroK8s AI Stack

> A production-ready MicroK8s homelab featuring Open WebUI, Postgres/pgvector, Redis, Kokoro TTS, and Faster-Whisper STT on Rocky Linux.

## Overview

This repository contains a GitOps-friendly infrastructure setup for running an AI-powered homelab on MicroK8s. The stack is designed for learning Kubernetes (CKA preparation) while providing practical AI capabilities including:

- **Open WebUI** - ChatGPT-like interface with RAG support
- **Postgres + pgvector** - Vector database for embeddings and semantic search
- **Redis** - Session management and caching
- **Kokoro TTS** - High-quality text-to-speech
- **Faster-Whisper STT** - Speech-to-text transcription
- **pgAdmin** - Database administration interface
- **Portainer CE** - Kubernetes cluster management UI

## Quick Access

Once deployed, services will be available at (example FQDNs):

- **Open WebUI**: `http://ai.adm.vx.home`
- **Portainer**: `https://ptnr.adm.vx.home`
- **pgAdmin**: 'https://control.adm.vx.home/pgadmin'

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                         MicroK8s Node                        │
│                      (Rocky Linux + A2 GPU)                  │
├─────────────────────────────────────────────────────────────┤
│  Ingress (NGINX)                                            │
│    ├─ ai.vx.home        → Open WebUI                       │
│    └─ ptnr.adm.vx.home  → Portainer                        │
├─────────────────────────────────────────────────────────────┤
│  Namespace: ai                                              │
│                                                             │
│  ┌──────────────┐  ┌───────────────┐  ┌─────────────┐     │
│  │ Open WebUI   │──│ pgvector (PG) │  │   Redis     │     │
│  │ (Deployment) │  │ (StatefulSet) │  │(StatefulSet)│     │
│  └──────────────┘  └───────────────┘  └─────────────┘     │
│         │                                                   │
│         ├─────────┬─────────────────────┐                  │
│         │         │                     │                  │
│  ┌──────▼────┐  ┌─▼─────────┐  ┌───────▼────────┐         │
│  │  Kokoro   │  │  Whisper  │  │    pgAdmin     │         │
│  │   (TTS)   │  │   (STT)   │  │  (Deployment)  │         │
│  │nodeSelect:│  │nodeSelect:│  └────────────────┘         │
│  │  gpu      │  │  gpu      │                             │
│  └───────────┘  └───────────┘                             │
├─────────────────────────────────────────────────────────────┤
│  Storage: hostpath-storage (single-node PVCs)              │
└─────────────────────────────────────────────────────────────┘
```

### Design Decisions

- **CPU-only for most services**: Open WebUI and pgvector run on CPU to conserve GPU resources
- **GPU pinning for TTS/STT**: Only Kokoro and Faster-Whisper are pinned to nodes with label `gpu=true`
- **StatefulSets for databases**: Ensures stable pod identity and persistent storage
- **Kustomize for manifests**: Native kubectl integration, easier to learn than Helm
- **hostpath-storage**: Appropriate for single-node homelab (documented migration path to Longhorn/NFS for multi-node)

## Repository Structure

```
demo-app-k8s-stack/
├── README.md                          # This file
├── docs/
│   ├── 00-overview.md                 # Architecture deep-dive
│   ├── 10-microk8s-install.md         # Step-by-step installation guide
│   ├── 20-portainer.md                # Portainer setup
│   ├── 30-ai-stack-openwebui.md       # AI stack configuration
│   ├── 40-gpu-notes.md                # Future GPU enablement
│   ├── 50-terraform-future.md         # Terraform migration path
│   └── 90-troubleshooting.md          # Common issues & solutions
├── scripts/
│   ├── vx-admin.sh                    # Interactive admin menu
│   ├── setup/                         # One-time setup scripts (run as root)
│   │   ├── 01-selinux-config.sh       # SELinux setup (CRITICAL)
│   │   ├── 02-install-snapd.sh        # Snapd installation
│   │   ├── 03-install-microk8s.sh     # MicroK8s installation
│   │   ├── 04-install-kubectl-helm.sh # kubectl/helm system-wide (optional)
│   │   ├── 05-enable-addons.sh        # Enable essential addons
│   │   ├── 06-configure-cert-manager.sh # Configure TLS CA
│   │   ├── 07-configure-firewall.sh   # Firewall configuration
│   │   └── 08-label-node.sh           # Node labeling
│   ├── admin/                         # Day-to-day admin scripts
│   │   ├── deploy.sh                  # Apply/delete K8s resources
│   │   ├── status.sh                  # Check cluster status
│   │   ├── logs.sh                    # View app logs
│   │   ├── restart.sh                 # Restart apps
│   │   ├── portainer.sh               # Install/uninstall Portainer
│   │   ├── secrets.sh                 # Manage secrets
│   │   ├── init-pgvector.sh           # Initialize pgvector extension
│   │   ├── test.sh                    # DNS/Ingress tests
│   │   └── clean.sh                   # Clean failed pods
│   └── lib/
│       └── common.sh                  # Shared functions
├── k8s/
│   └── clusters/
│       └── vx-home/
│           ├── kustomization.yaml     # Main Kustomize entry
│           ├── namespace-ai.yaml      # AI namespace
│           ├── ingress/
│           │   └── openwebui-ingress.yaml
│           └── apps/
│               ├── portainer/
│               │   └── values.yaml
│               └── ai-stack/
│                   ├── kustomization.yaml
│                   ├── secrets.example.yaml
│                   ├── pgvector/
│                   ├── redis/
│                   ├── pgadmin/
│                   ├── kokoro/
│                   ├── faster-whisper/
│                   └── openwebui/
├── terraform/                         # Future Terraform modules
└── .gitignore
```

## Quickstart

### Prerequisites

- Rocky Linux (RHEL-compatible) host with:
  - Minimum 4 CPU cores, 8GB RAM
  - 100GB+ available disk space
  - Network access to the internet
  - (Optional) NVIDIA A2 GPU for future TTS/STT GPU acceleration

### Installation Steps

**CRITICAL: Read [docs/10-microk8s-install.md](docs/10-microk8s-install.md) first!**

The installation must be done in this exact order:

```bash
# 1. Configure SELinux (CRITICAL - must be first!)
sudo ./scripts/setup/01-selinux-config.sh

# 2. Install snapd
sudo ./scripts/setup/02-install-snapd.sh

# 3. Install MicroK8s
sudo ./scripts/setup/03-install-microk8s.sh

# 4. Enable addons
sudo ./scripts/setup/05-enable-addons.sh

# 5. Configure firewall
sudo ./scripts/setup/07-configure-firewall.sh

# 6. Label node for TTS/STT workloads
sudo ./scripts/setup/08-label-node.sh

# 7. Install Portainer (see docs/20-portainer.md)
./scripts/admin/portainer.sh install

# 8. Create secrets from example template
./scripts/admin/secrets.sh create
# Or manually edit: k8s/clusters/vx-home/apps/ai-stack/secrets.yaml

# 9. Deploy AI stack
./scripts/admin/deploy.sh apply

# 10. Initialize pgvector extension
./scripts/admin/init-pgvector.sh

# 11. Configure Open WebUI (see docs/30-ai-stack-openwebui.md)
# Access http://ai.vx.home and complete Admin Panel configuration
```

### DNS Configuration

Add these entries to your `/etc/hosts` or DNS server:

```
<your-node-ip> ai.vx.home
<your-node-ip> ptnr.adm.vx.home
```

Replace `<your-node-ip>` with your MicroK8s node's IP address.

## Admin Scripts

Convenient commands for common operations:

```bash
# Interactive menu (recommended)
./scripts/vx-admin.sh

# Or use scripts directly
./scripts/admin/deploy.sh apply       # Deploy all Kubernetes resources
./scripts/admin/deploy.sh delete      # Delete all resources (careful!)
./scripts/admin/status.sh             # Show status of all pods in ai namespace
./scripts/admin/portainer.sh install  # Install Portainer via Helm
./scripts/admin/init-pgvector.sh      # Initialize pgvector extension in Postgres
./scripts/admin/logs.sh openwebui     # View logs for an app
./scripts/admin/restart.sh openwebui  # Restart an app
./scripts/admin/clean.sh              # Clean failed pods
./scripts/admin/test.sh               # Run DNS/Ingress tests
```

## Key Features

### RAG (Retrieval-Augmented Generation)

- **Vector Database**: pgvector for semantic search
- **Embedding Model**: BAAI/bge-m3 (configured in Open WebUI)
- **Reranker**: BAAI/bge-reranker-v2-m3
- **Hybrid Search**: Enabled for better retrieval accuracy

### Audio Processing

- **TTS (Text-to-Speech)**: Kokoro with `af_bella` voice
- **STT (Speech-to-Text)**: Faster-Whisper with OpenAI-compatible API
- **OpenAI Integration**: Full API compatibility

### Image Generation

- **OpenAI gpt-image-1**: Via Open WebUI Pipe/Function integration
- Configure via Admin Panel → Image Generation

## Educational Value (CKA Prep)

This stack demonstrates core Kubernetes concepts tested in the CKA exam:

- ✓ Namespaces and resource isolation
- ✓ Deployments vs StatefulSets
- ✓ Services (ClusterIP, LoadBalancer)
- ✓ PersistentVolumeClaims and storage
- ✓ ConfigMaps and Secrets
- ✓ Ingress controllers
- ✓ Node selectors and affinity
- ✓ Kustomize for configuration management
- ✓ kubectl troubleshooting workflows

See [docs/00-overview.md](docs/00-overview.md) for detailed explanations.

## Important Notes

### SELinux Configuration

**CRITICAL**: MicroK8s requires SELinux in permissive mode on RHEL/Rocky systems. The `06-selinux-config.sh` script handles this, but you **must** run it before installing MicroK8s.

### Storage Limitations

The `hostpath-storage` addon is perfect for single-node setups but has limitations:

- Volumes are tied to the node (can't move between nodes)
- Volumes can grow beyond PVC capacity limits (monitor disk usage!)
- Not suitable for multi-node clusters

See [docs/40-gpu-notes.md](docs/40-gpu-notes.md) for migration path to Longhorn or NFS.

### GPU Support

Currently all services run on CPU. GPU support for TTS/STT is documented as a Phase 2 enhancement in [docs/40-gpu-notes.md](docs/40-gpu-notes.md).

## Troubleshooting

Common issues and solutions are documented in [docs/90-troubleshooting.md](docs/90-troubleshooting.md).

Quick diagnostic commands:

```bash
# Check MicroK8s status
microk8s status

# Check pod status
microk8s kubectl get pods -n ai

# Check persistent volumes
microk8s kubectl get pv,pvc -n ai

# Check ingress
microk8s kubectl get ingress -n ai

# View pod logs
microk8s kubectl logs -n ai <pod-name>

# Check node resources
microk8s kubectl top nodes
microk8s kubectl top pods -n ai
```

## Future Enhancements

Documented but not yet implemented:

1. **GPU Enablement** - NVIDIA device plugin, resource limits, time-slicing
2. **Multi-Node Scaling** - Longhorn storage, Open WebUI replicas, HA databases
3. **Terraform Migration** - IaC for DNS, certificates, infrastructure
4. **Observability** - Prometheus, Grafana, Loki
5. **GitOps** - FluxCD or ArgoCD for automated deployments

See [docs/50-terraform-future.md](docs/50-terraform-future.md) for the roadmap.

## Security Considerations

### Secrets Management

- Real secrets go in `secrets.yaml` (gitignored)
- Never commit `secrets.yaml` to version control
- Use `secrets.example.yaml` as a template
- Consider external secrets management (Vault, Sealed Secrets) for production

### Network Security

- Ingress exposes only Open WebUI and Portainer externally
- Other services (pgAdmin, databases) are ClusterIP only
- Use strong passwords for all services
- Consider cert-manager + Let's Encrypt for TLS

### Pod Security

- Run containers as non-root where possible
- Consider Pod Security Standards (restricted/baseline)
- Implement Network Policies for segmentation

## Contributing

This is a personal homelab setup, but improvements are welcome:

1. Fork the repository
2. Create a feature branch
3. Test changes thoroughly
4. Submit a pull request with clear description

## License

MIT License - See LICENSE file for details

## Resources

- [MicroK8s Documentation](https://microk8s.io/docs)
- [Open WebUI Documentation](https://docs.openwebui.com/)
- [Kubernetes Documentation](https://kubernetes.io/docs/)
- [CKA Exam Curriculum](https://training.linuxfoundation.org/certification/certified-kubernetes-administrator-cka/)
- [Kustomize Documentation](https://kustomize.io/)

## Support

For issues specific to this setup, open an issue in this repository.

For general Kubernetes questions, refer to:
- Kubernetes Slack
- Stack Overflow (tag: kubernetes)
- Reddit r/kubernetes

## Acknowledgments

- ChatGPT 5.2 for initial architecture guidance
- Claude Code for implementation refinement and CKA-focused documentation
- MicroK8s team for an excellent K8s distribution
- Open WebUI community for the fantastic AI interface
