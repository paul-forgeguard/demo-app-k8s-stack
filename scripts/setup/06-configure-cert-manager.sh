#!/usr/bin/env bash
#
# Script: 06-configure-cert-manager.sh
# Purpose: Configure cert-manager with a self-signed CA for homelab TLS
# Prerequisites: cert-manager addon enabled (run 05-enable-addons.sh first)
# Author: VX Home Infrastructure
#
# This creates a CA chain for issuing TLS certificates:
# 1. selfsigned-issuer (ClusterIssuer) - bootstrap issuer
# 2. vx-home-ca (Certificate) - CA certificate signed by self-signed issuer
# 3. vx-home-ca-issuer (ClusterIssuer) - CA issuer that signs all other certs
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

# Script directory (for finding YAML files)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
CERT_MANAGER_DIR="$PROJECT_ROOT/k8s/clusters/vx-home/cert-manager"

log_info "Configuring cert-manager CA for VX Home..."

# Check if cert-manager addon is enabled (creates namespace automatically)
if ! microk8s kubectl get namespace cert-manager &>/dev/null; then
    log_error "cert-manager addon is NOT enabled"
    echo ""
    log_warn "The cert-manager namespace is created automatically when you enable the addon."
    log_warn "Do NOT create it manually - use the MicroK8s addon instead."
    echo ""
    log_error "Current MicroK8s addon status:"
    microk8s status 2>&1 | grep -E "(cert-manager|addons:)" | head -5 || microk8s status --format short 2>&1 | head -20 || true
    echo ""
    log_info "To fix, run this command:"
    echo ""
    echo "    microk8s enable cert-manager"
    echo ""
    log_info "Then re-run this script:"
    echo ""
    echo "    ./scripts/setup/06-configure-cert-manager.sh"
    echo ""
    exit 1
fi

# Wait for cert-manager to be ready
log_info "Waiting for cert-manager to be ready..."

log_info "Checking cert-manager deployment..."
if ! microk8s kubectl wait --for=condition=Available deployment/cert-manager -n cert-manager --timeout=120s; then
    log_error "cert-manager deployment not ready after 120s"
    echo ""
    log_error "Pod status:"
    microk8s kubectl get pods -n cert-manager -o wide 2>&1 || true
    echo ""
    log_error "Recent events:"
    microk8s kubectl get events -n cert-manager --sort-by='.lastTimestamp' 2>&1 | tail -10 || true
    exit 1
fi

log_info "Checking cert-manager-webhook deployment..."
if ! microk8s kubectl wait --for=condition=Available deployment/cert-manager-webhook -n cert-manager --timeout=120s; then
    log_error "cert-manager-webhook deployment not ready after 120s"
    echo ""
    log_error "Pod status:"
    microk8s kubectl get pods -n cert-manager -l app=webhook -o wide 2>&1 || true
    echo ""
    log_error "Webhook logs (last 20 lines):"
    microk8s kubectl logs -n cert-manager -l app=webhook --tail=20 2>&1 || true
    exit 1
fi

log_info "Checking cert-manager-cainjector deployment..."
if ! microk8s kubectl wait --for=condition=Available deployment/cert-manager-cainjector -n cert-manager --timeout=120s; then
    log_error "cert-manager-cainjector deployment not ready after 120s"
    echo ""
    log_error "Pod status:"
    microk8s kubectl get pods -n cert-manager -l app=cainjector -o wide 2>&1 || true
    echo ""
    log_error "Cainjector logs (last 20 lines):"
    microk8s kubectl logs -n cert-manager -l app=cainjector --tail=20 2>&1 || true
    exit 1
fi

log_info "cert-manager is ready!"

# Check if ClusterIssuer manifests exist
if [ ! -f "$CERT_MANAGER_DIR/clusterissuer.yaml" ]; then
    log_error "ClusterIssuer manifest not found at: $CERT_MANAGER_DIR/clusterissuer.yaml"
    log_error "Please ensure k8s/clusters/vx-home/cert-manager/clusterissuer.yaml exists"
    exit 1
fi

# Apply ClusterIssuer configuration
log_info "Applying ClusterIssuer configuration..."
microk8s kubectl apply -f "$CERT_MANAGER_DIR/"

# Wait for CA certificate to be issued
log_info "Waiting for CA certificate to be issued..."
sleep 5  # Give cert-manager a moment to process

if ! microk8s kubectl wait --for=condition=Ready certificate/vx-home-ca -n cert-manager --timeout=60s; then
    log_error "CA certificate not ready after 60s"
    echo ""
    log_error "Certificate status:"
    microk8s kubectl describe certificate vx-home-ca -n cert-manager 2>&1 | tail -30 || true
    echo ""
    log_error "CertificateRequest status:"
    microk8s kubectl get certificaterequest -n cert-manager 2>&1 || true
    echo ""
    log_error "cert-manager logs (last 30 lines):"
    microk8s kubectl logs -n cert-manager -l app=cert-manager --tail=30 2>&1 || true
    exit 1
fi

log_info "CA certificate issued successfully!"

# Verification
echo ""
log_info "========================================="
log_info "Verification"
log_info "========================================="

# Check ClusterIssuers
log_info "ClusterIssuers:"
microk8s kubectl get clusterissuers

echo ""

# Check CA Certificate
log_info "CA Certificate:"
microk8s kubectl get certificate -n cert-manager

echo ""

# Show CA secret
log_info "CA Secret:"
microk8s kubectl get secret vx-home-ca-secret -n cert-manager

echo ""
log_info "========================================="
log_info "cert-manager CA configuration completed!"
log_info "========================================="
echo ""

log_info "Your homelab CA is ready to issue certificates."
echo ""
log_info "To use TLS in Ingress resources, add these annotations:"
echo "  metadata:"
echo "    annotations:"
echo "      cert-manager.io/cluster-issuer: \"vx-home-ca-issuer\""
echo "  spec:"
echo "    tls:"
echo "      - secretName: <your-app>-tls"
echo "        hosts:"
echo "          - <your-hostname>"
echo ""

log_info "To trust the CA on client machines:"
echo ""
echo "  # Export CA certificate"
echo "  kubectl get secret vx-home-ca-secret -n cert-manager \\"
echo "    -o jsonpath='{.data.ca\\.crt}' | base64 -d > ~/vx-home-ca.crt"
echo ""
echo "  # Linux: Trust CA system-wide"
echo "  sudo cp ~/vx-home-ca.crt /usr/local/share/ca-certificates/vx-home-ca.crt"
echo "  sudo update-ca-certificates"
echo ""
echo "  # macOS: Trust CA"
echo "  sudo security add-trusted-cert -d -r trustRoot \\"
echo "    -k /Library/Keychains/System.keychain ~/vx-home-ca.crt"
echo ""

log_info "Next steps:"
echo "  1. Run: sudo ./scripts/setup/07-configure-firewall.sh"
echo ""
