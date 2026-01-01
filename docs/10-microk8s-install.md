# MicroK8s Installation Guide

> **Target Audience**: This guide is written for Kubernetes learners working toward CKA certification. Each step includes explanations of **what** you're doing and **why** it matters.

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Critical Pre-Flight: SELinux Configuration](#critical-pre-flight-selinux-configuration)
3. [Step 1: Install snapd](#step-1-install-snapd)
4. [Step 2: Install MicroK8s](#step-2-install-microk8s)
5. [Step 3: Enable Addons](#step-3-enable-addons)
6. [Step 4: Configure Firewall](#step-4-configure-firewall)
7. [Step 5: Label Node](#step-5-label-node)
8. [Verification](#verification)
9. [Next Steps](#next-steps)

## Prerequisites

### System Requirements

**Minimum** (will run, but slow):
- 2 CPU cores
- 4GB RAM
- 40GB disk space

**Recommended** (for this AI stack):
- 4+ CPU cores
- 8GB+ RAM
- 100GB+ disk space (for persistent volumes)

**Your System**:
- Rocky Linux (RHEL-compatible)
- Optional: NVIDIA A2 GPU (for future Phase 2)

### User Permissions

You'll need:
- `sudo` access for installation
- Ability to modify firewall rules
- Ability to change SELinux mode

### Network Requirements

- Internet access for:
  - Package downloads (EPEL, snapd, MicroK8s)
  - Container image pulls (Open WebUI, Postgres, etc.)
- Ports available (see [Firewall Configuration](#step-4-configure-firewall))

## Critical Pre-Flight: SELinux Configuration

### Why This Matters

**SELinux (Security-Enhanced Linux)** is a mandatory access control system on RHEL/Rocky/Fedora. By default, it's in **enforcing mode**, which blocks many Kubernetes operations:

- Docker/containerd socket communication
- Pod networking across nodes
- Volume mounts from host filesystem

**Without setting SELinux to permissive mode, MicroK8s will fail to start.**

### What is SELinux Permissive Mode?

| Mode | Behavior | Our Choice |
|------|----------|------------|
| **Enforcing** | Blocks violations, logs them | ❌ Breaks MicroK8s |
| **Permissive** | Allows violations, logs them | ✅ Allows K8s, still audits |
| **Disabled** | No SELinux at all | ⚠️ Overkill, not recommended |

**Permissive mode** is a compromise:
- ✓ Allows MicroK8s to function
- ✓ Still logs policy violations for audit
- ✓ Can analyze logs to create custom policies later

### CKA Learning Point: SELinux in Production

**CKA Exam**: May test basic SELinux awareness (knowing to check `getenforce`, understanding permissive vs enforcing).

**Production Practice**:
- Many Kubernetes distributions require permissive mode
- Some organizations use custom SELinux policies (complex, time-consuming)
- Cloud providers (EKS, GKE, AKS) handle this for you

### Configuration Script

Run this **before** installing MicroK8s:

```bash
sudo ./scripts/setup/01-selinux-config.sh
```

**What it does**:
1. Checks current SELinux mode (`getenforce`)
2. Sets runtime mode to permissive (`setenforce 0`)
3. Updates `/etc/selinux/config` to make it permanent
4. Explains the change with comments

**Manual Alternative**:

```bash
# Check current mode
getenforce
# Output: Enforcing (or Permissive, or Disabled)

# Set to permissive immediately (runtime only)
sudo setenforce 0

# Make it permanent across reboots
sudo sed -i 's/^SELINUX=enforcing/SELINUX=permissive/' /etc/selinux/config

# Verify the change
getenforce
# Output: Permissive
```

**⚠️ CRITICAL**: You must run this **before** Step 1. Installing MicroK8s with enforcing mode will cause cryptic errors.

## Step 1: Install snapd

### What is snapd?

**Snap** is a package management system developed by Canonical (makers of Ubuntu). Snaps are:
- **Self-contained**: Include all dependencies
- **Auto-updating**: Background updates by default
- **Versioned**: Can run multiple versions simultaneously
- **Sandboxed**: Isolated from host system (using AppArmor/SELinux)

**Why MicroK8s uses Snap**:
- Single install command across distros (Ubuntu, CentOS, Fedora, etc.)
- Easy rollbacks (`snap revert microk8s`)
- Channel-based versioning (1.35/stable, 1.34/stable, etc.)

**CKA Learning Point**: In production, you may use `kubeadm` (not snap-based), but understanding package management is valuable.

### Installation

Run the installation script:

```bash
sudo ./scripts/setup/02-install-snapd.sh
```

**What it does**:

1. **Install EPEL repository** (Extra Packages for Enterprise Linux):
   ```bash
   sudo dnf install -y epel-release
   ```
   - EPEL provides `snapd` package (not in base Rocky repos)

2. **Install snapd**:
   ```bash
   sudo dnf install -y snapd
   ```

3. **Enable snapd socket** (systemd service):
   ```bash
   sudo systemctl enable --now snapd.socket
   ```
   - `enable`: Start on boot
   - `--now`: Start immediately
   - Socket activation: systemd manages snap daemon lifecycle

4. **Create symbolic link** (for "classic" snaps):
   ```bash
   sudo ln -s /var/lib/snapd/snap /snap
   ```
   - Classic snaps (like MicroK8s) expect `/snap` directory
   - RHEL/Rocky use `/var/lib/snapd/snap` by default
   - Symlink bridges the gap

5. **Add snap to PATH**:
   ```bash
   echo 'export PATH=$PATH:/snap/bin' | sudo tee /etc/profile.d/snapd.sh
   source /etc/profile.d/snapd.sh
   ```
   - Makes `snap` command available system-wide

### Verification

```bash
# Check snapd service
sudo systemctl status snapd.socket
# Should show: Active: active (listening)

# Check snap version
snap version
# Output: snap X.XX, snapd X.XX, series XX

# Check snap is in PATH
which snap
# Output: /usr/bin/snap
```

### CKA Learning Point: systemd Services

The CKA exam tests systemd service management:
- `systemctl start/stop/restart <service>`
- `systemctl enable/disable <service>` (boot persistence)
- `systemctl status <service>` (troubleshooting)
- `journalctl -u <service>` (logs)

## Step 2: Install MicroK8s

### What is MicroK8s?

**MicroK8s** is a lightweight Kubernetes distribution by Canonical:
- **Full Kubernetes**: Not a simplified version, actual K8s
- **Single-node capable**: Can run entire cluster on one machine
- **Multi-node ready**: Can grow to 3, 5, 10+ nodes
- **Addon ecosystem**: One-command features (dns, ingress, gpu, etc.)

**vs Other K8s Distributions**:
| Distribution | Use Case | CKA Alignment |
|--------------|----------|---------------|
| kubeadm | Production multi-node, CKA exam default | ✅ Very high |
| MicroK8s | Dev, homelab, edge, learning | ✅ High |
| k3s | Edge, IoT, resource-constrained | ⚠️ Medium (more opinionated) |
| kind | Local dev, CI/CD testing | ⚠️ Low (Docker-in-Docker) |
| minikube | Local learning | ⚠️ Low (VM-based, not production-like) |

**Why MicroK8s for CKA Prep**:
- Real Kubernetes components (kube-apiserver, kubelet, etcd, etc.)
- Similar troubleshooting workflows to production clusters
- Easy to break and rebuild (valuable for exam practice!)

### Installation

Run the installation script:

```bash
sudo ./scripts/setup/03-install-microk8s.sh
```

**What it does**:

1. **Install MicroK8s snap** (channel 1.35/stable):
   ```bash
   sudo snap install microk8s --classic --channel=1.35/stable
   ```
   - `--classic`: Unconfined snap (full system access)
   - `--channel=1.35/stable`: Kubernetes 1.35 (current stable as of 2025)

   **Channel Explanation**:
   - `1.35/stable`: Production-ready Kubernetes 1.35
   - `1.35/candidate`: Pre-release testing
   - `1.35/edge`: Bleeding-edge (not recommended)
   - `latest/stable`: Always latest K8s version (auto-updates)

2. **Add user to microk8s group**:
   ```bash
   sudo usermod -a -G microk8s $USER
   ```
   - Without this, you need `sudo` for every `microk8s` command
   - Group membership grants access to MicroK8s socket

3. **Apply group membership** (without logout):
   ```bash
   newgrp microk8s
   ```
   - Starts new shell with updated groups
   - Alternative: Log out and back in

4. **Wait for MicroK8s to be ready**:
   ```bash
   microk8s status --wait-ready
   ```
   - Polls until all services are running
   - Can take 30-60 seconds on first boot

### Verification

```bash
# Check MicroK8s status
microk8s status
# Output: MicroK8s is running
#         High availability: no
#         Addons: (list of enabled addons)

# Check Kubernetes version
microk8s kubectl version --short
# Output: Server Version: v1.35.X

# Check nodes
microk8s kubectl get nodes
# Output: NAME     STATUS   ROLES   AGE   VERSION
#         <hostname>   Ready    <none>  1m    v1.35.X
```

### CKA Learning Point: Kubernetes Components

When you run `microk8s status`, you're checking these core components:

**Control Plane** (master node):
- **kube-apiserver**: REST API endpoint for cluster management
- **kube-controller-manager**: Reconciliation loops (Deployments, ReplicaSets, etc.)
- **kube-scheduler**: Assigns pods to nodes
- **etcd**: Key-value store for all cluster state

**Node Components** (worker node, same node in single-node setup):
- **kubelet**: Runs on every node, manages pod lifecycle
- **kube-proxy**: Network routing for Services

**Addons**:
- **CoreDNS**: Cluster DNS service
- **Calico**: Container Network Interface (CNI) for pod networking

The CKA exam tests understanding of these components, how to troubleshoot them, and where their logs are.

### Troubleshooting: MicroK8s Won't Start

**Common Issues**:

1. **SELinux still enforcing**:
   ```bash
   getenforce
   # If output is "Enforcing", go back to pre-flight step
   ```

2. **Port conflicts** (if you have other K8s/Docker):
   ```bash
   sudo netstat -tulnp | grep -E '16443|10250|10255|25000'
   # If any are in use, stop conflicting services
   ```

3. **Snap services not running**:
   ```bash
   sudo systemctl status snapd.socket
   sudo systemctl restart snapd.socket
   ```

4. **Logs** (check for errors):
   ```bash
   sudo journalctl -u snap.microk8s.daemon-kubelite.service -f
   ```

## Step 3: Enable Addons

### What are MicroK8s Addons?

**Addons** are optional Kubernetes components packaged by MicroK8s:
- One-command installation
- Pre-configured for MicroK8s environment
- Can be enabled/disabled at runtime

**Addons vs Helm Charts**:
- Addons are MicroK8s-specific, Helm is universal
- Addons are simpler but less configurable
- Production often uses both (e.g., MicroK8s ingress + Helm apps)

### Required Addons for This Stack

We need these addons:

| Addon | Purpose | Why Required |
|-------|---------|--------------|
| **dns** | CoreDNS for service discovery | Pods need to resolve `pgvector`, `redis`, etc. |
| **ingress** | NGINX Ingress Controller | Route `ai.vx.home` to Open WebUI |
| **hostpath-storage** | Dynamic PV provisioner | Auto-create PVs for PVCs |
| **helm3** | Helm package manager | Install Portainer |

**Optional** (recommended for production):
- **metrics-server**: `kubectl top` for resource usage
- **metallb**: LoadBalancer IP allocation (useful even on single-node)
- **cert-manager**: Let's Encrypt TLS certificates

### Installation

Run the addon script:

```bash
sudo ./scripts/setup/05-enable-addons.sh
```

**What it does**:

```bash
# Enable DNS (CoreDNS)
microk8s enable dns
# Creates: Deployment coredns in kube-system namespace
# Purpose: Resolves <service>.<namespace>.svc.cluster.local

# Enable Ingress (NGINX)
microk8s enable ingress
# Creates: Deployment nginx-ingress-microk8s-controller in ingress namespace
# Purpose: HTTP/HTTPS routing to Services

# Enable hostpath-storage
microk8s enable hostpath-storage
# Creates: StorageClass microk8s-hostpath with provisioner microk8s.io/hostpath
# Purpose: Automatically provision PVs when PVCs are created

# Enable Helm3
microk8s enable helm3
# Installs: Helm 3 binary at /snap/microk8s/current/bin/helm3
# Purpose: Install Portainer and future Helm charts
```

### Verification

```bash
# Check enabled addons
microk8s status
# Output should show:
#   dns: enabled
#   ingress: enabled
#   hostpath-storage: enabled
#   helm3: enabled

# Check DNS pods
microk8s kubectl get pods -n kube-system -l k8s-app=kube-dns
# Output: coredns-XXX   1/1   Running

# Check Ingress controller
microk8s kubectl get pods -n ingress
# Output: nginx-ingress-microk8s-controller-XXX   1/1   Running

# Check StorageClass
microk8s kubectl get storageclass
# Output: NAME                 PROVISIONER
#         microk8s-hostpath    microk8s.io/hostpath

# Check Helm version
microk8s helm3 version --short
# Output: v3.XX.X
```

### CKA Learning Point: CoreDNS and Service Discovery

**How DNS Works in Kubernetes**:

1. **Pod creates DNS query** for `pgvector`:
   ```
   Application → /etc/resolv.conf → nameserver <coredns-cluster-ip>
   ```

2. **CoreDNS expands short name** to FQDN:
   ```
   pgvector → pgvector.ai.svc.cluster.local
   ```
   - `.ai`: Namespace (current pod's namespace is tried first)
   - `.svc`: Service type
   - `.cluster.local`: Cluster domain

3. **CoreDNS returns Service ClusterIP**:
   ```
   pgvector.ai.svc.cluster.local → 10.152.183.45
   ```

4. **kube-proxy routes to pod**:
   ```
   10.152.183.45 (Service) → 10.1.0.78 (Pod IP)
   ```

**CKA Exam**: Expect to debug DNS issues like:
- Pod can't resolve service name
- CoreDNS pod not running
- Wrong namespace in service name

**Debugging Commands**:
```bash
# Test DNS from a pod
microk8s kubectl run -it --rm debug --image=busybox --restart=Never -- nslookup pgvector.ai.svc.cluster.local

# Check CoreDNS logs
microk8s kubectl logs -n kube-system -l k8s-app=kube-dns
```

### CKA Learning Point: Ingress Controllers

**What is an Ingress Controller?**

An Ingress Controller is a specialized load balancer that:
- Runs **inside** the cluster (as a pod)
- Watches **Ingress resources** (YAML definitions)
- Configures routing rules dynamically

**NGINX Ingress Flow**:
```
User → http://ai.vx.home
  ↓
Node IP:80 (HostPort or NodePort)
  ↓
NGINX Ingress Controller Pod
  ↓
Ingress Resource (host: ai.vx.home → backend: openwebui:80)
  ↓
Service openwebui (ClusterIP 10.152.183.50)
  ↓
Pod openwebui-7d8f9-abc12 (Pod IP 10.1.0.100)
```

**CKA Exam**: May test Ingress resource creation:
```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: test-ingress
  namespace: default
spec:
  rules:
  - host: test.example.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: test-service
            port:
              number: 80
```

## Step 4: Configure Firewall

### Why Firewall Configuration Matters

**Problem**: By default, Rocky Linux's `firewalld` blocks most incoming connections.

**Impact**:
- Can't access Ingress from other machines (http://ai.vx.home won't work)
- Kubernetes node communication blocked (for multi-node, future)
- API server inaccessible (for remote kubectl, future)

### Required Ports

| Port | Protocol | Service | Purpose |
|------|----------|---------|---------|
| **80** | TCP | HTTP | Ingress (Open WebUI, Portainer HTTP) |
| **443** | TCP | HTTPS | Ingress TLS (future) |
| **16443** | TCP | Kubernetes API | Remote kubectl (optional) |
| **10250** | TCP | kubelet | Node communication (multi-node, future) |
| **10255** | TCP | kubelet read-only | Metrics (optional) |
| **25000** | TCP | cluster-agent | Node communication (multi-node, future) |

**For single-node homelab, essential ports**:
- **80** (HTTP)
- **443** (HTTPS, future)

**For multi-node (Phase 2)**:
- All of the above

### Installation

Run the firewall script:

```bash
sudo ./scripts/setup/07-configure-firewall.sh
```

**What it does**:

```bash
# Check if firewalld is running
sudo systemctl status firewalld

# Open HTTP and HTTPS
sudo firewall-cmd --permanent --add-service=http
sudo firewall-cmd --permanent --add-service=https

# Open Kubernetes ports
sudo firewall-cmd --permanent --add-port=16443/tcp  # API server
sudo firewall-cmd --permanent --add-port=10250/tcp  # kubelet
sudo firewall-cmd --permanent --add-port=10255/tcp  # kubelet read-only
sudo firewall-cmd --permanent --add-port=25000/tcp  # cluster-agent

# Enable masquerading (required for pod networking)
sudo firewall-cmd --permanent --add-masquerade

# Reload to apply changes
sudo firewall-cmd --reload
```

**Masquerading Explanation**:
- Allows pods to access external networks
- Rewrites source IP from pod IP to node IP (NAT)
- Essential for internet access from pods

### Verification

```bash
# Check firewalld status
sudo firewall-cmd --list-all
# Output should include:
#   services: http https
#   ports: 16443/tcp 10250/tcp 10255/tcp 25000/tcp
#   masquerade: yes

# Test from another machine (if available)
curl http://<node-ip>
# Should connect (may get 404 or 502, but not connection refused)
```

### CKA Learning Point: iptables and Networking

**Under the Hood**: firewalld manages iptables rules.

**Kubernetes also uses iptables** (via kube-proxy) for:
- Service load balancing (ClusterIP → Pod IPs)
- NodePort forwarding (Node IP:port → Service)
- Network policies (pod-to-pod firewall rules)

**CKA Exam**: May test basic iptables troubleshooting:
```bash
# View iptables rules for Services
sudo iptables -t nat -L KUBE-SERVICES

# View rules for a specific Service
sudo iptables -t nat -L KUBE-SVC-XXXXX
```

**Debugging Network Issues**:
- If pods can't reach internet: Check masquerading
- If Services aren't load-balancing: Check kube-proxy logs
- If external access fails: Check firewalld and iptables

## Step 5: Label Node

### What are Node Labels?

**Labels** are key-value pairs attached to Kubernetes objects (nodes, pods, etc.):
- Used for selection and filtering
- Enables targeted scheduling (nodeSelector, nodeAffinity)
- Arbitrary keys/values (you define them)

**Example Labels**:
```yaml
metadata:
  labels:
    kubernetes.io/hostname: worker-1
    node-role.kubernetes.io/worker: ""
    gpu: "true"  # Our custom label
```

### Why Label for GPU?

**Current State** (single-node):
- All pods run on the same node anyway
- Labeling seems unnecessary

**Future State** (multi-node, Phase 2):
- Add a second node (CPU-only)
- GPU node labeled `gpu=true`, non-GPU nodes labeled `gpu=false`
- TTS/STT pods pinned to GPU node via nodeSelector
- Other pods can run on either node

**CKA Learning Point**: Labeling for future flexibility is good practice. Demonstrates planning for scalability.

### Installation

Run the label script:

```bash
sudo ./scripts/setup/08-label-node.sh
```

**What it does**:

```bash
# Get the node name
NODE_NAME=$(microk8s kubectl get nodes -o jsonpath='{.items[0].metadata.name}')

# Apply the label
microk8s kubectl label node $NODE_NAME gpu=true

# Verify
microk8s kubectl get nodes --show-labels
```

### Verification

```bash
# Check node labels
microk8s kubectl get nodes --show-labels | grep gpu
# Output: <node-name>   Ready   <none>   10m   v1.35.X   ...gpu=true...

# Describe node (detailed view)
microk8s kubectl describe node <node-name> | grep gpu
# Output: Labels:  ...
#                  gpu=true
```

### How Pods Use the Label

**In Deployment YAML** (e.g., Kokoro TTS):

```yaml
spec:
  template:
    spec:
      nodeSelector:
        gpu: "true"  # Only schedule on nodes with this label
```

**Scheduler Behavior**:
1. Pod created with nodeSelector
2. Scheduler filters nodes: only those with `gpu=true`
3. If no matching nodes: Pod stays Pending
4. If matching nodes: Pod scheduled to one of them

**CKA Exam**: Troubleshooting Pending pods often involves checking nodeSelector vs available node labels.

```bash
# Why is this pod Pending?
microk8s kubectl describe pod kokoro-XXX-YYY -n ai
# Output: Events:
#   Warning  FailedScheduling  0/1 nodes available: 1 node(s) didn't match node selector
```

### CKA Learning Point: Affinity vs Taints/Tolerations

**Three Ways to Control Pod Placement**:

| Method | Use Case | Complexity |
|--------|----------|------------|
| **nodeSelector** | Simple "must run on nodes with label X" | Low (our choice) |
| **nodeAffinity** | "Prefer nodes with label X, but allow others" | Medium |
| **Taints/Tolerations** | "Prevent pods from running unless they tolerate taint X" | High |

**When to Use Which**:
- **nodeSelector**: GPU nodes, storage nodes, specific hardware
- **nodeAffinity**: "Prefer same zone as X, but allow other zones"
- **Taints**: "Don't run user workloads on master nodes"

**CKA Exam**: Expect questions on all three methods.

## Verification: Complete System Check

### 1. MicroK8s Health

```bash
# Overall status
microk8s status

# Check all system pods
microk8s kubectl get pods --all-namespaces
# All pods should be Running (not Pending, CrashLoopBackOff, etc.)
```

### 2. Addon Verification

```bash
# DNS
microk8s kubectl get pods -n kube-system -l k8s-app=kube-dns
# Ingress
microk8s kubectl get pods -n ingress
# Storage
microk8s kubectl get sc
```

### 3. Node Status

```bash
# Node ready
microk8s kubectl get nodes
# Output: STATUS = Ready

# Node labeled
microk8s kubectl get nodes --show-labels | grep gpu
# Output: should contain gpu=true
```

### 4. Network Connectivity

```bash
# Test DNS from a pod
microk8s kubectl run -it --rm test --image=busybox --restart=Never -- nslookup kubernetes.default
# Output: Server:    10.152.183.10
#         Address 1: 10.152.183.10 kube-dns.kube-system.svc.cluster.local

# Test internet access from pod
microk8s kubectl run -it --rm test --image=busybox --restart=Never -- wget -qO- https://www.google.com
# Output: (HTML content)
```

### 5. Firewall

```bash
# Check open ports
sudo firewall-cmd --list-all
# Should show: http, https, ports 16443, 10250, 10255, 25000, masquerade enabled
```

## Troubleshooting Common Issues

### Issue: MicroK8s services not starting

**Symptoms**:
```bash
microk8s status
# Output: MicroK8s is not running. Use microk8s inspect for more details.
```

**Diagnosis**:
```bash
# Check journalctl logs
sudo journalctl -u snap.microk8s.daemon-kubelite.service -n 100 --no-pager

# Check inspection report
microk8s inspect
# Generates report at /var/snap/microk8s/common/inspection-report-XXXXXX.tar.gz
```

**Common Causes**:
1. SELinux enforcing: `getenforce` → should be Permissive
2. Port conflicts: `sudo netstat -tulnp | grep 16443`
3. Disk space: `df -h /var/snap/microk8s`

### Issue: Pods stuck in Pending

**Symptoms**:
```bash
microk8s kubectl get pods -n ai
# Output: pgvector-0   0/1   Pending
```

**Diagnosis**:
```bash
# Describe pod for events
microk8s kubectl describe pod pgvector-0 -n ai
# Look for: Events section

# Check node resources
microk8s kubectl describe nodes
# Look for: Allocatable resources, Conditions
```

**Common Causes**:
1. No matching node (nodeSelector, nodeAffinity)
2. Insufficient resources (CPU, memory)
3. PVC can't be bound (no StorageClass)

### Issue: Ingress not working (404/502/connection refused)

**Symptoms**:
```bash
curl http://ai.vx.home
# Output: Connection refused OR 404 Not Found OR 502 Bad Gateway
```

**Diagnosis**:
```bash
# Check Ingress controller
microk8s kubectl get pods -n ingress
# Output: should be Running

# Check Ingress resource
microk8s kubectl get ingress -n ai
# Check: ADDRESS column should have IP

# Check Service endpoints
microk8s kubectl get endpoints openwebui -n ai
# Should have pod IP(s)

# Check Ingress controller logs
microk8s kubectl logs -n ingress <nginx-controller-pod>
```

**Common Causes**:
1. Ingress controller not running
2. Service name mismatch in Ingress
3. Backend pod not running
4. DNS not pointing to node IP

### Issue: Firewall blocks access from other machines

**Symptoms**:
```bash
# From another machine
curl http://<node-ip>
# Output: Connection timed out
```

**Diagnosis**:
```bash
# Check firewalld on node
sudo firewall-cmd --list-all

# Check if port 80 is listening
sudo netstat -tulnp | grep :80
```

**Solution**:
```bash
# Re-run firewall script
sudo ./scripts/setup/07-configure-firewall.sh

# OR manually open port
sudo firewall-cmd --permanent --add-service=http
sudo firewall-cmd --reload
```

## Next Steps

✅ **Installation Complete!**

Now proceed to:

1. **[Portainer Installation](20-portainer.md)**: Install cluster management UI
2. **[AI Stack Deployment](30-ai-stack-openwebui.md)**: Deploy Open WebUI and supporting services

**Optional Learning**:
- Experiment with kubectl commands
- Break and fix things (great CKA practice!)
- Add a second node (requires another machine)

## Additional CKA Study Resources

**Practice kubectl**:
```bash
# Alias for convenience (add to ~/.bashrc)
alias k='microk8s kubectl'

# Essential kubectl commands
k get pods -A                        # All pods, all namespaces
k get pods -n ai -o wide             # Show node placement, IP
k describe pod <pod-name> -n ai      # Detailed info + events
k logs <pod-name> -n ai              # Container logs
k logs <pod-name> -n ai -f           # Follow logs (tail -f)
k exec -it <pod-name> -n ai -- bash  # Shell into container
k port-forward svc/<service> 8080:80 # Forward local port to service
```

**CKA Exam Tips**:
- Memorize kubectl syntax (no autocomplete on exam)
- Practice imperative commands (faster than YAML for simple tasks)
- Use `kubectl explain` for YAML field documentation
- Set up bash aliases before the exam

**Resources**:
- [Kubernetes Documentation](https://kubernetes.io/docs/)
- [kubectl Cheat Sheet](https://kubernetes.io/docs/reference/kubectl/cheatsheet/)
- [CKA Exam Curriculum](https://training.linuxfoundation.org/certification/certified-kubernetes-administrator-cka/)

---

**Questions?** See [docs/90-troubleshooting.md](90-troubleshooting.md) for more help!
