#!/usr/bin/env bash
#
# Script: 03-install-microk8s.sh
# Purpose: Install MicroK8s via snap
# Prerequisites: snapd installed (run 02-install-snapd.sh first)
# Author: VX Home Infrastructure
#

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Check sudo
if [ "$EUID" -ne 0 ]; then
    log_error "This script must be run with sudo"
    exit 1
fi

log_info "Starting MicroK8s installation..."

# Check snapd installed
if ! command -v snap &> /dev/null; then
    log_error "snap command not found"
    echo ""
    log_error "snapd service status:"
    systemctl status snapd.socket --no-pager 2>&1 | head -10 || echo "  snapd.socket not found"
    echo ""
    log_error "To fix: Run 'sudo ./scripts/setup/02-install-snapd.sh' first"
    exit 1
fi

# MicroK8s channel (Kubernetes version)
# Options: latest/stable, 1.35/stable, 1.34/stable, 1.33/stable, etc.
# Set via environment: MICROK8S_CHANNEL=1.35/stable bash 02-install-microk8s.sh
CHANNEL="${MICROK8S_CHANNEL:-1.35/stable}"
log_info "Using MicroK8s channel: $CHANNEL"

# Step 1: Install MicroK8s
log_info "Step 1/4: Installing MicroK8s (this may take a few minutes)..."
if snap list | grep -q microk8s; then
    log_warn "MicroK8s already installed"
    CURRENT_CHANNEL=$(snap info microk8s | grep 'tracking:' | awk '{print $2}')
    log_info "Current channel: $CURRENT_CHANNEL"
    if [ "$CURRENT_CHANNEL" != "$CHANNEL" ]; then
        log_warn "Refreshing to channel: $CHANNEL"
        snap refresh microk8s --channel=$CHANNEL --classic
    fi
else
    snap install microk8s --classic --channel=$CHANNEL
    log_info "MicroK8s installed successfully"
fi

# Step 2: Add user to microk8s group
log_info "Step 2/4: Adding current user to microk8s group..."
REAL_USER="${SUDO_USER:-$USER}"
if id -nG "$REAL_USER" | grep -qw microk8s; then
    log_warn "User $REAL_USER already in microk8s group"
else
    usermod -a -G microk8s "$REAL_USER"
    log_info "User $REAL_USER added to microk8s group"
    log_warn "Group membership will take effect after logout/login or 'newgrp microk8s'"
fi

# Step 3: Set permissions on .kube directory
log_info "Step 3/4: Setting up .kube directory..."
USER_HOME=$(eval echo ~"$REAL_USER")
mkdir -p "$USER_HOME/.kube"
chown -R "$REAL_USER:$REAL_USER" "$USER_HOME/.kube"
log_info ".kube directory configured"

# Step 4: Wait for MicroK8s to be ready
log_info "Step 4/4: Waiting for MicroK8s to be ready..."
microk8s status --wait-ready
log_info "MicroK8s is ready!"

# Verification
log_info "Verifying installation..."

if microk8s status | grep -q "microk8s is running"; then
    log_info "✓ MicroK8s is running"
else
    log_error "✗ MicroK8s is not running"
    echo ""
    log_error "MicroK8s status:"
    microk8s status 2>&1 || true
    echo ""
    log_error "Kubelite service status:"
    systemctl status snap.microk8s.daemon-kubelite.service --no-pager 2>&1 | head -15 || true
    echo ""
    log_error "Recent kubelite logs:"
    journalctl -u snap.microk8s.daemon-kubelite.service --no-pager -n 20 2>&1 || true
    echo ""
    log_error "For detailed inspection: microk8s inspect"
    exit 1
fi

K8S_VERSION=$(microk8s kubectl version --short 2>/dev/null | grep 'Server Version' || echo "unknown")
log_info "✓ Kubernetes version: $K8S_VERSION"

# Check node status
NODE_STATUS=$(microk8s kubectl get nodes --no-headers 2>/dev/null | awk '{print $2}' || echo "unknown")
if [ "$NODE_STATUS" = "Ready" ]; then
    log_info "✓ Node is Ready"
else
    log_warn "✗ Node status: $NODE_STATUS (may need a moment to become Ready)"
fi

# Final instructions
echo ""
log_info "========================================="
log_info "MicroK8s installation completed!"
log_info "========================================="
echo ""
log_warn "IMPORTANT: Group membership changes require new shell session."
echo "  Option 1: Log out and log back in"
echo "  Option 2: Run 'newgrp microk8s' in current shell"
echo ""
log_info "Useful commands:"
echo "  microk8s status          # Check MicroK8s status"
echo "  microk8s kubectl get nodes  # List nodes"
echo "  microk8s kubectl get pods -A  # List all pods"
echo ""
log_info "Next steps:"
echo "  1. Run: newgrp microk8s (to activate group membership)"
echo "  2. Run: sudo ./scripts/setup/05-enable-addons.sh"
echo ""
