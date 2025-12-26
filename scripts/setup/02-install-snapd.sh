#!/usr/bin/env bash
#
# Script: 02-install-snapd.sh
# Purpose: Install snapd on Rocky/RHEL Linux for MicroK8s installation
# Prerequisites: sudo access, internet connection
# Author: VX Home Infrastructure
#

set -euo pipefail  # Exit on error, undefined vars, pipe failures

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if running as root or with sudo
if [ "$EUID" -ne 0 ]; then
    log_error "This script must be run with sudo"
    echo "Usage: sudo bash $0"
    exit 1
fi

log_info "Starting snapd installation for Rocky/RHEL Linux..."

# Step 1: Install EPEL repository
log_info "Step 1/5: Installing EPEL repository..."
if dnf repolist | grep -q epel; then
    log_warn "EPEL repository already installed"
else
    dnf install -y epel-release
    log_info "EPEL repository installed successfully"
fi

# Step 2: Install snapd
log_info "Step 2/5: Installing snapd package..."
if command -v snap &> /dev/null; then
    log_warn "snapd already installed"
else
    dnf install -y snapd
    log_info "snapd package installed successfully"
fi

# Step 3: Enable and start snapd socket
log_info "Step 3/5: Enabling and starting snapd.socket..."
systemctl enable --now snapd.socket
log_info "snapd.socket enabled and started"

# Step 4: Create symbolic link for classic snaps
log_info "Step 4/5: Creating symbolic link /snap -> /var/lib/snapd/snap..."
if [ -L /snap ]; then
    log_warn "Symbolic link /snap already exists"
elif [ -d /snap ]; then
    log_warn "/snap exists as directory (not symlink), removing and recreating..."
    rmdir /snap || rm -rf /snap
    ln -s /var/lib/snapd/snap /snap
    log_info "Symbolic link created"
else
    ln -s /var/lib/snapd/snap /snap
    log_info "Symbolic link created"
fi

# Step 5: Add snap to PATH
log_info "Step 5/5: Adding snap binaries to PATH..."
if [ -f /etc/profile.d/snapd.sh ]; then
    log_warn "/etc/profile.d/snapd.sh already exists"
else
    echo 'export PATH=$PATH:/snap/bin' > /etc/profile.d/snapd.sh
    log_info "Created /etc/profile.d/snapd.sh"
fi

# Source the profile (for current session)
export PATH=$PATH:/snap/bin

# Verification
log_info "Verifying installation..."

if systemctl is-active --quiet snapd.socket; then
    log_info "✓ snapd.socket is active"
else
    log_error "✗ snapd.socket is not active"
    echo ""
    log_error "Service status:"
    systemctl status snapd.socket --no-pager 2>&1 | head -15 || true
    echo ""
    log_error "Journal logs (last 20 lines):"
    journalctl -u snapd.socket --no-pager -n 20 2>&1 || true
    exit 1
fi

if command -v snap &> /dev/null; then
    SNAP_VERSION=$(snap version | head -n1)
    log_info "✓ snap command available: $SNAP_VERSION"
else
    log_error "✗ snap command not found in PATH"
    echo ""
    log_error "Current PATH: $PATH"
    log_error "Checking if snapd binary exists:"
    ls -la /snap/bin/snap 2>&1 || ls -la /var/lib/snapd/snap/bin/snap 2>&1 || echo "  snap binary not found"
    echo ""
    log_warn "To fix: Log out and back in, or run: source /etc/profile.d/snapd.sh"
    exit 1
fi

# Final instructions
echo ""
log_info "========================================="
log_info "snapd installation completed successfully!"
log_info "========================================="
echo ""
log_warn "IMPORTANT: To use snap commands in your current session, run:"
echo "  source /etc/profile.d/snapd.sh"
echo ""
log_warn "Or simply log out and log back in."
echo ""
log_info "Next steps:"
echo "  1. Run: sudo ./scripts/setup/03-install-microk8s.sh"
echo ""
