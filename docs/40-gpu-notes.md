# GPU Enablement Strategy (Phase 2)

## Current State

**CPU-Only Configuration**:
- ✅ Open WebUI: CPU
- ✅ pgvector: CPU
- ✅ Redis: CPU
- ✅ pgAdmin: CPU
- ✅ Kokoro TTS: CPU (pinned to ai-stt-tts node for future GPU)
- ✅ Faster-Whisper STT: CPU (pinned to ai-stt-tts node for future GPU)

**Why CPU-Only Now**:
1. Simpler initial setup (no NVIDIA drivers/runtime complexity)
2. Validates architecture before adding GPU
3. Single A2 GPU + two GPU-hungry services requires planning

## NVIDIA A2 GPU Capabilities

**NVIDIA A2 Specifications**:
- **CUDA Cores**: 3,328
- **Tensor Cores**: 104 (2nd gen)
- **GPU Memory**: 16GB GDDR6
- **TDP**: 60W (low power)
- **MIG Support**: ❌ No (A2 doesn't support Multi-Instance GPU)

**Performance Profile**:
- Designed for edge AI inference (not training)
- Excellent for TTS/STT workloads
- Can handle both Kokoro + Faster-Whisper, but requires sharing strategy

## GPU Sharing Challenges

### Default Kubernetes GPU Scheduling

**Problem**: Kubernetes treats GPUs as discrete resources.

```yaml
resources:
  limits:
    nvidia.com/gpu: 1  # Request 1 entire GPU
```

**Implications**:
- Pod gets exclusive access to entire GPU
- Other pods can't use the GPU (even if underutilized)
- For single A2: only ONE pod can use GPU at a time

**Example Conflict**:
```
Kokoro pod requests:     nvidia.com/gpu: 1
Faster-Whisper requests: nvidia.com/gpu: 1
Available GPUs: 1

Result: One pod runs, other stays Pending (insufficient GPU)
```

### GPU Sharing Solutions

| Method | Complexity | A2 Support | Best For |
|--------|-----------|-----------|----------|
| **Serial Scheduling** | Low | ✅ Yes | Simple, one service at a time |
| **Time-Slicing** | Medium | ✅ Yes | Share GPU temporally (NVIDIA config) |
| **MIG (Multi-Instance GPU)** | High | ❌ No (A30+ only) | Partition GPU into instances |
| **MPS (Multi-Process Service)** | Medium | ✅ Yes | Share GPU spatially (CUDA streams) |

**Recommended for A2: Time-Slicing** (balance of simplicity and capability)

## Time-Slicing GPU Sharing

### What is Time-Slicing?

**Concept**: Multiple pods share GPU by taking turns (time-division multiplexing).

**How it works**:
1. NVIDIA device plugin configured with replicas > 1
2. Kubernetes sees "multiple GPUs" (logical, not physical)
3. NVIDIA runtime time-slices access to physical GPU
4. Pods run concurrently, GPU switches context between them

**Trade-offs**:
- ✅ Allows multiple pods to use GPU
- ✅ Better utilization than exclusive access
- ⚠️ Performance degradation if both pods active simultaneously
- ⚠️ No memory isolation (total memory shared)

### Time-Slicing Configuration

**NVIDIA Device Plugin ConfigMap**:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: nvidia-device-plugin-config
  namespace: kube-system
data:
  config.yaml: |
    version: v1
    sharing:
      timeSlicing:
        replicas: 2  # Logical GPUs per physical GPU
        renameByDefault: false
    resources:
      - name: nvidia.com/gpu
        devices: all
```

**Explanation**:
- `replicas: 2`: Kubernetes sees 2 GPUs (both use same physical A2)
- `renameByDefault: false`: Keep resource name as `nvidia.com/gpu`
- `devices: all`: Apply to all GPUs on node

**Result**:
```bash
kubectl describe node
# Capacity:
#   nvidia.com/gpu: 2  # Logical (was 1 physical)
```

Now Kokoro and Faster-Whisper can both request `nvidia.com/gpu: 1`.

## GPU Enablement Workflow

### Phase 1: Prerequisites

**1. Install NVIDIA Drivers on Host**:

```bash
# Check current driver version
nvidia-smi
# If not installed:

# Add NVIDIA repository
sudo dnf config-manager --add-repo \
  https://developer.download.nvidia.com/compute/cuda/repos/rhel9/x86_64/cuda-rhel9.repo

# Install driver
sudo dnf install -y nvidia-driver nvidia-driver-cuda

# Reboot
sudo reboot

# Verify after reboot
nvidia-smi
# Should show GPU info
```

**2. Install NVIDIA Container Toolkit**:

```bash
# Add NVIDIA container toolkit repo
distribution=$(. /etc/os-release;echo $ID$VERSION_ID)
curl -s -L https://nvidia.github.io/libnvidia-container/$distribution/libnvidia-container.repo | \
  sudo tee /etc/yum.repos.d/nvidia-container-toolkit.repo

# Install toolkit
sudo dnf install -y nvidia-container-toolkit

# Configure containerd (MicroK8s uses containerd)
sudo nvidia-ctk runtime configure --runtime=containerd \
  --config=/var/snap/microk8s/current/args/containerd-template.toml

# Restart MicroK8s
microk8s stop
microk8s start
```

**3. Verify Container GPU Access**:

```bash
# Run test container
microk8s kubectl run gpu-test --rm -it --restart=Never \
  --image=nvidia/cuda:12.0-base \
  -- nvidia-smi

# Should show GPU info from within container
```

### Phase 2: Enable MicroK8s GPU Addon

**MicroK8s provides GPU addon** (uses NVIDIA GPU Operator):

```bash
# Enable GPU addon
microk8s enable gpu
```

**What this does**:
- Installs NVIDIA GPU Operator
- Deploys NVIDIA device plugin
- Configures container runtime
- Adds `nvidia.com/gpu` resource to nodes

**Verify**:

```bash
# Check GPU operator pods
kubectl get pods -n gpu-operator-resources

# Check node capacity
kubectl get nodes -o jsonpath='{.items[0].status.capacity}' | jq
# Should show: "nvidia.com/gpu": "1"
```

### Phase 3: Configure Time-Slicing (Optional)

**If you want both Kokoro + Faster-Whisper to use GPU simultaneously**:

1. **Create ConfigMap** (from example above)
2. **Restart device plugin**:
   ```bash
   kubectl rollout restart daemonset nvidia-device-plugin-daemonset -n gpu-operator-resources
   ```
3. **Verify**:
   ```bash
   kubectl get nodes -o jsonpath='{.items[0].status.capacity}' | jq
   # Should show: "nvidia.com/gpu": "2"
   ```

### Phase 4: Update Deployments for GPU

**Choose ONE service first** (Kokoro TTS):

```yaml
# k8s/clusters/vx-home/apps/ai-stack/kokoro/deployment.yaml
spec:
  template:
    spec:
      containers:
      - name: kokoro
        image: ghcr.io/remsky/kokoro-fastapi:latest  # GPU variant
        resources:
          limits:
            nvidia.com/gpu: 1  # Request GPU
```

**Deploy update**:

```bash
kubectl apply -f k8s/clusters/vx-home/apps/ai-stack/kokoro/deployment.yaml
```

**Verify GPU usage**:

```bash
# Check pod is using GPU
kubectl describe pod -n ai <kokoro-pod> | grep nvidia.com/gpu
# Output: Limits: nvidia.com/gpu: 1

# Check GPU utilization from node
nvidia-smi
# Should show Kokoro process
```

**Then update Faster-Whisper**:

```yaml
# k8s/clusters/vx-home/apps/ai-stack/faster-whisper/deployment.yaml
spec:
  template:
    spec:
      containers:
      - name: faster-whisper
        image: fedirz/faster-whisper-server:latest-cuda  # GPU variant
        env:
        - name: WHISPER__INFERENCE_DEVICE
          value: "cuda"
        resources:
          limits:
            nvidia.com/gpu: 1
```

## Performance Expectations

### CPU vs GPU Performance

**Kokoro TTS** (generating 10 seconds of audio):
- CPU: ~3-5 seconds
- GPU (A2): ~0.5-1 second
- **Speedup**: ~5x

**Faster-Whisper STT** (transcribing 1 minute of audio):
- CPU: ~10-20 seconds
- GPU (A2): ~2-4 seconds
- **Speedup**: ~5x

**Concurrent Usage** (time-slicing with both pods active):
- Each pod gets 50% GPU time (approximately)
- Effective performance: ~2.5x faster than CPU (not full 5x)
- Still worthwhile for improved user experience

## Monitoring GPU Usage

### nvidia-smi

```bash
# Basic GPU status
nvidia-smi

# Continuous monitoring (updates every 1 second)
watch -n 1 nvidia-smi

# Specific info (GPU utilization, memory)
nvidia-smi --query-gpu=utilization.gpu,utilization.memory,memory.total,memory.used,memory.free --format=csv
```

### Kubernetes Metrics

```bash
# Enable metrics-server (if not already)
microk8s enable metrics-server

# View node resources (includes GPU)
kubectl describe nodes
# Look for: Allocatable: nvidia.com/gpu: X
#           Allocated:   nvidia.com/gpu: Y

# GPU usage per pod (requires DCGM exporter)
# See Observability section below
```

### Prometheus + Grafana (Future)

**DCGM Exporter** (NVIDIA Data Center GPU Manager):
- Exports GPU metrics to Prometheus
- Pre-built dashboards for Grafana
- Shows per-pod GPU usage, temperature, power, etc.

```bash
# Install via GPU operator
microk8s enable observability  # Prometheus + Grafana
# Then configure DCGM exporter (GPU operator includes it)
```

## Troubleshooting

### Issue: nvidia-smi not found

**Cause**: NVIDIA drivers not installed

**Solution**: Follow Phase 1 (prerequisites)

### Issue: Pods stuck Pending with "insufficient nvidia.com/gpu"

**Diagnosis**:

```bash
kubectl describe pod -n ai <pod-name>
# Events: 0/1 nodes available: 1 Insufficient nvidia.com/gpu
```

**Causes**:
1. GPU addon not enabled
2. GPU already allocated to another pod (no time-slicing)
3. Node doesn't have GPU

**Solutions**:
1. `microk8s enable gpu`
2. Configure time-slicing (see Phase 3)
3. Verify node has GPU: `kubectl get nodes -o jsonpath='{.items[0].status.capacity}'`

### Issue: Pod crashes with "CUDA error"

**Diagnosis**:

```bash
kubectl logs -n ai <pod-name>
# Check for errors like: "CUDA error: no kernel image is available"
```

**Causes**:
1. Wrong CUDA version (container vs driver mismatch)
2. Container doesn't have CUDA support

**Solutions**:
1. Match container CUDA version to driver: `nvidia-smi` shows CUDA version
2. Use GPU-specific image (e.g., `faster-whisper-server:latest-cuda`)

### Issue: GPU not being utilized (nvidia-smi shows 0%)

**Diagnosis**:

```bash
# Check if pod actually has GPU allocated
kubectl describe pod -n ai <pod-name> | grep nvidia.com/gpu

# Check application logs (may be using CPU fallback)
kubectl logs -n ai <pod-name>
```

**Causes**:
1. Application defaulting to CPU
2. GPU resource limit not set in Deployment
3. CUDA libraries not found in container

**Solutions**:
1. Set `WHISPER__INFERENCE_DEVICE=cuda` env var (for Faster-Whisper)
2. Add `resources.limits.nvidia.com/gpu: 1` to Deployment
3. Use GPU-variant container image

## Migration Strategy

**Recommended Approach** (minimize risk):

1. ✅ **Start with CPU-only** (current state)
2. ✅ **Validate entire stack works** (Open WebUI, RAG, TTS, STT all functional)
3. 🔄 **Enable GPU for ONE service** (Kokoro TTS)
   - Test performance improvement
   - Ensure no regressions
4. 🔄 **Enable GPU for SECOND service** (Faster-Whisper STT)
   - Configure time-slicing if both need simultaneous GPU access
   - Monitor GPU utilization
5. 🔄 **Tune resource limits** based on actual usage

**Rollback Plan**:
- Remove `nvidia.com/gpu` limits from Deployments
- Pods fall back to CPU (graceful degradation)

## Alternative: Keep CPU-Only

**Valid Reasons to Stay CPU-Only**:
1. **Performance Acceptable**: If TTS/STT latency is tolerable, no need for complexity
2. **Power Efficiency**: GPU adds 60W power draw (A2 TDP)
3. **Simplicity**: Fewer moving parts, easier to troubleshoot
4. **Reserve GPU for Future**: Save GPU for future workloads (local LLM, image gen, etc.)

**CKA Learning**: Both CPU and GPU scenarios teach valuable Kubernetes concepts.

## Future Enhancements

### Multi-Node GPU Cluster

When adding more nodes:
1. **GPU Node**: A2 GPU, runs TTS/STT
2. **CPU Nodes**: Run Open WebUI, databases, other services
3. **Node Labels**: More granular (`gpu-type=a2`, `gpu-memory=16gb`)
4. **NodeAffinity**: "Prefer GPU node, but allow CPU fallback"

### MIG-Capable GPUs (A30+)

If upgrading to A30 or higher:
- **MIG**: Partition GPU into isolated instances (e.g., 2x 8GB slices)
- **Better Isolation**: Each slice appears as separate GPU
- **Memory Guarantees**: Unlike time-slicing, MIG enforces memory limits

### Inference Optimization

- **TensorRT**: Optimize models for NVIDIA GPUs (faster inference)
- **ONNX Runtime**: Framework-agnostic inference (Kokoro supports ONNX)
- **Model Quantization**: Reduce model size and memory usage (e.g., INT8)

## CKA Learning Points

### Resource Management

**Extended Resources** (like GPUs):
- Kubernetes supports custom resources (not just CPU/memory)
- Managed by device plugins (NVIDIA device plugin, AMD GPU plugin, etc.)
- Same scheduling principles apply

**Resource Requests vs Limits**:
```yaml
resources:
  requests:
    nvidia.com/gpu: 1  # Scheduler uses this for placement
  limits:
    nvidia.com/gpu: 1  # Hard cap (for GPUs, request == limit)
```

**CKA Exam**: Expect questions on resource requests, limits, and scheduling.

### Device Plugins

**What are Device Plugins?**
- Extend Kubernetes to support hardware (GPUs, FPGAs, SR-IOV NICs)
- Run as DaemonSets (one per node)
- Advertise device availability to kubelet
- Handle device allocation to pods

**CKA Relevance**: Understanding plugin architecture (not implementing them).

## Summary

**Current State**: CPU-only, all services functional

**Phase 2 GPU Enablement**:
1. Install NVIDIA drivers + container toolkit
2. Enable MicroK8s GPU addon
3. Configure time-slicing (optional, for concurrent access)
4. Update Deployment YAMLs with GPU limits
5. Switch to GPU-variant container images

**Expected Outcome**: ~5x performance improvement for TTS/STT

**Risks**: Complexity, driver/CUDA compatibility, power consumption

**Recommendation**: Only enable GPU once CPU-only stack is stable and validated.

---

**Resources**:
- [NVIDIA GPU Operator Documentation](https://docs.nvidia.com/datacenter/cloud-native/gpu-operator/overview.html)
- [MicroK8s GPU Addon](https://microk8s.io/docs/addon-gpu)
- [Kubernetes Device Plugins](https://kubernetes.io/docs/concepts/extend-kubernetes/compute-storage-net/device-plugins/)
- [NVIDIA Time-Slicing Guide](https://docs.nvidia.com/datacenter/cloud-native/gpu-operator/gpu-sharing.html)
