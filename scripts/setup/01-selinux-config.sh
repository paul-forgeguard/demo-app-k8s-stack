#!/usr/bin/env bash
#
# Script: 01-selinux-config.sh
# Purpose: Configure SELinux to permissive mode for MicroK8s
# Prerequisites: RHEL/Rocky Linux with SELinux
# Author: VX Home Infrastructure
#
# CRITICAL: This MUST be run BEFORE installing MicroK8s!
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

# Check sudo
if [ "$EUID" -ne 0 ]; then
    log_error "This script must be run with sudo"
    exit 1
fi

log_info "========================================="
log_info "SELinux Configuration for MicroK8s"
log_info "========================================="
echo ""

# Check if SELinux is available
if ! command -v getenforce &> /dev/null; then
    log_warn "SELinux tools not found (getenforce command missing)"
    log_warn "This may not be an SELinux-enabled system"
    exit 0
fi

# Get current SELinux mode
CURRENT_MODE=$(getenforce)
log_info "Current SELinux mode: $CURRENT_MODE"

# If already permissive or disabled, no action needed
if [ "$CURRENT_MODE" = "Permissive" ]; then
    log_warn "SELinux is already in Permissive mode"
    log_info "Checking if persistent configuration matches..."
elif [ "$CURRENT_MODE" = "Disabled" ]; then
    log_warn "SELinux is Disabled (not recommended, but MicroK8s will work)"
    log_info "No changes needed"
    exit 0
fi

# Explain why we're doing this
echo ""
log_warn "┌─────────────────────────────────────────────────────────┐"
log_warn "│  WHY SELINUX MUST BE PERMISSIVE FOR MICROK8S           │"
log_warn "└─────────────────────────────────────────────────────────┘"
echo ""
echo "SELinux in Enforcing mode blocks Kubernetes operations:"
echo "  • Container socket communication (docker/containerd)"
echo "  • Pod networking across nodes"
echo "  • Volume mounts from host filesystem"
echo ""
echo "Permissive mode is a compromise:"
echo "  ✓ Allows MicroK8s to function"
echo "  ✓ Still logs policy violations for audit"
echo "  ✓ Can analyze logs to create custom policies later"
echo ""
echo "Alternative (advanced): Create custom SELinux policies"
echo "  • Complex and time-consuming"
echo "  • Most K8s distros require permissive mode"
echo ""

read -p "Set SELinux to Permissive mode? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    log_warn "SELinux configuration cancelled by user"
    log_error "MicroK8s will likely fail to start with SELinux in Enforcing mode!"
    exit 1
fi

# Set runtime mode to permissive
log_info "Setting SELinux to Permissive mode (runtime)..."
if setenforce 0; then
    log_info "✓ Runtime mode set to Permissive"
else
    log_error "Failed to set SELinux to Permissive mode"
    echo ""
    log_error "Current SELinux status:"
    sestatus 2>&1 || getenforce 2>&1 || true
    echo ""
    log_error "Check for errors:"
    dmesg | grep -i selinux | tail -5 2>&1 || true
    exit 1
fi

# Verify runtime change
NEW_MODE=$(getenforce)
log_info "New runtime mode: $NEW_MODE"

# Make it persistent across reboots
log_info "Updating /etc/selinux/config for persistent configuration..."

if [ -f /etc/selinux/config ]; then
    # Backup original config
    if [ ! -f /etc/selinux/config.backup ]; then
        cp /etc/selinux/config /etc/selinux/config.backup
        log_info "Created backup: /etc/selinux/config.backup"
    fi

    # Update SELINUX=enforcing to SELINUX=permissive
    sed -i 's/^SELINUX=enforcing/SELINUX=permissive/' /etc/selinux/config
    sed -i 's/^SELINUX=disabled/SELINUX=permissive/' /etc/selinux/config

    log_info "✓ /etc/selinux/config updated"

    # Show the relevant line
    log_info "Configuration line:"
    grep "^SELINUX=" /etc/selinux/config || log_warn "Could not find SELINUX= line"
else
    log_warn "/etc/selinux/config not found (unusual)"
fi

# Verification
echo ""
log_info "========================================="
log_info "Verification"
log_info "========================================="

FINAL_MODE=$(getenforce)
log_info "Current SELinux mode: $FINAL_MODE"

if [ "$FINAL_MODE" = "Permissive" ]; then
    log_info "✓ SELinux is now in Permissive mode"
else
    log_error "✗ SELinux mode is $FINAL_MODE (expected Permissive)"
    echo ""
    log_error "Full SELinux status:"
    sestatus 2>&1 || true
    echo ""
    log_error "Config file contents:"
    grep -v "^#" /etc/selinux/config 2>&1 | grep -v "^$" || true
    exit 1
fi

# Check persistent config
if [ -f /etc/selinux/config ]; then
    CONFIG_MODE=$(grep "^SELINUX=" /etc/selinux/config | cut -d= -f2)
    log_info "Persistent configuration: SELINUX=$CONFIG_MODE"

    if [ "$CONFIG_MODE" = "permissive" ]; then
        log_info "✓ Configuration will persist across reboots"
    else
        log_warn "⚠ Configuration may not persist (check /etc/selinux/config)"
    fi
fi

# Final instructions
echo ""
log_info "========================================="
log_info "SELinux configuration completed!"
log_info "========================================="
echo ""

log_warn "Important Notes:"
echo "  • SELinux is now in Permissive mode"
echo "  • Policy violations are LOGGED but not BLOCKED"
echo "  • Check logs: ausearch -m avc (SELinux violations)"
echo "  • No reboot required (changes active immediately)"
echo ""

log_info "You can now proceed with MicroK8s installation!"
echo ""

log_info "Next steps:"
echo "  1. Run: sudo ./scripts/setup/02-install-snapd.sh"
echo ""

log_warn "To return to Enforcing mode later (advanced):"
echo "  1. setenforce 1"
echo "  2. Edit /etc/selinux/config: SELINUX=enforcing"
echo "  3. Create custom SELinux policies for MicroK8s (complex)"
echo ""
