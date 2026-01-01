#!/usr/bin/env bash
#
# Script: 16-enable-cephfs.sh
# Purpose: Enable CephFS filesystem for ReadWriteMany (RWX) storage
# Prerequisites: MicroCeph running with at least 1 OSD, rook-ceph addon enabled
# Author: VX Home Infrastructure
#

set -euo pipefail

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step() { echo -e "${BLUE}[STEP]${NC} $1"; }

echo ""
log_info "========================================="
log_info "CephFS Enablement Script"
log_info "========================================="
echo ""

# Check prerequisites
log_step "Checking prerequisites..."

if ! command -v microceph &> /dev/null; then
    log_error "MicroCeph is not installed"
    exit 1
fi

# Check if running as root (required for microceph commands)
if [[ $EUID -ne 0 ]]; then
    log_error "This script must be run as root (use sudo)"
    exit 1
fi

# Check if Ceph cluster is accessible
if ! microceph.ceph health &> /dev/null; then
    log_error "Cannot connect to Ceph cluster. Is MicroCeph running?"
    log_error "Try: snap services microceph"
    exit 1
fi
log_info "Ceph cluster is accessible"

# Check OSD count
OSD_COUNT=$(microceph.ceph osd stat 2>/dev/null | grep -oP '\d+(?= osds)' || echo "0")
if [ "$OSD_COUNT" -lt 1 ]; then
    log_error "No OSDs available. Add a disk first with: sudo microceph disk add /dev/sdX --wipe"
    exit 1
fi
log_info "Found $OSD_COUNT OSD(s)"

# Check if CephFS already exists
if microceph.ceph fs ls | grep -q "cephfs"; then
    log_warn "CephFS filesystem already exists"
    microceph.ceph fs ls
    echo ""
else
    log_step "Creating CephFS filesystem..."

    # Get pool replication size based on OSD count
    if [ "$OSD_COUNT" -eq 1 ]; then
        POOL_SIZE=1
        log_warn "Single OSD detected - using replication size 1 (no redundancy)"
    else
        POOL_SIZE=2
        log_info "Multiple OSDs detected - using replication size 2"
    fi

    # Create CephFS data pool
    log_info "Creating cephfs_data pool..."
    microceph.ceph osd pool create cephfs_data 32
    microceph.ceph osd pool set cephfs_data size $POOL_SIZE --yes-i-really-mean-it
    microceph.ceph osd pool set cephfs_data min_size 1

    # Create CephFS metadata pool
    log_info "Creating cephfs_metadata pool..."
    microceph.ceph osd pool create cephfs_metadata 16
    microceph.ceph osd pool set cephfs_metadata size $POOL_SIZE --yes-i-really-mean-it
    microceph.ceph osd pool set cephfs_metadata min_size 1

    # Create CephFS filesystem
    log_info "Creating CephFS filesystem..."
    microceph.ceph fs new cephfs cephfs_metadata cephfs_data

    log_info "CephFS filesystem created successfully"
fi

# Verify MDS is running
log_step "Verifying MDS (Metadata Server)..."
MDS_COUNT=$(microceph status | grep -c "mds" || echo "0")
if [ "$MDS_COUNT" -lt 1 ]; then
    log_warn "MDS may not be running yet. MicroCeph should start it automatically."
fi

# Wait for CephFS to become active
log_step "Waiting for CephFS to become active..."
for i in {1..30}; do
    if microceph.ceph fs status cephfs 2>/dev/null | grep -q "active"; then
        log_info "CephFS is active"
        break
    fi
    echo -n "."
    sleep 2
done
echo ""

# Show CephFS status
log_info "CephFS status:"
microceph.ceph fs status cephfs

echo ""
log_step "Creating CephFS client user for Kubernetes..."

# Create or get CephFS user
USER_NAME="client.cephfs-csi"
if microceph.ceph auth get $USER_NAME &> /dev/null; then
    log_warn "User $USER_NAME already exists"
else
    log_info "Creating user $USER_NAME..."
    microceph.ceph auth get-or-create $USER_NAME \
        mon 'allow r' \
        mgr 'allow rw' \
        osd 'allow rw pool=cephfs_data, allow rw pool=cephfs_metadata' \
        mds 'allow rw'
fi

# Get the user key
CEPHFS_KEY=$(microceph.ceph auth get-key $USER_NAME)
ADMIN_KEY=$(microceph.ceph auth get-key client.admin)

# Get cluster info
CLUSTER_ID="rook-ceph-external"
MONITORS=$(microceph.ceph mon dump -f json 2>/dev/null | jq -r '.mons[].addr' | cut -d'/' -f1 | tr '\n' ',' | sed 's/,$//')

echo ""
log_info "========================================="
log_info "CephFS Configuration Details"
log_info "========================================="
echo ""
echo "Cluster ID:     $CLUSTER_ID"
echo "Monitors:       $MONITORS"
echo "CephFS User:    $USER_NAME"
echo "Filesystem:     cephfs"
echo ""

# Generate Kubernetes secret manifests
log_step "Generating Kubernetes manifests..."

MANIFEST_DIR="/home/administrator/projects/demo-app-k8s-stack/k8s/base/storage"
mkdir -p "$MANIFEST_DIR"

# Create CephFS provisioner secret
cat > "$MANIFEST_DIR/cephfs-provisioner-secret.yaml" << EOF
apiVersion: v1
kind: Secret
metadata:
  name: rook-csi-cephfs-provisioner
  namespace: rook-ceph-external
type: kubernetes.io/rook
stringData:
  adminID: cephfs-csi
  adminKey: $CEPHFS_KEY
EOF

# Create CephFS node secret
cat > "$MANIFEST_DIR/cephfs-node-secret.yaml" << EOF
apiVersion: v1
kind: Secret
metadata:
  name: rook-csi-cephfs-node
  namespace: rook-ceph-external
type: kubernetes.io/rook
stringData:
  adminID: cephfs-csi
  adminKey: $CEPHFS_KEY
EOF

# Create CephFS StorageClass
cat > "$MANIFEST_DIR/cephfs-storageclass.yaml" << EOF
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: cephfs
provisioner: rook-ceph.cephfs.csi.ceph.com
parameters:
  clusterID: $CLUSTER_ID
  fsName: cephfs
  pool: cephfs_data
  csi.storage.k8s.io/provisioner-secret-name: rook-csi-cephfs-provisioner
  csi.storage.k8s.io/provisioner-secret-namespace: rook-ceph-external
  csi.storage.k8s.io/controller-expand-secret-name: rook-csi-cephfs-provisioner
  csi.storage.k8s.io/controller-expand-secret-namespace: rook-ceph-external
  csi.storage.k8s.io/node-stage-secret-name: rook-csi-cephfs-node
  csi.storage.k8s.io/node-stage-secret-namespace: rook-ceph-external
reclaimPolicy: Delete
allowVolumeExpansion: true
EOF

log_info "Manifests generated in: $MANIFEST_DIR"

echo ""
log_step "Applying Kubernetes manifests..."

# Apply secrets and storageclass
microk8s kubectl apply -f "$MANIFEST_DIR/cephfs-provisioner-secret.yaml"
microk8s kubectl apply -f "$MANIFEST_DIR/cephfs-node-secret.yaml"
microk8s kubectl apply -f "$MANIFEST_DIR/cephfs-storageclass.yaml"

echo ""
log_info "========================================="
log_info "CephFS Enablement Complete!"
log_info "========================================="
echo ""

# Verify
log_step "Verifying StorageClasses..."
microk8s kubectl get sc

echo ""
log_step "Testing CephFS PVC..."
microk8s kubectl apply -f - <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: test-cephfs-pvc
  namespace: default
spec:
  accessModes:
    - ReadWriteMany
  storageClassName: cephfs
  resources:
    requests:
      storage: 1Gi
EOF

echo ""
log_info "Waiting for PVC to bind..."
for i in {1..30}; do
    STATUS=$(microk8s kubectl get pvc test-cephfs-pvc -o jsonpath='{.status.phase}' 2>/dev/null || echo "Pending")
    if [ "$STATUS" = "Bound" ]; then
        log_info "Test PVC bound successfully!"
        break
    fi
    echo -n "."
    sleep 2
done
echo ""

microk8s kubectl get pvc test-cephfs-pvc

echo ""
log_step "Cleaning up test PVC..."
microk8s kubectl delete pvc test-cephfs-pvc

echo ""
log_info "========================================="
log_info "CephFS is ready for use!"
log_info "========================================="
echo ""
log_info "Storage classes available:"
microk8s kubectl get sc
echo ""
log_info "Use storageClassName: cephfs for ReadWriteMany (RWX) volumes"
log_info "Use storageClassName: ceph-rbd for ReadWriteOnce (RWO) volumes"
echo ""
