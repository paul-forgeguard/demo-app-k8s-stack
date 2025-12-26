#!/usr/bin/env bash
#
# Script: 07-configure-firewall.sh
# Purpose: Configure firewalld for MicroK8s and Ingress access
# Prerequisites: firewalld installed (default on Rocky/RHEL)
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

# Check sudo
if [ "$EUID" -ne 0 ]; then
    log_error "This script must be run with sudo"
    exit 1
fi

log_info "Configuring firewall for MicroK8s..."

# Check if firewalld is running
if ! systemctl is-active --quiet firewalld; then
    log_warn "firewalld is not running"
    read -p "Start firewalld? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        systemctl start firewalld
        systemctl enable firewalld
        log_info "firewalld started and enabled"
    else
        log_warn "Skipping firewall configuration (firewalld not running)"
        exit 0
    fi
fi

# Essential ports for single-node homelab
log_info "Opening essential ports for web access..."

# HTTP and HTTPS (for Ingress)
log_info "Enabling HTTP (80) and HTTPS (443) services..."
firewall-cmd --permanent --add-service=http
firewall-cmd --permanent --add-service=https

# Kubernetes API server (for remote kubectl, optional)
log_info "Opening Kubernetes API server port (16443)..."
firewall-cmd --permanent --add-port=16443/tcp

# Kubelet ports (for multi-node, future)
log_info "Opening kubelet ports (10250, 10255)..."
firewall-cmd --permanent --add-port=10250/tcp  # kubelet API
firewall-cmd --permanent --add-port=10255/tcp  # kubelet read-only

# Cluster-agent port (for multi-node, future)
log_info "Opening cluster-agent port (25000)..."
firewall-cmd --permanent --add-port=25000/tcp

# Enable masquerading (required for pod networking)
log_info "Enabling masquerading for pod networking..."
firewall-cmd --permanent --add-masquerade

# Calico CNI pod-to-pod networking (CRITICAL for MicroK8s)
# Without this, Ingress controller cannot reach backend pods
log_info "Configuring trusted zone for Calico CNI networking..."

# Add Calico virtual interfaces (cali*) to trusted zone
# This allows pod-to-pod traffic through the CNI network
firewall-cmd --zone=trusted --add-interface=cali+ --permanent

# Add MicroK8s pod network CIDR to trusted zone
# Default MicroK8s pod CIDR is 10.1.0.0/16
POD_CIDR="${POD_CIDR:-10.1.0.0/16}"
log_info "Adding pod network CIDR ($POD_CIDR) to trusted zone..."
firewall-cmd --zone=trusted --add-source="$POD_CIDR" --permanent

# Reload firewall to apply changes
log_info "Reloading firewall..."
firewall-cmd --reload

# Verification
log_info "Verifying firewall configuration..."

echo ""
log_info "========================================="
log_info "Current firewall rules:"
log_info "========================================="
firewall-cmd --list-all

echo ""
log_info "========================================="
log_info "Firewall configuration completed!"
log_info "========================================="
echo ""

log_info "Ports opened:"
echo "  - 80/tcp (HTTP)         : Ingress web access"
echo "  - 443/tcp (HTTPS)       : Ingress TLS access"
echo "  - 16443/tcp             : Kubernetes API server"
echo "  - 10250/tcp             : kubelet API"
echo "  - 10255/tcp             : kubelet read-only"
echo "  - 25000/tcp             : cluster-agent"
echo "  - Masquerading enabled  : Pod internet access"
echo ""
log_info "Calico CNI networking (trusted zone):"
echo "  - cali+ interfaces      : Pod-to-pod traffic"
echo "  - $POD_CIDR             : Pod network CIDR"
echo ""

log_warn "Security Notes:"
echo "  - These ports are open to ALL network interfaces"
echo "  - For production, consider restricting source IPs"
echo "  - HTTPS (443) requires TLS certificates (use cert-manager)"
echo ""

log_info "Next steps:"
echo "  1. Run: sudo ./scripts/setup/08-label-node.sh"
echo ""
