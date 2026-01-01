# MicroCeph Storage Architecture

> **Document Purpose:** MicroCeph installation, configuration, and operations guide
> **Storage Backend:** Ceph via MicroCeph snap + MicroK8s rook-ceph addon
> **Target:** Single-node (expandable to multi-node)

---

## Overview

MicroCeph provides enterprise-grade distributed storage through Ceph, packaged as a lightweight snap. Combined with MicroK8s's `rook-ceph` addon, it delivers:

- **CephFS**: Shared filesystem (ReadWriteMany - RWX)
- **RBD**: Block devices (ReadWriteOnce - RWO)
- **Built-in redundancy**: Configurable replication
- **Self-healing**: Automatic recovery from failures

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        MicroK8s Cluster                         │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │                    rook-ceph Addon                         │  │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────┐│  │
│  │  │ CSI Driver  │  │ CSI Driver  │  │   Rook Operator     ││  │
│  │  │  (CephFS)   │  │   (RBD)     │  │                     ││  │
│  │  └──────┬──────┘  └──────┬──────┘  └─────────────────────┘│  │
│  └─────────┼────────────────┼────────────────────────────────┘  │
│            │                │                                    │
│            ▼                ▼                                    │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │                      MicroCeph                             │  │
│  │  ┌───────────┐  ┌───────────┐  ┌────────────────────────┐ │  │
│  │  │    MON    │  │    MGR    │  │         OSD            │ │  │
│  │  │ (Monitor) │  │ (Manager) │  │  (Object Storage Dev)  │ │  │
│  │  └───────────┘  └───────────┘  └───────────┬────────────┘ │  │
│  └──────────────────────────────────────────────┼─────────────┘  │
│                                                 │                │
└─────────────────────────────────────────────────┼────────────────┘
                                                  │
                                                  ▼
                                    ┌─────────────────────────┐
                                    │   /dev/sdb (dedicated)  │
                                    │   or loop device file   │
                                    │    (block storage)      │
                                    └─────────────────────────┘
```

---

## Storage Classes

After installation, two StorageClasses become available:

| StorageClass | Access Mode | Use Case |
|--------------|-------------|----------|
| `cephfs` | ReadWriteMany (RWX) | Shared configs, logs, multi-pod access |
| `ceph-rbd` | ReadWriteOnce (RWO) | Databases, Vault, single-pod volumes |

### Which to Use?

| Application | Recommended | Reason |
|-------------|-------------|--------|
| PostgreSQL (pgvector) | `ceph-rbd` | Database requires exclusive access |
| Redis | `ceph-rbd` | Single writer pattern |
| Open WebUI | `cephfs` | Enables horizontal scaling (multiple replicas) |
| Vault | `ceph-rbd` | File-based storage backend |
| Shared configs | `cephfs` | Multiple pods reading |
| Log aggregation | `cephfs` | Multiple writers |

---

## Installation Steps

### Prerequisites

- MicroK8s installed and running
- Dedicated disk (recommended) OR 50GB+ free disk space for loop device
- Snap installed

### Step 1: Install MicroCeph Snap

```bash
sudo snap install microceph --channel=latest/stable
```

### Step 2: Bootstrap Single-Node Cluster

```bash
sudo microceph cluster bootstrap
sudo microceph status
```

Expected output:
```
MicroCeph deployment summary:
- ceph-mds: 1
- ceph-mgr: 1
- ceph-mon: 1
```

### Step 3: Add OSD

Choose one of the following options:

#### Option A: Dedicated Disk (Recommended)

Best performance. Use a dedicated virtual or physical disk:

```bash
# Identify available disks (look for one without partitions/filesystem)
lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT

# Verify disk is clean (should show no output)
sudo wipefs /dev/sdb

# Add disk directly to MicroCeph
sudo microceph disk add /dev/sdb --wipe
```

#### Option B: Loop Device (No Spare Disk)

For testing when no dedicated disk is available. Has ~30-50% I/O overhead:

```bash
# Create directory and loop file
sudo mkdir -p /var/lib/microceph-loop
sudo truncate -s 50G /var/lib/microceph-loop/osd.img

# Create loop device
LOOP_DEV=$(sudo losetup -f --show /var/lib/microceph-loop/osd.img)
echo "Created loop device: $LOOP_DEV"

# Add to MicroCeph
sudo microceph disk add $LOOP_DEV --wipe

# Create systemd service for persistence across reboots
sudo tee /etc/systemd/system/microceph-loop.service << 'EOF'
[Unit]
Description=Setup loop device for MicroCeph OSD
Before=snap.microceph.daemon.service
After=local-fs.target

[Service]
Type=oneshot
ExecStart=/sbin/losetup /dev/loop100 /var/lib/microceph-loop/osd.img
ExecStop=/sbin/losetup -d /dev/loop100
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable microceph-loop.service
```

### Step 4: Configure Single-Node Replication

**Critical for single-node clusters.** By default, Ceph pools require 3 replicas. With only 1 OSD, placement groups (PGs) will be stuck in `undersized+peered` state and storage will be unusable.

```bash
# Allow single-replica pools (required for size=1)
sudo microceph.ceph config set global mon_allow_pool_size_one true

# Set global defaults for new pools
sudo microceph.ceph config set global osd_pool_default_size 1
sudo microceph.ceph config set global osd_pool_default_min_size 1
```

> **Note:** When expanding to multi-node, you'll increase these values for redundancy.

### Step 5: Verify OSD and Health

```bash
sudo microceph.ceph status
```

Expected: `HEALTH_OK` or `HEALTH_WARN` (warn about mon insecure global_id is normal)

### Step 6: Enable rook-ceph Addon

```bash
sudo microk8s enable rook-ceph
```

Wait 2-3 minutes for pods to start:
```bash
microk8s kubectl get pods -n rook-ceph -w
```

### Step 7: Connect MicroK8s to MicroCeph

```bash
sudo microk8s connect-external-ceph
```

### Step 8: Configure Pool for Single-Node

The `connect-external-ceph` command creates pools with default replication. Fix the pools for single-node:

```bash
# Set existing pool to single replica
sudo microceph.ceph osd pool set microk8s-rbd0 size 1 --yes-i-really-mean-it
sudo microceph.ceph osd pool set microk8s-rbd0 min_size 1

# Verify health - should now show HEALTH_OK (or WARN for minor issues)
sudo microceph.ceph health
```

### Step 9: Enable CephFS (Optional - for RWX volumes)

The `connect-external-ceph` command only creates the `ceph-rbd` StorageClass. If you need ReadWriteMany (RWX) volumes for horizontal pod scaling (e.g., Open WebUI), enable CephFS:

```bash
# Run the CephFS enablement script
./scripts/setup/16-enable-cephfs.sh
```

This script:
1. Creates CephFS data and metadata pools
2. Creates the CephFS filesystem
3. Creates a dedicated CephFS user for Kubernetes
4. Generates and applies Kubernetes secrets
5. Creates the `cephfs` StorageClass
6. Tests the setup with a sample PVC

**Manual Alternative** (if script unavailable):

```bash
# 1. Create CephFS pools (adjust size based on OSD count)
sudo microceph.ceph osd pool create cephfs_data 32
sudo microceph.ceph osd pool create cephfs_metadata 16

# For single-node (size=1) or multi-node (size=2):
sudo microceph.ceph osd pool set cephfs_data size 2 --yes-i-really-mean-it
sudo microceph.ceph osd pool set cephfs_metadata size 2 --yes-i-really-mean-it

# 2. Create CephFS filesystem
sudo microceph.ceph fs new cephfs cephfs_metadata cephfs_data

# 3. Create CephFS user
sudo microceph.ceph auth get-or-create client.cephfs-csi \
    mon 'allow r' \
    osd 'allow rw pool=cephfs_data, allow rw pool=cephfs_metadata' \
    mds 'allow rw'

# 4. Get the key for Kubernetes secrets
sudo microceph.ceph auth get-key client.cephfs-csi
```

Then apply the Kubernetes manifests from `k8s/base/storage/`:
```bash
microk8s kubectl apply -f k8s/base/storage/
```

### Step 10: Verify StorageClasses

```bash
microk8s kubectl get sc
```

Expected output:
```
NAME                          PROVISIONER                    ...
ceph-rbd                      rook-ceph.rbd.csi.ceph.com    ...
cephfs                        rook-ceph.cephfs.csi.ceph.com ...
microk8s-hostpath (default)   microk8s.io/hostpath          ...
```

> **Note:** `cephfs` will only appear after running Step 9.

---

## Verification Tests

### Test CephFS (RWX)

```bash
microk8s kubectl apply -f - <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: test-cephfs
  namespace: default
spec:
  accessModes: [ReadWriteMany]
  storageClassName: cephfs
  resources:
    requests:
      storage: 1Gi
EOF

# Wait for binding
microk8s kubectl get pvc test-cephfs -w

# Cleanup
microk8s kubectl delete pvc test-cephfs
```

### Test RBD (RWO)

```bash
microk8s kubectl apply -f - <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: test-rbd
  namespace: default
spec:
  accessModes: [ReadWriteOnce]
  storageClassName: ceph-rbd
  resources:
    requests:
      storage: 1Gi
EOF

# Wait for binding
microk8s kubectl get pvc test-rbd -w

# Cleanup
microk8s kubectl delete pvc test-rbd
```

---

## Common Commands

### Cluster Status

```bash
# MicroCeph status
sudo microceph status

# Ceph health
sudo microceph.ceph status

# Detailed health
sudo microceph.ceph health detail

# OSD status
sudo microceph.ceph osd status

# Pool list
sudo microceph.ceph osd pool ls detail
```

### Kubernetes Storage

```bash
# Storage classes
microk8s kubectl get sc

# All PVCs
microk8s kubectl get pvc -A

# PV details
microk8s kubectl get pv

# CSI pods
microk8s kubectl get pods -n rook-ceph | grep csi
```

### Space Usage

```bash
# Ceph usage
sudo microceph.ceph df

# OSD usage
sudo microceph.ceph osd df

# Check disk usage (dedicated disk)
lsblk /dev/sdb

# Check loop device (if using loop device)
# df -h /var/lib/microceph-loop/
```

---

## Troubleshooting

### Health Warnings

#### `HEALTH_WARN: mon is allowing insecure global_id reclaim`

Normal for new clusters. Fix:
```bash
sudo microceph.ceph config set mon auth_allow_insecure_global_id_reclaim false
```

#### `HEALTH_WARN: 1 pool(s) have no replicas configured`

Single-node setup. Set pool size:
```bash
sudo microceph.ceph osd pool set <pool-name> size 1
sudo microceph.ceph osd pool set <pool-name> min_size 1
```

### PVC Stuck Pending

**First, check Ceph cluster health:**
```bash
sudo microceph.ceph health detail
```

**If you see "PGs inactive" or "undersized+peered":**

This means the pool replication is set higher than available OSDs. Fix:
```bash
# Check OSD count
sudo microceph.ceph osd stat

# If OSD count < pool size, reduce replication
sudo microceph.ceph config set global mon_allow_pool_size_one true
sudo microceph.ceph osd pool set microk8s-rbd0 size 1 --yes-i-really-mean-it
sudo microceph.ceph osd pool set microk8s-rbd0 min_size 1

# Verify PGs become active
sudo microceph.ceph health
```

**If Ceph is healthy, check CSI:**

1. Check CSI pods:
   ```bash
   microk8s kubectl get pods -n rook-ceph | grep csi
   ```

2. Check provisioner logs:
   ```bash
   microk8s kubectl logs -n rook-ceph -l app=csi-rbdplugin-provisioner -c csi-rbdplugin --tail=50
   ```

3. Check events:
   ```bash
   microk8s kubectl describe pvc <pvc-name>
   ```

**If you see "operation already exists" error:**

This is a stale OMAP lock. Try creating a PVC with a different name, or restart the provisioner:
```bash
microk8s kubectl rollout restart deployment/csi-rbdplugin-provisioner -n rook-ceph
```

### Loop Device Missing After Reboot

1. Check systemd service:
   ```bash
   sudo systemctl status microceph-loop.service
   ```

2. Manually recreate:
   ```bash
   sudo losetup /dev/loop100 /var/lib/microceph-loop/osd.img
   ```

3. Restart MicroCeph:
   ```bash
   sudo snap restart microceph
   ```

### OSD Down

```bash
# Check OSD status
sudo microceph.ceph osd tree

# OSD logs
sudo journalctl -u snap.microceph.osd.service
```

---

## Migration from hostpath-storage

### Strategy: Create New PVCs, Copy Data

1. **Create new PVC with Ceph:**
   ```yaml
   apiVersion: v1
   kind: PersistentVolumeClaim
   metadata:
     name: openwebui-data-ceph
     namespace: ai
   spec:
     accessModes: [ReadWriteOnce]
     storageClassName: ceph-rbd
     resources:
       requests:
         storage: 50Gi
   ```

2. **Copy data (example with temporary pod):**
   ```bash
   # Create a pod that mounts both PVCs
   # Copy data from old to new
   # Update deployment to use new PVC
   ```

3. **Update deployment:**
   ```yaml
   volumes:
   - name: data
     persistentVolumeClaim:
       claimName: openwebui-data-ceph  # Changed from openwebui-data
   ```

---

## Multi-Node Expansion

### Network Requirements

Ensure these ports are open between all Ceph nodes:

| Port | Protocol | Purpose |
|------|----------|---------|
| 7443 | TCP | MicroCeph cluster API |
| 3300 | TCP | Ceph MON (msgr2) |
| 6789 | TCP | Ceph MON (legacy) |
| 6800-7300 | TCP | Ceph OSD |

### Step 1: Install MicroCeph on New Node

```bash
# On new node
sudo snap install microceph --channel=latest/stable
```

### Step 2: Generate Join Token (From Existing Node)

```bash
# On existing node (e.g., vx-app-00)
sudo microceph cluster add <new-hostname>

# Example:
sudo microceph cluster add vx-app-01
```

This outputs a join token - save it for the next step.

### Step 3: Join Cluster (On New Node)

```bash
# On new node
sudo microceph cluster join <token>
```

### Step 4: Add OSD on New Node

```bash
# On new node
# Verify disk is available
lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT

# Add disk
sudo microceph disk add /dev/sdb --wipe
```

### Step 5: Update Pool Replication

After adding a second OSD, increase replication for redundancy:

```bash
# On any node
sudo microceph.ceph osd pool set microk8s-rbd0 size 2
sudo microceph.ceph osd pool set microk8s-rbd0 min_size 1

# Update global default for future pools
sudo microceph.ceph config set global osd_pool_default_size 2
```

**Pool Size Guidance:**

| OSDs | Recommended size | min_size | Notes |
|------|------------------|----------|-------|
| 1    | 1                | 1        | No redundancy (testing/dev) |
| 2    | 2                | 1        | Single failure tolerance |
| 3+   | 3                | 2        | Full redundancy (production) |

### Step 6: Verify Multi-Node Cluster

```bash
# Cluster status
sudo microceph status

# Ceph health
sudo microceph.ceph status

# OSD tree (shows nodes and OSDs)
sudo microceph.ceph osd tree

# Pool replication
sudo microceph.ceph osd pool ls detail
```

**Expected OSD tree for 2 nodes:**
```
ID  CLASS  WEIGHT   TYPE NAME                STATUS
-1         0.23    root default
-3         0.11        host vx-app-00
 0   ssd   0.11            osd.0              up
-5         0.11        host vx-app-01
 1   ssd   0.11            osd.1              up
```

### Removing a Node

To safely remove a node from the Ceph cluster:

```bash
# 1. Mark OSD out (starts data migration)
sudo microceph.ceph osd out <osd-id>

# 2. Wait for data migration to complete
watch sudo microceph.ceph status

# 3. Stop and remove OSD
sudo microceph.ceph osd down <osd-id>
sudo microceph.ceph osd rm <osd-id>

# 4. Remove from CRUSH map
sudo microceph.ceph osd crush rm osd.<osd-id>

# 5. Remove node from cluster
sudo microceph cluster remove <hostname>
```

---

## Maintenance

### Daily/Automatic

- Ceph self-heals degraded PGs
- Automatic rebalancing

### Weekly Check

```bash
sudo microceph.ceph status
sudo microceph.ceph health detail
df -h /var/lib/microceph-loop/
```

### Before Cluster Changes

```bash
# Disable scrubbing during maintenance
sudo microceph.ceph osd set noscrub
sudo microceph.ceph osd set nodeep-scrub

# Re-enable after
sudo microceph.ceph osd unset noscrub
sudo microceph.ceph osd unset nodeep-scrub
```

---

## References

- [MicroCeph Documentation](https://canonical-microceph.readthedocs-hosted.com/)
- [Ceph Documentation](https://docs.ceph.com/)
- [MicroK8s rook-ceph Addon](https://microk8s.io/docs/addon-rook-ceph)
- [Rook Ceph Operator](https://rook.io/docs/rook/latest/)
