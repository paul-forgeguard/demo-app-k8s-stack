#!/usr/bin/env bash
#
# Script: 10-enable-microceph.sh
# Purpose: Install and configure MicroCeph with dedicated disk or loop device OSD
# Prerequisites: MicroK8s installed (run 03-install-microk8s.sh first)
# Author: VX Home Infrastructure
#
# Usage:
#   sudo ./10-enable-microceph.sh                    # Interactive - prompts for disk
#   sudo ./10-enable-microceph.sh /dev/sdb           # Use dedicated disk
#   sudo ./10-enable-microceph.sh --loop             # Use loop device (fallback)
#   MICROCEPH_DISK=/dev/sdb sudo ./10-enable-microceph.sh  # Via environment
#

set -euo pipefail

# Source common functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

# Configuration
LOOP_DIR="/var/lib/microceph-loop"
LOOP_FILE="$LOOP_DIR/osd.img"
LOOP_SIZE="${MICROCEPH_LOOP_SIZE:-50G}"
LOOP_DEVICE="/dev/loop100"
SYSTEMD_SERVICE="/etc/systemd/system/microceph-loop.service"

# Determine OSD device
USE_LOOP_DEVICE=false
OSD_DEVICE="${MICROCEPH_DISK:-}"

# Parse arguments
if [[ $# -ge 1 ]]; then
    if [[ "$1" == "--loop" ]]; then
        USE_LOOP_DEVICE=true
    elif [[ "$1" == "--help" ]] || [[ "$1" == "-h" ]]; then
        echo "Usage: $0 [DEVICE|--loop]"
        echo ""
        echo "Options:"
        echo "  /dev/sdX    Use dedicated disk (recommended)"
        echo "  --loop      Use loop device (fallback, slower)"
        echo ""
        echo "Environment variables:"
        echo "  MICROCEPH_DISK       Device to use (e.g., /dev/sdb)"
        echo "  MICROCEPH_LOOP_SIZE  Loop file size (default: 50G)"
        exit 0
    else
        OSD_DEVICE="$1"
    fi
fi

print_header "MicroCeph Installation"

# Check for root
require_root

# Check MicroK8s is installed
check_microk8s_installed || exit 1

# ============================================================================
# Step 1: Install MicroCeph Snap
# ============================================================================

log_step "Installing MicroCeph snap..."

if snap list microceph &>/dev/null; then
    log_warn "MicroCeph snap already installed"
    snap list microceph
else
    log_info "Installing MicroCeph..."
    snap install microceph --channel=latest/stable
    log_success "MicroCeph snap installed"
fi

echo ""

# ============================================================================
# Step 2: Bootstrap Cluster (if not already done)
# ============================================================================

log_step "Bootstrapping MicroCeph cluster..."

if microceph status 2>/dev/null | grep -q "ceph-mon"; then
    log_warn "MicroCeph cluster already bootstrapped"
else
    log_info "Bootstrapping single-node cluster..."
    microceph cluster bootstrap
    log_success "Cluster bootstrapped"
fi

# Show status
log_info "Current MicroCeph status:"
microceph status

echo ""

# ============================================================================
# Step 3: Determine and Configure OSD Device
# ============================================================================

# Check if OSD already exists
if microceph.ceph osd tree 2>/dev/null | grep -q "osd.0"; then
    log_warn "OSD already exists - skipping disk setup"
    microceph.ceph osd tree
else
    # If no device specified and not explicitly using loop, try to detect or prompt
    if [[ -z "$OSD_DEVICE" ]] && [[ "$USE_LOOP_DEVICE" != "true" ]]; then
        log_step "Detecting available disks..."

        # Find unused disks (no partitions, no filesystem)
        AVAILABLE_DISKS=()
        while IFS= read -r disk; do
            # Skip if disk has partitions
            if lsblk -n "$disk" | grep -q "part"; then
                continue
            fi
            # Skip if disk has filesystem
            if wipefs "$disk" 2>/dev/null | grep -q "."; then
                continue
            fi
            AVAILABLE_DISKS+=("$disk")
        done < <(lsblk -dpn -o NAME | grep -E "^/dev/(sd|vd|nvme)")

        if [[ ${#AVAILABLE_DISKS[@]} -gt 0 ]]; then
            log_info "Found available disk(s):"
            for disk in "${AVAILABLE_DISKS[@]}"; do
                SIZE=$(lsblk -dn -o SIZE "$disk")
                echo "  - $disk ($SIZE)"
            done
            echo ""

            if [[ ${#AVAILABLE_DISKS[@]} -eq 1 ]]; then
                OSD_DEVICE="${AVAILABLE_DISKS[0]}"
                log_info "Using detected disk: $OSD_DEVICE"
            else
                log_warn "Multiple disks available. Please specify one:"
                echo "  sudo $0 /dev/sdX"
                exit 1
            fi
        else
            log_warn "No unused disks detected. Falling back to loop device."
            USE_LOOP_DEVICE=true
        fi
    fi

    # ============================================================================
    # Step 3a: Setup Loop Device (if needed)
    # ============================================================================

    if [[ "$USE_LOOP_DEVICE" == "true" ]]; then
        log_step "Setting up loop device for OSD..."

        # Check if loop file already exists
        if [[ -f "$LOOP_FILE" ]]; then
            log_warn "Loop file already exists: $LOOP_FILE"
            ls -lh "$LOOP_FILE"
        else
            log_info "Creating loop directory..."
            mkdir -p "$LOOP_DIR"

            log_info "Creating $LOOP_SIZE loop file at $LOOP_FILE..."
            truncate -s "$LOOP_SIZE" "$LOOP_FILE"
            log_success "Loop file created"
        fi

        # Check if loop device is already set up
        if losetup -l | grep -q "$LOOP_FILE"; then
            EXISTING_LOOP=$(losetup -l | grep "$LOOP_FILE" | awk '{print $1}')
            log_warn "Loop device already exists: $EXISTING_LOOP"
            OSD_DEVICE="$EXISTING_LOOP"
        else
            log_info "Creating loop device..."
            OSD_DEVICE=$(losetup -f --show "$LOOP_FILE")
            log_success "Created loop device: $OSD_DEVICE"
        fi

        echo ""

        # Create Systemd Service for Loop Persistence
        log_step "Creating systemd service for loop device persistence..."

        if [[ -f "$SYSTEMD_SERVICE" ]]; then
            log_warn "Systemd service already exists"
        else
            cat > "$SYSTEMD_SERVICE" << 'EOF'
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

            systemctl daemon-reload
            systemctl enable microceph-loop.service
            log_success "Systemd service created and enabled"
        fi
    else
        # Using dedicated disk
        log_step "Using dedicated disk: $OSD_DEVICE"

        # Verify disk exists
        if [[ ! -b "$OSD_DEVICE" ]]; then
            log_error "Device $OSD_DEVICE does not exist or is not a block device"
            exit 1
        fi

        # Check if disk is clean
        if wipefs "$OSD_DEVICE" 2>/dev/null | grep -q "."; then
            log_warn "Disk $OSD_DEVICE has existing signatures"
            wipefs "$OSD_DEVICE"
            if ! confirm_action "Wipe disk $OSD_DEVICE and use for Ceph?" "n"; then
                log_error "Aborted by user"
                exit 1
            fi
        fi

        log_success "Disk $OSD_DEVICE is ready"
    fi

    echo ""

    # ============================================================================
    # Step 4: Add OSD
    # ============================================================================

    log_step "Adding OSD on $OSD_DEVICE..."

    microceph disk add "$OSD_DEVICE" --wipe
    log_success "OSD added"

    # Wait for OSD to come up
    log_info "Waiting for OSD to become active..."
    sleep 10
fi

echo ""

# ============================================================================
# Step 5: Enable rook-ceph Addon
# ============================================================================

log_step "Enabling rook-ceph addon..."

if microk8s status | grep -q "rook-ceph.*enabled"; then
    log_warn "rook-ceph addon already enabled"
else
    log_info "Enabling rook-ceph addon (this may take 2-3 minutes)..."
    microk8s enable rook-ceph

    log_info "Waiting for rook-ceph pods..."
    sleep 30

    # Wait for operator to be ready
    KUBECTL=$(get_kubectl)
    $KUBECTL wait --for=condition=Ready pods -l app=rook-ceph-operator -n rook-ceph --timeout=180s || {
        log_warn "Operator not ready yet, continuing anyway"
    }
fi

echo ""

# ============================================================================
# Step 6: Connect MicroK8s to MicroCeph
# ============================================================================

log_step "Connecting MicroK8s to MicroCeph..."

# Check if already connected
KUBECTL=$(get_kubectl)
if $KUBECTL get sc ceph-rbd &>/dev/null; then
    log_warn "Ceph storage classes already exist"
else
    log_info "Running microk8s connect-external-ceph..."
    microk8s connect-external-ceph

    log_info "Waiting for CSI pods..."
    sleep 30
fi

echo ""

# ============================================================================
# Step 7: Configure Pool for Single-Node
# ============================================================================

log_step "Configuring pool replication for single-node..."

# Check OSD count
OSD_COUNT=$(microceph.ceph osd stat 2>/dev/null | grep -oP '\d+(?= osds:)' || echo "0")

if [[ "$OSD_COUNT" -le 1 ]]; then
    log_info "Single OSD detected - configuring single-replica pools..."

    # Allow single-replica pools
    microceph.ceph config set global mon_allow_pool_size_one true

    # Set global defaults for future pools
    microceph.ceph config set global osd_pool_default_size 1
    microceph.ceph config set global osd_pool_default_min_size 1

    # Fix existing pool (if it exists)
    if microceph.ceph osd pool ls | grep -q "microk8s-rbd0"; then
        log_info "Setting microk8s-rbd0 pool to size=1..."
        microceph.ceph osd pool set microk8s-rbd0 size 1 --yes-i-really-mean-it
        microceph.ceph osd pool set microk8s-rbd0 min_size 1
    fi

    log_success "Single-node replication configured"
else
    log_info "Multiple OSDs detected ($OSD_COUNT) - keeping default replication"
fi

echo ""

# ============================================================================
# Step 8: Verify Installation
# ============================================================================

log_step "Verifying installation..."

echo ""
log_info "Ceph cluster status:"
microceph.ceph status

echo ""
log_info "OSD tree:"
microceph.ceph osd tree

echo ""
log_info "Available storage classes:"
$KUBECTL get sc

echo ""

# ============================================================================
# Final Status
# ============================================================================

print_header "Installation Complete"

log_success "MicroCeph installed and configured"
echo ""
if [[ "$USE_LOOP_DEVICE" == "true" ]]; then
    log_info "OSD configured on: loop device ($LOOP_FILE)"
    log_warn "Note: Loop device has ~30-50% I/O overhead vs dedicated disk"
else
    log_info "OSD configured on: $OSD_DEVICE (dedicated disk)"
fi
echo ""
log_info "Storage classes available:"
echo "  - ceph-rbd (ReadWriteOnce - for databases, Vault)"
echo "  - cephfs (ReadWriteMany - for shared storage)"
echo ""
log_info "Next steps:"
echo "  1. Run: sudo ./scripts/setup/11-verify-microceph.sh"
echo "  2. Then: sudo ./scripts/setup/12-install-vault.sh"
echo ""
