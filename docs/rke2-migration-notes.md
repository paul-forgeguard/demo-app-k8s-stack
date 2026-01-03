# RKE2 Migration Research Notes

Research notes comparing MicroK8s to RKE2 for potential future migration.

## RKE2 vs MicroK8s Comparison

### What You'd GAIN with RKE2

| Feature | Description |
|---------|-------------|
| **FIPS 140-2 Compliance** | Required for US government/regulated workloads |
| **CIS Hardening** | Built-in security policies, out-of-box compliance |
| **SELinux/AppArmor** | Native enforcement, not just optional |
| **etcd Datastore** | Production-grade HA datastore (vs dqlite) |
| **Air-Gap Support** | First-class offline deployment capability |
| **Windows Nodes** | Native support for mixed Linux/Windows clusters |
| **Rancher Integration** | Native management UI, GitOps with Fleet |
| **Enterprise Support** | SUSE-backed commercial support option |
| **HA Stability** | Better multi-node consensus than dqlite |

### What You'd LOSE

| Feature | Impact |
|---------|--------|
| **Snap addons** | No `microk8s enable gpu/rook-ceph/etc` - manual setup required |
| **Simplicity** | RKE2 requires more upfront configuration |
| **Single-command install** | More steps to bootstrap cluster |
| **MicroCeph integration** | Would need to reconfigure Ceph or switch to Longhorn |

---

## Migration Complexity Assessment: Medium-High

### Workload Categories

1. **Stateless apps** (OpenWebUI, Kokoro, Faster-Whisper, pgAdmin)
   - Export YAML manifests
   - Apply to RKE2 cluster
   - Relatively straightforward

2. **Stateful apps** (Redis, pgvector)
   - Need data migration via `pv-migrate` or backup/restore
   - More complex due to persistent volumes

3. **Storage Layer**
   - Rook-Ceph would need reconfiguration
   - Alternative: Switch to Longhorn (RKE2-native storage)

4. **GPU Operator**
   - Would reinstall cleanly on RKE2
   - Same NVIDIA GPU Operator works

5. **Ingress**
   - Different ingress controller configuration
   - nginx-ingress available on both

### Migration Tools

- **pv-migrate**: For migrating PersistentVolumeClaims between clusters
- **CloudCasa**: Backup and restore approach with cross-distribution compatibility
- **Velero**: Alternative backup/restore solution
- **GitOps (Fleet)**: If using GitOps, can leverage for workload deployment

---

## Quick Start: Deploy Rancher on Current Cluster

You can deploy Rancher Server on the existing MicroK8s cluster to explore the UI:

```bash
# Add Rancher Helm repo
helm repo add rancher-latest https://releases.rancher.com/server-charts/latest
helm repo update

# Create namespace
kubectl create namespace cattle-system

# Install Rancher (uses existing cert-manager)
helm install rancher rancher-latest/rancher \
  --namespace cattle-system \
  --set hostname=rancher.vx.home \
  --set bootstrapPassword=admin \
  --set ingress.tls.source=secret \
  --set replicas=1
```

Then create an Ingress for `rancher.vx.home` and you can:
- Explore the Rancher management UI
- Import the current MicroK8s cluster as a "downstream" cluster
- Test management features before committing to migration

---

## Recommended Migration Approach

1. **Phase 1: Exploration**
   - Deploy Rancher on current MicroK8s cluster
   - Learn the Rancher UI and concepts
   - Understand RKE2 architecture

2. **Phase 2: Parallel Cluster**
   - Build RKE2 cluster on separate nodes
   - Configure storage (Longhorn or Ceph)
   - Set up GPU operator

3. **Phase 3: Workload Migration**
   - Migrate stateless workloads first
   - Test thoroughly
   - Migrate stateful workloads with data

4. **Phase 4: Cutover**
   - Update DNS to point to new cluster
   - Decommission MicroK8s cluster

---

## Sources

- [RKE2: Secure, Enterprise-Ready Kubernetes](https://blog.octabyte.io/posts/hosting-and-infrastructure/rke2/rke2-secure-enterprise-ready-kubernetes-distribution/)
- [Kubernetes Distributions Overview](https://www.glukhov.org/post/2025/08/kubernetes-distributions-overview/)
- [MicroK8s HA Lessons Learned](https://www.thegalah.com/which-kubernetes-distribution-should-you-choose-lessons-from-failure)
- [Install Rancher on Kubernetes Cluster](https://ranchermanager.docs.rancher.com/getting-started/installation-and-upgrade/install-upgrade-on-a-kubernetes-cluster)
- [pv-migrate for Storage Migration](https://support.tools/migrating-rke1-to-rke2-pv-migrate/)
- [CloudCasa Migration Guide](https://support.tools/migrating-rke1-to-rke2-cloudcasa/)
