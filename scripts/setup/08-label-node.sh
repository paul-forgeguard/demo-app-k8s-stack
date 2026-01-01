#!/usr/bin/env bash
#
# Script: 08-label-node.sh
# Purpose: Label node with gpu=true for GPU workload pod placement
# Prerequisites: MicroK8s running
# Author: VX Home Infrastructure
#

set -euo pipefail

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

log_info "Labeling node for GPU workloads..."

# Check MicroK8s is running
if ! microk8s status | grep -q "microk8s is running"; then
    log_error "MicroK8s is not running"
    echo ""
    log_error "Current MicroK8s status:"
    microk8s status 2>&1 | head -15 || true
    echo ""
    log_error "To fix: Run 'microk8s start' or check service with:"
    log_error "  journalctl -u snap.microk8s.daemon-kubelite.service -n 20"
    exit 1
fi

# Get node name
NODE_NAME=$(microk8s kubectl get nodes -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)

if [ -z "$NODE_NAME" ]; then
    log_error "Could not get node name"
    echo ""
    log_error "Current nodes in cluster:"
    microk8s kubectl get nodes 2>&1 || true
    echo ""
    log_error "This may indicate MicroK8s is still initializing. Wait and retry."
    exit 1
fi

log_info "Node name: $NODE_NAME"

# Label to apply
LABEL_KEY="gpu"
LABEL_VALUE="true"

# Check if label already exists
EXISTING_LABEL=$(microk8s kubectl get node "$NODE_NAME" -o jsonpath="{.metadata.labels.${LABEL_KEY}}" 2>/dev/null || echo "")

if [ "$EXISTING_LABEL" = "$LABEL_VALUE" ]; then
    log_warn "Node already has label $LABEL_KEY=$LABEL_VALUE"
else
    log_info "Applying label $LABEL_KEY=$LABEL_VALUE to node $NODE_NAME..."
    microk8s kubectl label node "$NODE_NAME" "$LABEL_KEY=$LABEL_VALUE" --overwrite
    log_info "✓ Label applied successfully"
fi

# Verify
log_info "Verifying label..."
LABELS=$(microk8s kubectl get node "$NODE_NAME" --show-labels | grep "$LABEL_KEY=$LABEL_VALUE" || echo "")

if [ -n "$LABELS" ]; then
    log_info "✓ Label verified"
else
    log_error "✗ Label not found on node"
    echo ""
    log_error "Current node labels:"
    microk8s kubectl get node "$NODE_NAME" -o jsonpath='{.metadata.labels}' 2>&1 | tr ',' '\n' || true
    echo ""
    log_error "Try applying the label manually:"
    log_error "  microk8s kubectl label node $NODE_NAME $LABEL_KEY=$LABEL_VALUE"
    exit 1
fi

echo ""
log_info "========================================="
log_info "Node labeling completed!"
log_info "========================================="
echo ""

log_info "Node labels:"
microk8s kubectl get node "$NODE_NAME" --show-labels

echo ""
log_warn "Why this label matters:"
echo "  - Kokoro (TTS) and Faster-Whisper (STT) use nodeSelector"
echo "  - They will ONLY schedule on nodes with label: gpu=true"
echo "  - Non-GPU nodes should be labeled gpu=false"
echo ""

log_info "Label usage in Deployment YAML:"
cat <<EOF
  spec:
    template:
      spec:
        nodeSelector:
          gpu: "true"  # Matches this node
EOF

echo ""
log_info "Next steps:"
echo "  1. Install Portainer: ./scripts/admin/portainer.sh install"
echo "  2. Deploy AI stack: ./scripts/admin/deploy.sh apply"
echo ""
