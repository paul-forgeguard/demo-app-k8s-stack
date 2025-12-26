#!/usr/bin/env bash
#
# Script: 04-install-kubectl-helm.sh
# Purpose: Install kubectl and helm3 system-wide via dnf/package manager
# Prerequisites: Internet connection
# Author: VX Home Infrastructure
#
# This installs kubectl and helm as system commands (not MicroK8s-prefixed)
# Optional: You can use microk8s kubectl and microk8s helm3 instead
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

log_info "Installing kubectl and helm3 system-wide..."

# Kubernetes version to match MicroK8s
K8S_VERSION="${K8S_VERSION:-v1.35}"
log_info "Using Kubernetes version: $K8S_VERSION"

# Step 1: Add Kubernetes repository
log_info "Step 1/6: Adding Kubernetes repository..."
cat <<EOF > /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://pkgs.k8s.io/core:/stable:/${K8S_VERSION}/rpm/
enabled=1
gpgcheck=1
gpgkey=https://pkgs.k8s.io/core:/stable:/${K8S_VERSION}/rpm/repodata/repomd.xml.key
exclude=kubelet kubeadm
EOF

log_info "Kubernetes repository added"

# Step 2: Install kubectl
log_info "Step 2/6: Installing kubectl..."
if command -v kubectl &> /dev/null; then
    CURRENT_VERSION=$(kubectl version --client --short 2>/dev/null | grep 'Client Version' || echo "unknown")
    log_warn "kubectl already installed: $CURRENT_VERSION"
    read -p "Reinstall/update? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        dnf install -y kubectl
        log_info "kubectl updated"
    else
        log_info "Skipping kubectl installation"
    fi
else
    dnf install -y kubectl
    log_info "kubectl installed successfully"
fi

# Step 3: Install Helm3
log_info "Step 3/6: Installing Helm3..."
if command -v helm &> /dev/null; then
    CURRENT_HELM=$(helm version --short 2>/dev/null || echo "unknown")
    log_warn "helm already installed: $CURRENT_HELM"
    read -p "Reinstall/update? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        log_info "Downloading and installing Helm..."
        curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
        log_info "Helm updated"
    else
        log_info "Skipping Helm installation"
    fi
else
    log_info "Downloading and installing Helm..."
    curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
    log_info "Helm installed successfully"
fi

# Step 4: Configure kubectl for MicroK8s
log_info "Step 4/6: Configuring kubectl for MicroK8s..."

# Check if MicroK8s is installed
if command -v microk8s &> /dev/null; then
    # Get the actual user (not root)
    REAL_USER="${SUDO_USER:-$USER}"
    USER_HOME=$(eval echo ~"$REAL_USER")

    log_info "Setting up kubeconfig for user: $REAL_USER"

    # Create .kube directory
    mkdir -p "$USER_HOME/.kube"

    # Export MicroK8s config to user's kubeconfig
    microk8s config > "$USER_HOME/.kube/config"

    # Set correct ownership
    chown -R "$REAL_USER:$REAL_USER" "$USER_HOME/.kube"

    # Set permissions (kubeconfig should be readable only by user)
    chmod 600 "$USER_HOME/.kube/config"

    log_info "kubectl configured to use MicroK8s cluster"
    log_info "Config written to: $USER_HOME/.kube/config"
else
    log_warn "MicroK8s not found. Install MicroK8s first, then run this script again to configure kubectl"
fi

# Step 5: Install bash-completion if needed
log_info "Step 5/6: Ensuring bash-completion is installed..."
if ! rpm -q bash-completion &>/dev/null; then
    dnf install -y bash-completion
    log_info "bash-completion installed"
else
    log_info "bash-completion already installed"
fi

# Step 6: Configure shell completion for kubectl and helm
log_info "Step 6/6: Configuring bash completion for kubectl and helm..."

# Get the actual user (not root)
REAL_USER="${SUDO_USER:-$USER}"
USER_HOME=$(eval echo ~"$REAL_USER")
USER_BASHRC="$USER_HOME/.bashrc"

# Generate system-wide completion files
log_info "Generating system-wide completion scripts..."
kubectl completion bash > /etc/bash_completion.d/kubectl
helm completion bash > /etc/bash_completion.d/helm
log_info "Completion scripts installed to /etc/bash_completion.d/"

# Add explicit sourcing to user's .bashrc for reliability
# (System lazy-loading can be unreliable on some distros)
log_info "Configuring completion for user: $REAL_USER"

# Check if completion lines already exist
if ! grep -q "kubectl completion bash" "$USER_BASHRC" 2>/dev/null; then
    cat >> "$USER_BASHRC" << 'COMPLETION_EOF'

# kubectl and helm bash completion (added by 02b-install-kubectl-helm.sh)
# See: https://kubernetes.io/docs/tasks/tools/install-kubectl-linux/
# See: https://helm.sh/docs/helm/helm_completion_bash/
if command -v kubectl &>/dev/null; then
    source <(kubectl completion bash)
    alias k=kubectl
    complete -o default -F __start_kubectl k
fi
if command -v helm &>/dev/null; then
    source <(helm completion bash)
fi
COMPLETION_EOF
    log_info "Completion configuration added to $USER_BASHRC"
else
    log_warn "Completion already configured in $USER_BASHRC"
fi

# Verification
echo ""
log_info "========================================="
log_info "Verification"
log_info "========================================="

# Check kubectl
if command -v kubectl &> /dev/null; then
    KUBECTL_VERSION=$(kubectl version --client --short 2>/dev/null | grep 'Client Version' || kubectl version --client 2>/dev/null | head -1)
    log_info "✓ kubectl installed: $KUBECTL_VERSION"

    # Test kubectl against MicroK8s
    if kubectl get nodes &> /dev/null; then
        log_info "✓ kubectl can connect to MicroK8s cluster"
        kubectl get nodes
    else
        log_warn "kubectl installed but cannot connect to cluster"
        echo ""
        log_warn "Connection details:"
        kubectl cluster-info 2>&1 | head -5 || echo "  Unable to get cluster info"
        echo ""
        log_warn "Kubeconfig location: ${KUBECONFIG:-$HOME/.kube/config}"
        log_warn "To fix: Ensure MicroK8s is running (microk8s status) and config is correct"
    fi
else
    log_error "✗ kubectl not found"
    echo ""
    log_error "Expected location: /usr/bin/kubectl"
    ls -la /usr/bin/kubectl 2>&1 || echo "  kubectl binary not found"
    echo ""
    log_error "dnf repo status:"
    dnf repolist 2>&1 | grep -i kubernetes || echo "  Kubernetes repo may not be configured"
fi

# Check helm
if command -v helm &> /dev/null; then
    HELM_VERSION=$(helm version --short 2>/dev/null || echo "unknown")
    log_info "✓ helm installed: $HELM_VERSION"
else
    log_error "✗ helm not found"
    echo ""
    log_error "Expected location: /usr/local/bin/helm"
    ls -la /usr/local/bin/helm 2>&1 || echo "  helm binary not found"
    echo ""
    log_error "To install manually: curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash"
fi

echo ""
log_info "========================================="
log_info "Installation completed!"
log_info "========================================="
echo ""

log_info "Now you can use:"
echo "  kubectl get nodes          # Instead of: microk8s kubectl get nodes"
echo "  kubectl get pods -A        # Instead of: microk8s kubectl get pods -A"
echo "  helm version               # Instead of: microk8s helm3 version"
echo ""

log_info "The admin scripts use system kubectl/helm when available."
log_info "See: ./scripts/vx-admin.sh for the interactive admin menu."
echo ""

log_warn "IMPORTANT: Reload your shell for completion to take effect:"
echo "  source ~/.bashrc"
echo ""
log_info "After reload, you can use:"
echo "  - Tab completion for kubectl and helm commands"
echo "  - 'k' as alias for kubectl (with completion)"
echo ""
log_info "Next steps:"
echo "  1. Run: sudo ./scripts/setup/07-configure-firewall.sh"
echo ""
