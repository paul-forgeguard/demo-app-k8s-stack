#!/usr/bin/env bash
#
# 09-enable-gpu.sh - Enable NVIDIA GPU support in MicroK8s
#
# This script enables GPU support via Helm install of the NVIDIA GPU Operator.
# The built-in 'microk8s enable nvidia' addon often fails, so we use the
# manual Helm approach with MicroK8s-specific containerd settings.
#
# Prerequisites:
#   - NVIDIA driver installed on host (nvidia-smi should work)
#   - MicroK8s installed and running
#   - Helm addon enabled (microk8s enable helm3)
#
# Usage:
#   ./scripts/setup/09-enable-gpu.sh
#
# What this script does:
#   1. Verifies NVIDIA driver is installed
#   2. Adds the NVIDIA Helm repository
#   3. Installs the GPU Operator with MicroK8s containerd paths
#   4. Creates the nvidia runtime config for containerd
#   5. Optionally configures GPU time-slicing for sharing
#

set -euo pipefail

# Source common functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

# ============================================================================
# CONFIGURATION
# ============================================================================

GPU_OPERATOR_NAMESPACE="gpu-operator"
WAIT_TIMEOUT=600  # 10 minutes (GPU operator pods can be slow)
GPU_TIME_SLICE_REPLICAS=2  # Number of virtual GPUs per physical GPU

# ============================================================================
# FUNCTIONS
# ============================================================================

check_nvidia_driver() {
    print_header "Checking NVIDIA Driver"

    if ! command -v nvidia-smi &>/dev/null; then
        print_error "nvidia-smi not found. Install NVIDIA driver first."
        print_info "On Rocky Linux: sudo dnf install nvidia-driver nvidia-driver-cuda"
        return 1
    fi

    print_info "NVIDIA driver status:"
    nvidia-smi --query-gpu=name,driver_version,memory.total --format=csv,noheader
    echo

    print_success "NVIDIA driver is installed"
}

check_microk8s() {
    print_header "Checking MicroK8s"

    if ! command -v microk8s &>/dev/null; then
        print_error "microk8s not found. Install MicroK8s first."
        return 1
    fi

    if ! microk8s status --wait-ready &>/dev/null; then
        print_error "MicroK8s is not running"
        return 1
    fi

    local version
    version=$(microk8s version | head -1)
    print_success "MicroK8s is running: $version"
}

check_gpu_operator_installed() {
    print_header "Checking Current GPU Operator Status"

    if helm list -n "$GPU_OPERATOR_NAMESPACE" 2>/dev/null | grep -q "gpu-operator"; then
        print_warning "GPU Operator is already installed"
        print_info "Checking GPU operator pods..."
        kubectl get pods -n "$GPU_OPERATOR_NAMESPACE" 2>/dev/null || true
        return 0
    fi

    print_info "GPU Operator is not installed"
    return 1
}

add_nvidia_helm_repo() {
    print_header "Adding NVIDIA Helm Repository"

    if helm repo list 2>/dev/null | grep -q "nvidia"; then
        print_info "NVIDIA Helm repo already exists, updating..."
        helm repo update nvidia
    else
        print_info "Adding NVIDIA Helm repository..."
        helm repo add nvidia https://helm.ngc.nvidia.com/nvidia
        helm repo update
    fi

    print_success "NVIDIA Helm repository ready"
}

install_gpu_operator() {
    print_header "Installing NVIDIA GPU Operator via Helm"

    print_info "This may take 5-10 minutes..."
    print_info "Installing with MicroK8s-specific containerd paths..."
    print_info "  - driver.enabled=false (using host driver)"
    print_info "  - toolkit paths for snap-based containerd"
    echo

    helm install gpu-operator nvidia/gpu-operator \
        --namespace "$GPU_OPERATOR_NAMESPACE" \
        --create-namespace \
        --set driver.enabled=false \
        --set toolkit.env[0].name=CONTAINERD_CONFIG \
        --set toolkit.env[0].value=/var/snap/microk8s/current/args/containerd-template.toml \
        --set toolkit.env[1].name=CONTAINERD_SOCKET \
        --set toolkit.env[1].value=/var/snap/microk8s/common/run/containerd.sock \
        --set toolkit.env[2].name=CONTAINERD_RUNTIME_CLASS \
        --set toolkit.env[2].value=nvidia \
        --timeout 10m

    print_success "GPU Operator Helm release installed"
}

create_nvidia_runtime_config() {
    print_header "Creating NVIDIA Runtime Config for containerd"

    print_info "Creating /etc/containerd/conf.d/99-nvidia.toml..."
    print_warning "This requires sudo access"

    # Create the directory if it doesn't exist
    sudo mkdir -p /etc/containerd/conf.d

    # Create the nvidia runtime config
    # This is CRITICAL for MicroK8s - the GPU Operator's toolkit creates a broken
    # config file with unexpanded ${RUNTIME} variables. We create a minimal working config.
    sudo tee /etc/containerd/conf.d/99-nvidia.toml > /dev/null << 'EOF'
version = 2

[plugins."io.containerd.grpc.v1.cri".containerd.runtimes.nvidia]
  runtime_type = "io.containerd.runc.v2"
  [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.nvidia.options]
    BinaryName = "/usr/local/nvidia/toolkit/nvidia-container-runtime"
EOF

    print_success "NVIDIA runtime config created"
    print_info "Restarting containerd..."

    sudo snap restart microk8s.daemon-containerd

    # Wait for containerd to be ready
    sleep 5

    print_success "containerd restarted with nvidia runtime"
}

configure_gpu_time_slicing() {
    print_header "Configuring GPU Time-Slicing"

    print_info "Time-slicing allows multiple pods to share a single GPU"
    print_info "Configuring $GPU_TIME_SLICE_REPLICAS virtual GPUs per physical GPU"
    echo

    # Create the time-slicing ConfigMap
    kubectl apply -n "$GPU_OPERATOR_NAMESPACE" -f - << EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: time-slicing-config
  namespace: $GPU_OPERATOR_NAMESPACE
data:
  any: |-
    version: v1
    flags:
      migStrategy: none
    sharing:
      timeSlicing:
        resources:
        - name: nvidia.com/gpu
          replicas: $GPU_TIME_SLICE_REPLICAS
EOF

    print_info "Patching ClusterPolicy to use time-slicing config..."

    kubectl patch clusterpolicy cluster-policy \
        --type merge \
        -p '{"spec": {"devicePlugin": {"config": {"name": "time-slicing-config", "default": "any"}}}}'

    print_success "GPU time-slicing configured"
    print_info "Waiting for device plugin to restart..."

    # Wait for device plugin to restart
    kubectl rollout status daemonset/nvidia-device-plugin-daemonset -n "$GPU_OPERATOR_NAMESPACE" --timeout=120s || true

    print_success "Time-slicing enabled: $GPU_TIME_SLICE_REPLICAS virtual GPUs per physical GPU"
}

wait_for_gpu_operator() {
    print_header "Waiting for GPU Operator Pods"

    print_info "Waiting for pods in namespace: $GPU_OPERATOR_NAMESPACE"
    print_info "Timeout: ${WAIT_TIMEOUT}s"
    echo

    local start_time=$SECONDS
    local all_ready=false

    while [[ $((SECONDS - start_time)) -lt $WAIT_TIMEOUT ]]; do
        # Check if namespace exists
        if ! kubectl get namespace "$GPU_OPERATOR_NAMESPACE" &>/dev/null; then
            print_dim "Waiting for namespace to be created..."
            sleep 5
            continue
        fi

        # Get pod status
        local total ready
        total=$(kubectl get pods -n "$GPU_OPERATOR_NAMESPACE" --no-headers 2>/dev/null | wc -l)
        ready=$(kubectl get pods -n "$GPU_OPERATOR_NAMESPACE" --no-headers 2>/dev/null | grep -c "Running\|Completed" || true)

        if [[ $total -gt 0 ]]; then
            print_dim "Pods ready: $ready/$total"

            # Check if all pods are ready
            local not_ready
            not_ready=$(kubectl get pods -n "$GPU_OPERATOR_NAMESPACE" --no-headers 2>/dev/null | grep -v "Running\|Completed" | wc -l)

            if [[ $not_ready -eq 0 && $total -gt 0 ]]; then
                all_ready=true
                break
            fi
        fi

        sleep 10
    done

    if [[ "$all_ready" == "true" ]]; then
        print_success "All GPU operator pods are ready"
        echo
        kubectl get pods -n "$GPU_OPERATOR_NAMESPACE"
    else
        print_warning "Some pods may still be starting"
        echo
        kubectl get pods -n "$GPU_OPERATOR_NAMESPACE"
        print_info "Monitor with: kubectl get pods -n $GPU_OPERATOR_NAMESPACE -w"
    fi
}

wait_for_cluster_policy_ready() {
    print_header "Waiting for ClusterPolicy to be Ready"

    local start_time=$SECONDS
    local ready=false

    while [[ $((SECONDS - start_time)) -lt 120 ]]; do
        local status
        status=$(kubectl get clusterpolicy cluster-policy -o jsonpath='{.status.state}' 2>/dev/null || echo "unknown")

        if [[ "$status" == "ready" ]]; then
            ready=true
            break
        fi

        print_dim "ClusterPolicy status: $status"
        sleep 5
    done

    if [[ "$ready" == "true" ]]; then
        print_success "ClusterPolicy is ready"
    else
        print_warning "ClusterPolicy not yet ready, continuing anyway..."
    fi
}

verify_gpu_available() {
    print_header "Verifying GPU Available to Cluster"

    print_info "Checking node allocatable resources..."
    echo

    if kubectl describe node | grep -A5 "Allocatable:" | grep -q "nvidia.com/gpu"; then
        local gpu_count
        gpu_count=$(kubectl describe node | grep "nvidia.com/gpu:" | head -1 | awk '{print $2}')
        print_success "GPU available to cluster: $gpu_count GPU(s)"
        echo

        # Show GPU details
        kubectl describe node | grep -A10 "Allocatable:" | head -12
    else
        print_warning "GPU not yet visible in cluster resources"
        print_info "This may take a few more minutes for the device plugin to register"
        print_info "Check again with: kubectl describe node | grep nvidia"
    fi
}

test_gpu_pod() {
    print_header "Testing GPU Access (Optional)"

    if ! confirm_action "Run a test pod to verify GPU access?"; then
        print_info "Skipping GPU test"
        return 0
    fi

    print_info "Creating test pod with nvidia-smi..."

    kubectl run gpu-test --rm -it --restart=Never \
        --image=nvidia/cuda:12.3.1-base-ubuntu22.04 \
        --limits=nvidia.com/gpu=1 \
        -- nvidia-smi

    print_success "GPU test completed"
}

show_next_steps() {
    print_header "Next Steps"

    echo -e "${CYAN}GPU is now available. Update your deployments:${NC}"
    echo
    echo "1. Update Kokoro to GPU image:"
    echo "   kubectl apply -f k8s/clusters/vx-home/apps/ai-stack/kokoro/deployment.yaml"
    echo "   kubectl rollout restart deployment kokoro -n ai-stack"
    echo
    echo "2. Update Faster-Whisper to CUDA image:"
    echo "   kubectl apply -f k8s/clusters/vx-home/apps/ai-stack/faster-whisper/deployment.yaml"
    echo "   kubectl rollout restart deployment faster-whisper -n ai-stack"
    echo
    echo "3. Verify GPU allocation:"
    echo "   kubectl describe node | grep -A10 'Allocated resources'"
    echo
    echo "4. Check pod GPU assignments:"
    echo "   kubectl get pods -n ai-stack -o jsonpath='{range .items[*]}{.metadata.name}{\"\\t\"}{.spec.containers[*].resources.limits}{\"\\n\"}{end}'"
    echo
}

# ============================================================================
# MAIN
# ============================================================================

main() {
    print_header "NVIDIA GPU Enablement for MicroK8s"
    print_info "This script enables GPU support for Kubernetes workloads"
    print_info "Using Helm-based installation (more reliable than microk8s addon)"
    echo

    # Pre-flight checks
    check_nvidia_driver
    check_microk8s

    # Check if already installed
    if check_gpu_operator_installed; then
        verify_gpu_available
        print_success "GPU Operator is already configured"

        # Offer to configure time-slicing
        echo
        if confirm_action "Configure GPU time-slicing (allows multiple pods to share GPU)?"; then
            configure_gpu_time_slicing
            verify_gpu_available
        fi

        exit 0
    fi

    # Confirmation
    echo
    if ! confirm_action "Install NVIDIA GPU Operator?"; then
        print_info "Aborted by user"
        exit 0
    fi

    # Add Helm repo
    add_nvidia_helm_repo

    # Install GPU Operator
    install_gpu_operator

    # Wait for initial pods
    wait_for_gpu_operator

    # Create nvidia runtime config (CRITICAL for MicroK8s)
    create_nvidia_runtime_config

    # Wait for ClusterPolicy
    wait_for_cluster_policy_ready

    # Verify GPU
    verify_gpu_available

    # Ask about time-slicing
    echo
    if confirm_action "Configure GPU time-slicing (allows multiple pods to share GPU)?"; then
        configure_gpu_time_slicing
        verify_gpu_available
    fi

    # Optional test
    test_gpu_pod

    # Next steps
    show_next_steps

    print_success "GPU enablement complete!"
}

main "$@"
