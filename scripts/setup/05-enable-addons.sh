#!/usr/bin/env bash
#
# Script: 05-enable-addons.sh
# Purpose: Enable essential MicroK8s addons for AI stack
# Prerequisites: MicroK8s installed (run 03-install-microk8s.sh first)
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

log_info "Enabling MicroK8s addons..."

# Check MicroK8s is installed
if ! command -v microk8s &> /dev/null; then
    log_error "MicroK8s not found"
    echo ""
    log_error "snap packages installed:"
    snap list 2>&1 | head -10 || echo "  snap not available"
    echo ""
    log_error "To fix: Run 'sudo ./scripts/setup/03-install-microk8s.sh' first"
    exit 1
fi

# Check MicroK8s is running
if ! microk8s status | grep -q "microk8s is running"; then
    log_error "MicroK8s is not running"
    echo ""
    log_error "Current MicroK8s status:"
    microk8s status 2>&1 || true
    echo ""
    log_error "To fix: Run 'microk8s start' or check service logs with:"
    log_error "  journalctl -u snap.microk8s.daemon-kubelite.service -n 30"
    exit 1
fi

# Addon list
ADDONS=(
    "dns"                # CoreDNS for service discovery
    "ingress"            # NGINX Ingress Controller
    "hostpath-storage"   # PersistentVolume provisioner
    "helm3"              # Helm package manager
    "cert-manager"       # TLS certificate management
)

# Optional addons (commented out, can enable later)
OPTIONAL_ADDONS=(
    # "metrics-server"   # kubectl top command support
    # "metallb"          # LoadBalancer IP allocation
    # "observability"    # Prometheus + Grafana + Loki
)

log_info "Required addons to enable: ${ADDONS[*]}"

# Enable each addon
for addon in "${ADDONS[@]}"; do
    log_info "Enabling addon: $addon..."

    if microk8s status | grep -q "$addon: enabled"; then
        log_warn "$addon already enabled"
    else
        if microk8s enable "$addon"; then
            log_info "✓ $addon enabled successfully"
        else
            log_error "✗ Failed to enable $addon"
            echo ""
            log_error "Current addon status:"
            microk8s status 2>&1 | head -30 || true
            echo ""
            log_error "Check MicroK8s logs:"
            log_error "  journalctl -u snap.microk8s.daemon-kubelite.service -n 20"
            exit 1
        fi
    fi

    echo ""
done

# Wait for addons to be ready
log_info "Waiting for addons to be ready..."
sleep 10

# Verification
log_info "Verifying addons..."

# Check DNS (CoreDNS)
if microk8s kubectl get pods -n kube-system -l k8s-app=kube-dns --no-headers 2>/dev/null | grep -q Running; then
    log_info "✓ DNS (CoreDNS) is running"
else
    log_warn "✗ DNS pods not running yet (may need more time)"
fi

# Check Ingress
if microk8s kubectl get pods -n ingress --no-headers 2>/dev/null | grep -q Running; then
    log_info "✓ Ingress controller is running"
else
    log_warn "✗ Ingress controller not running yet (may need more time)"
fi

# Check hostpath-storage
if microk8s kubectl get storageclass 2>/dev/null | grep -q microk8s-hostpath; then
    log_info "✓ Storage class 'microk8s-hostpath' available"
else
    log_error "✗ Storage class not found"
fi

# Check Helm3
if command -v microk8s.helm3 &> /dev/null || command -v microk8s &> /dev/null && microk8s helm3 version &> /dev/null; then
    HELM_VERSION=$(microk8s helm3 version --short 2>/dev/null || echo "unknown")
    log_info "✓ Helm3 available: $HELM_VERSION"
else
    log_warn "✗ Helm3 not available"
fi

# Check cert-manager
if microk8s kubectl get pods -n cert-manager --no-headers 2>/dev/null | grep -q Running; then
    log_info "✓ cert-manager is running"
else
    log_warn "✗ cert-manager pods not running yet (may need more time)"
fi

# Get IngressClass name (needed for Ingress resources)
INGRESS_CLASS=$(microk8s kubectl get ingressclass -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
if [ -n "$INGRESS_CLASS" ]; then
    log_info "✓ IngressClass name: $INGRESS_CLASS"
    log_info "  (Use this in Ingress resources: spec.ingressClassName: $INGRESS_CLASS)"
else
    log_warn "✗ IngressClass not found (Ingress may not work)"
fi

# Final status
echo ""
log_info "========================================="
log_info "Addon enablement completed!"
log_info "========================================="
echo ""

log_info "Current addon status:"
microk8s status | grep -A 50 "addons:"

echo ""
log_info "Optional addons (can enable later):"
for addon in "${OPTIONAL_ADDONS[@]}"; do
    addon_name=$(echo "$addon" | sed 's/#//g' | xargs)
    echo "  - $addon_name"
done
echo ""

log_info "To enable optional addons:"
echo "  microk8s enable <addon-name>"
echo ""

log_info "Next steps:"
echo "  1. Run: sudo ./scripts/setup/06-configure-cert-manager.sh"
echo "  2. Run: sudo ./scripts/setup/07-configure-firewall.sh"
echo ""
