# Manual AI Stack Deployment Walkthrough

This guide walks through deploying the AI stack step-by-step using raw `kubectl` commands. Each command is explained so you understand what's happening and why.

---

## Prerequisites Check

Before starting, verify your cluster is ready:

```bash
# Check MicroK8s is running
microk8s status
```

**Expected output:** `microk8s is running` with these addons enabled:
- `dns` - CoreDNS for service discovery
- `ingress` - NGINX Ingress controller for external access
- `hostpath-storage` - Dynamic PersistentVolume provisioner
- `cert-manager` - TLS certificate automation
- `helm3` - Package manager (for Portainer)

```bash
# Check you can reach the Kubernetes API
kubectl get nodes
```

**Expected output:** Your node in `Ready` state.

```bash
# Check node labels (needed for TTS/STT scheduling)
kubectl get nodes --show-labels | grep gpu
```

**Expected output:** `gpu=true`

If missing, label your node:
```bash
kubectl label node vx-app-00.adm.vx.home gpu=true
```

---

## Phase 1: Create the Namespace

**What is a Namespace?**
Namespaces provide isolation within a cluster. Resources in the `ai` namespace are logically separated from `default` or `kube-system`. This helps with:
- Organization (all AI stack resources together)
- Access control (RBAC can scope to namespaces)
- Resource quotas (limit CPU/memory per namespace)

```bash
# View existing namespaces
kubectl get namespaces
```

```bash
# Create the ai namespace using the manifest (includes labels)
kubectl apply -f k8s/clusters/vx-home/namespace-ai.yaml
```

> **Note:** If you previously created the namespace with `kubectl create namespace ai`,
> you'll see a warning about missing `last-applied-configuration` annotation. This is
> harmless - kubectl patches it automatically. The warning occurs because `kubectl apply`
> tracks what was previously applied (for 3-way merges), but `kubectl create` doesn't
> store this metadata.

```bash
# Verify it was created
kubectl get namespace ai
```

**Expected output:**
```
NAME   STATUS   AGE
ai     Active   5s
```

---

## Phase 2: Create Secrets

**What are Secrets?**
Secrets store sensitive data like passwords and API keys. Unlike ConfigMaps, Secrets are:
- Base64-encoded (not encrypted by default, but can be)
- Accessible only to pods that reference them
- Not logged in kubectl output

### Step 2a: Create Your Secrets File

```bash
cd /home/administrator/projects/demo-app-k8s-stack

# Copy the template
cp k8s/clusters/vx-home/apps/ai-stack/secrets.example.yaml \
   k8s/clusters/vx-home/apps/ai-stack/secrets.yaml
```

### Step 2b: Generate Secure Passwords

```bash
# Generate a strong password for PostgreSQL
openssl rand -base64 24
```

Copy the output - you'll use it for both `POSTGRES_PASSWORD` and inside `DATABASE_URL`.

```bash
# Generate a password for pgAdmin
openssl rand -base64 24
```

### Step 2c: Edit the Secrets File

Open `k8s/clusters/vx-home/apps/ai-stack/secrets.yaml` and update:

```yaml
stringData:
  POSTGRES_DB: "openwebui"
  POSTGRES_USER: "openwebui"
  POSTGRES_PASSWORD: "YOUR_GENERATED_PASSWORD_HERE"

  # IMPORTANT: The password in DATABASE_URL must match POSTGRES_PASSWORD
  DATABASE_URL: "postgresql://openwebui:YOUR_GENERATED_PASSWORD_HERE@pgvector:5432/openwebui"

  PGADMIN_DEFAULT_EMAIL: "admin@vx.home"
  PGADMIN_DEFAULT_PASSWORD: "YOUR_PGADMIN_PASSWORD_HERE"

  # OpenAI API key (optional - leave placeholder if not using OpenAI)
  OPENAI_API_KEY: "sk-your-key-here"
```

### Step 2d: Apply the Secret

```bash
kubectl apply -f k8s/clusters/vx-home/apps/ai-stack/secrets.yaml
```

**What this does:**
- Creates a Secret named `ai-secrets` in the `ai` namespace
- Stores your credentials as base64-encoded key-value pairs
- Makes them available for pods to mount as environment variables

```bash
# Verify the secret was created (values are hidden)
kubectl get secret ai-secrets -n ai
```

```bash
# See the secret keys (not values)
kubectl describe secret ai-secrets -n ai
```

---

## Phase 3: Deploy the Databases

Databases must be running before applications that depend on them. We use **StatefulSets** for databases because they provide:
- Stable network identity (pod name like `pgvector-0`)
- Stable persistent storage (PVC bound to specific pod)
- Ordered startup/shutdown
- Predictable DNS names (e.g., `pgvector-0.pgvector.ai.svc.cluster.local`)

### Step 3a: Deploy PostgreSQL with pgvector

**What is pgvector?**
PostgreSQL extension for vector similarity search. Used by Open WebUI for semantic search and embeddings storage (RAG).

```bash
# Apply the StatefulSet
kubectl apply -f k8s/clusters/vx-home/apps/ai-stack/pgvector/statefulset.yaml
```

**What this manifest does:**
- Creates a StatefulSet named `pgvector` with 1 replica
- Uses the `pgvector/pgvector:pg18` image (PostgreSQL 18 + pgvector)
- Reads credentials from `ai-secrets` (POSTGRES_DB, POSTGRES_USER, POSTGRES_PASSWORD)
- Requests a 50Gi PersistentVolumeClaim for data (`/var/lib/postgresql/data`)
- Sets resource limits (256Mi-2Gi RAM, 0.25-2 CPU cores)
- Configures health checks using `pg_isready`

```bash
# Apply the Service
kubectl apply -f k8s/clusters/vx-home/apps/ai-stack/pgvector/service.yaml
```

**What this Service does:**
- Creates a ClusterIP service named `pgvector`
- Makes PostgreSQL reachable at `pgvector:5432` from other pods
- Uses `selector: app: pgvector` to find the pods
- `sessionAffinity: ClientIP` ensures clients stick to the same pod

```bash
# Watch the pod start up
kubectl get pods -n ai -l app=pgvector -w
```

Wait for `STATUS: Running` and `READY: 1/1`. Press Ctrl+C to exit watch.

```bash
# Check the PVC was created and bound
kubectl get pvc -n ai
```

**Expected output:**
```
NAME                    STATUS   VOLUME    CAPACITY   ACCESS MODES   STORAGECLASS
pgdata-pgvector-0       Bound    pvc-...   50Gi       RWO            microk8s-hostpath
```

### Step 3b: Deploy Redis

**What is Redis?**
In-memory data store used for:
- Session caching (faster than database lookups)
- Rate limiting
- Pub/sub messaging

```bash
# Apply the StatefulSet
kubectl apply -f k8s/clusters/vx-home/apps/ai-stack/redis/statefulset.yaml
```

**What this manifest does:**
- Creates StatefulSet `redis` with `redis:8-alpine` image
- Enables persistence with `--appendonly yes` (AOF - Append Only File)
- Saves snapshot every 60 seconds if at least 1 key changed (`--save 60 1`)
- Requests 10Gi storage for persistence
- Health check uses `redis-cli ping`

```bash
# Apply the Service
kubectl apply -f k8s/clusters/vx-home/apps/ai-stack/redis/service.yaml
```

```bash
# Verify Redis is running
kubectl get pods -n ai -l app=redis
```

---

## Phase 4: Deploy Admin Tools

### Step 4a: Deploy pgAdmin

**What is pgAdmin?**
Web-based PostgreSQL administration tool. Useful for:
- Running SQL queries
- Viewing table structures
- Monitoring database performance

```bash
# First, create the ConfigMap with server configuration
kubectl apply -f k8s/clusters/vx-home/apps/ai-stack/pgadmin/configmap-servers.yaml
```

**What this ConfigMap does:**
- Pre-configures pgAdmin with our PostgreSQL connection
- Server appears automatically in the pgAdmin UI (no manual setup needed)
- Connection uses internal DNS: `pgvector:5432`

```bash
# Deploy pgAdmin
kubectl apply -f k8s/clusters/vx-home/apps/ai-stack/pgadmin/deployment.yaml
```

**What this Deployment does:**
- Runs `dpage/pgadmin4:latest` container
- Gets login credentials from `ai-secrets` (PGADMIN_DEFAULT_EMAIL, PGADMIN_DEFAULT_PASSWORD)
- Mounts the servers.json ConfigMap so PostgreSQL appears pre-configured
- Sets `SCRIPT_NAME=/pgadmin` for path-based routing (we access it at /pgadmin)

```bash
# Apply the Service
kubectl apply -f k8s/clusters/vx-home/apps/ai-stack/pgadmin/service.yaml
```

```bash
# Check pgAdmin is running
kubectl get pods -n ai -l app=pgadmin
```

---

## Phase 5: Deploy AI Services (TTS/STT)

These services have a `nodeSelector` requiring `gpu=true` label. They won't schedule if the label is missing.

### Step 5a: Deploy Kokoro (Text-to-Speech)

**What is Kokoro?**
High-quality text-to-speech engine. Runs on CPU (GPU version available).

```bash
kubectl apply -f k8s/clusters/vx-home/apps/ai-stack/kokoro/deployment.yaml
kubectl apply -f k8s/clusters/vx-home/apps/ai-stack/kokoro/service.yaml
```

**Key configuration:**
- Uses `nodeSelector: gpu: "true"` - only schedules on labeled nodes
- Default voice: `af_bella`
- Health endpoint: `/health` on port 8880
- Service available at `kokoro:8880`

### Step 5b: Deploy Faster-Whisper (Speech-to-Text)

**What is Faster-Whisper?**
OpenAI Whisper implementation optimized for speed. Transcribes audio to text.

```bash
kubectl apply -f k8s/clusters/vx-home/apps/ai-stack/faster-whisper/deployment.yaml
kubectl apply -f k8s/clusters/vx-home/apps/ai-stack/faster-whisper/service.yaml
```

**Key configuration:**
- Also requires `gpu: "true"` node label
- Uses the `base` model (good balance of speed/accuracy)
- Configured for CPU inference (`WHISPER__INFERENCE_DEVICE: cpu`)
- Service available at `faster-whisper:8000`

```bash
# Check both are scheduling (may take a moment to pull images)
kubectl get pods -n ai -l 'app in (kokoro,faster-whisper)'
```

If pods are stuck in `Pending`, check events:
```bash
kubectl describe pod -n ai -l app=kokoro
```

Look for: `0/1 nodes are available: 1 node(s) didn't match Pod's node affinity/selector`

---

## Phase 6: Deploy Open WebUI

This is the main application - a ChatGPT-like interface that connects to everything.

### Step 6a: Create the PersistentVolumeClaim

```bash
kubectl apply -f k8s/clusters/vx-home/apps/ai-stack/openwebui/pvc.yaml
```

**What this PVC does:**
- Requests 20Gi storage from `microk8s-hostpath` StorageClass
- Stores uploaded files, conversation history, and user data
- `ReadWriteOnce` - can only be mounted by one pod at a time

```bash
# Verify PVC is bound
kubectl get pvc openwebui-data -n ai
```

### Step 6b: Deploy Open WebUI

```bash
kubectl apply -f k8s/clusters/vx-home/apps/ai-stack/openwebui/deployment.yaml
kubectl apply -f k8s/clusters/vx-home/apps/ai-stack/openwebui/service.yaml
```

**What this Deployment does:**
- Runs `ghcr.io/open-webui/open-webui:v0.6.42`
- Connects to PostgreSQL via `DATABASE_URL` from secrets
- Connects to Redis via `REDIS_URL` environment variable
- Uses OpenAI API key from secrets (for ChatGPT integration)
- Mounts the PVC at `/app/backend/data`
- Health checks on `/health` endpoint

```bash
# Watch Open WebUI start (may take 1-2 minutes to pull image)
kubectl get pods -n ai -l app=openwebui -w
```

### Step 6c: Check All Pods

```bash
kubectl get pods -n ai
```

**Expected output (all should be Running/Ready):**
```
NAME                         READY   STATUS    RESTARTS   AGE
pgvector-0                   1/1     Running   0          5m
redis-0                      1/1     Running   0          4m
pgadmin-xxxxxxxxxx-xxxxx     1/1     Running   0          3m
kokoro-xxxxxxxxxx-xxxxx      1/1     Running   0          2m
faster-whisper-xxxxx-xxxxx   1/1     Running   0          2m
openwebui-xxxxxxxxxx-xxxxx   1/1     Running   0          1m
```

---

## Phase 7: Initialize pgvector Extension

PostgreSQL needs the vector extension enabled in the database.

```bash
# Get the pgvector pod name
PGPOD=$(kubectl get pod -n ai -l app=pgvector -o jsonpath='{.items[0].metadata.name}')

# Execute psql inside the pod
kubectl exec -it $PGPOD -n ai -- psql -U openwebui -d openwebui -c "CREATE EXTENSION IF NOT EXISTS vector;"
```

**What this does:**
- Runs `psql` inside the PostgreSQL container
- Connects as user `openwebui` to database `openwebui`
- Creates the `vector` extension (enables vector data type and similarity functions)

```bash
# Verify the extension is installed
kubectl exec -it $PGPOD -n ai -- psql -U openwebui -d openwebui -c "SELECT extname, extversion FROM pg_extension WHERE extname = 'vector';"
```

**Expected output:**
```
 extname | extversion
---------+------------
 vector  | 0.8.0
```

---

## Phase 8: Deploy Ingress Resources

Ingress exposes your services to the network via HTTP/HTTPS.

### Step 8a: Verify cert-manager ClusterIssuers

These were created during setup. They manage TLS certificates.

```bash
kubectl get clusterissuers
```

**Expected output:**
```
NAME                READY   AGE
selfsigned-issuer   True    1d
vx-home-ca-issuer   True    1d
```

If missing, apply them:
```bash
kubectl apply -f k8s/clusters/vx-home/cert-manager/clusterissuer.yaml
```

### Step 8b: Deploy Open WebUI Ingress

```bash
kubectl apply -f k8s/clusters/vx-home/ingress/openwebui-ingress.yaml
```

**What this Ingress does:**
- Routes `https://ai.adm.vx.home` → `openwebui:80` service
- Requests TLS certificate from `vx-home-ca-issuer` (annotation: `cert-manager.io/cluster-issuer`)
- Stores certificate in secret `openwebui-tls`
- Sets large upload limits (50MB) and long timeouts (600s) for AI operations

### Step 8c: Deploy Control Portal Ingress

```bash
kubectl apply -f k8s/clusters/vx-home/ingress/control-ingress.yaml
```

**What this creates:**
- Landing page at `https://control.adm.vx.home/`
- pgAdmin at `https://control.adm.vx.home/pgadmin`
- Uses path rewriting (`/pgadmin/foo` → `/foo` for pgAdmin)
- Deploys a simple nginx container serving the landing page

```bash
# Verify Ingress resources
kubectl get ingress -n ai
```

**Expected output:**
```
NAME                   CLASS    HOSTS                  ADDRESS     PORTS     AGE
openwebui              public   ai.adm.vx.home         127.0.0.1   80, 443   1m
control-admin-portal   public   control.adm.vx.home    127.0.0.1   80, 443   1m
control-root           public   control.adm.vx.home    127.0.0.1   80, 443   1m
```

### Step 8d: Verify TLS Certificates

cert-manager automatically creates certificates when it sees the annotation.

```bash
kubectl get certificates -n ai
```

**Expected output:**
```
NAME                 READY   SECRET               AGE
openwebui-tls        True    openwebui-tls        1m
control-portal-tls   True    control-portal-tls   1m
```

If `READY` is `False`, check certificate status:
```bash
kubectl describe certificate openwebui-tls -n ai
```

---

## Phase 9: Configure DNS/Hosts

Your browser needs to resolve the hostnames to your node's IP.

### Option A: Edit /etc/hosts (Simplest)

```bash
# Get your node's IP
kubectl get nodes -o wide
```

Add to `/etc/hosts` on your workstation (the machine with the browser):

```
10.0.3.5  ai.adm.vx.home control.adm.vx.home ptnr.adm.vx.home
```

### Option B: DNS Server

If you have a DNS server (like Pi-hole, dnsmasq, or Windows DNS), add A records:
- `ai.adm.vx.home` → 10.0.3.5
- `control.adm.vx.home` → 10.0.3.5
- `ptnr.adm.vx.home` → 10.0.3.5

---

## Phase 10: Trust the CA Certificate (Optional)

Since we use a self-signed CA, browsers will show security warnings. To avoid this:

### Step 10a: Extract the CA Certificate

```bash
kubectl get secret vx-home-ca-secret -n cert-manager -o jsonpath='{.data.tls\.crt}' | base64 -d > vx-home-ca.crt
```

### Step 10b: Trust the Certificate

**Linux (Chrome/Firefox):**
```bash
sudo cp vx-home-ca.crt /usr/local/share/ca-certificates/
sudo update-ca-certificates
```

**macOS:**
```bash
sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain vx-home-ca.crt
```

**Windows:**
Import `vx-home-ca.crt` into "Trusted Root Certification Authorities" using `certmgr.msc`.

---

## Phase 11: Access Your Applications

### Open WebUI
- **URL:** https://ai.adm.vx.home
- **First visit:** Create an admin account
- **Configure:** Settings → Connections to add LLM providers (OpenAI, Ollama, etc.)

### Control Portal
- **URL:** https://control.adm.vx.home
- **pgAdmin:** https://control.adm.vx.home/pgadmin
  - Login with `PGADMIN_DEFAULT_EMAIL` and `PGADMIN_DEFAULT_PASSWORD`
  - PostgreSQL server is pre-configured (just enter the password when connecting)

### Portainer (if installed)
- **URL:** https://ptnr.adm.vx.home

---

## Verification Commands

### Check All Resources

```bash
# All pods
kubectl get pods -n ai

# All services
kubectl get svc -n ai

# All PVCs
kubectl get pvc -n ai

# All ingresses
kubectl get ingress -n ai

# All certificates
kubectl get certificates -n ai
```

### Check Service Endpoints

```bash
# Verify services have endpoints (pods are backing them)
kubectl get endpoints -n ai
```

All services should have IPs listed (not `<none>`).

### Test Internal Connectivity

```bash
# Test DNS resolution from inside a pod
kubectl exec -it deploy/openwebui -n ai -- nslookup pgvector

# Test PostgreSQL connection
kubectl exec -it deploy/openwebui -n ai -- nc -zv pgvector 5432

# Test Redis connection
kubectl exec -it deploy/openwebui -n ai -- nc -zv redis 6379
```

### View Logs

```bash
# Open WebUI logs
kubectl logs -f deploy/openwebui -n ai

# PostgreSQL logs
kubectl logs -f sts/pgvector -n ai

# Ingress controller logs (for debugging routing)
kubectl logs -f -n ingress daemonset/nginx-ingress-microk8s-controller
```

### Check Events

```bash
# Recent events (useful for troubleshooting)
kubectl get events -n ai --sort-by='.lastTimestamp' | tail -20
```

---

## Phase 12: GPU Enablement (Optional)

If your node has an NVIDIA GPU, enable GPU support for accelerated TTS/STT.

> **Important:** The `microk8s enable nvidia` addon often fails. This guide uses the more reliable Helm-based installation with MicroK8s-specific fixes.

### Step 12a: Verify NVIDIA Driver

```bash
# Check driver is installed
nvidia-smi
```

**Expected output:** GPU information with driver version and CUDA version.

### Step 12b: Add NVIDIA Helm Repository

```bash
# Add the NVIDIA Helm repo
helm repo add nvidia https://helm.ngc.nvidia.com/nvidia
helm repo update
```

### Step 12c: Install GPU Operator via Helm

```bash
# Install with MicroK8s-specific containerd settings
helm install gpu-operator nvidia/gpu-operator \
  --namespace gpu-operator \
  --create-namespace \
  --set driver.enabled=false \
  --set toolkit.env[0].name=CONTAINERD_CONFIG \
  --set toolkit.env[0].value=/var/snap/microk8s/current/args/containerd-template.toml \
  --set toolkit.env[1].name=CONTAINERD_SOCKET \
  --set toolkit.env[1].value=/var/snap/microk8s/common/run/containerd.sock \
  --set toolkit.env[2].name=CONTAINERD_RUNTIME_CLASS \
  --set toolkit.env[2].value=nvidia \
  --timeout 10m
```

**Key settings:**
- `driver.enabled=false` - Use host-installed NVIDIA driver (already have it)
- `toolkit.env[*]` - MicroK8s uses snap, so containerd paths differ from standard

### Step 12d: Create NVIDIA Runtime Config (CRITICAL)

The GPU Operator's toolkit creates a broken config with unexpanded variables. Create the correct config:

```bash
sudo mkdir -p /etc/containerd/conf.d

sudo tee /etc/containerd/conf.d/99-nvidia.toml << 'EOF'
version = 2

[plugins."io.containerd.grpc.v1.cri".containerd.runtimes.nvidia]
  runtime_type = "io.containerd.runc.v2"
  [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.nvidia.options]
    BinaryName = "/usr/local/nvidia/toolkit/nvidia-container-runtime"
EOF

# Restart containerd to pick up the config
sudo snap restart microk8s.daemon-containerd
```

### Step 12e: Wait for GPU Operator

```bash
# Watch pods come up (5-10 minutes)
kubectl get pods -n gpu-operator -w
```

Wait until all pods show `Running` or `Completed`.

### Step 12f: Verify GPU Available

```bash
# Check ClusterPolicy status
kubectl get clusterpolicy
# Should show STATUS: ready

# Check GPU is visible to Kubernetes
kubectl describe node | grep -A5 "Allocatable:" | grep nvidia
```

**Expected output:** `nvidia.com/gpu: 1`

### Step 12g: Configure GPU Time-Slicing (Required for Multiple GPU Pods)

If you have multiple pods that need GPU (e.g., Kokoro AND Faster-Whisper), configure time-slicing to share the GPU:

```bash
# Create time-slicing ConfigMap
kubectl apply -n gpu-operator -f - <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: time-slicing-config
  namespace: gpu-operator
data:
  any: |-
    version: v1
    flags:
      migStrategy: none
    sharing:
      timeSlicing:
        resources:
        - name: nvidia.com/gpu
          replicas: 2
EOF

# Patch ClusterPolicy to use time-slicing
kubectl patch clusterpolicy cluster-policy \
  --type merge \
  -p '{"spec": {"devicePlugin": {"config": {"name": "time-slicing-config", "default": "any"}}}}'

# Wait for device plugin to restart
kubectl rollout status daemonset/nvidia-device-plugin-daemonset -n gpu-operator --timeout=120s

# Verify - should now show nvidia.com/gpu: 2
kubectl describe node | grep -A5 "Allocatable:" | grep nvidia
```

**What is time-slicing?**
- Allows multiple pods to share a single physical GPU
- Pods take turns using the GPU (time-multiplexed)
- No memory isolation between pods (unlike MIG)
- `replicas: 2` means 2 pods can each request 1 GPU

### Step 12h: Test GPU Access

```bash
# Run a test pod with nvidia-smi
kubectl run gpu-test --rm -it --restart=Never \
  --image=nvidia/cuda:12.3.1-base-ubuntu22.04 \
  --limits=nvidia.com/gpu=1 \
  -- nvidia-smi
```

### Step 12i: Update Kokoro to GPU Image

```bash
# Apply GPU deployment (manifest already updated)
kubectl apply -f k8s/clusters/vx-home/apps/ai-stack/kokoro/deployment.yaml

# Restart to pick up changes
kubectl rollout restart deployment kokoro -n ai-stack

# Watch pod start (larger image, may take longer)
kubectl get pods -n ai-stack -l app=kokoro -w

# Verify GPU is being used
kubectl logs -l app=kokoro -n ai-stack | head -30
```

### Step 12j: Update Faster-Whisper to CUDA Image

```bash
# Apply CUDA deployment (manifest already updated)
kubectl apply -f k8s/clusters/vx-home/apps/ai-stack/faster-whisper/deployment.yaml

# Restart to pick up changes
kubectl rollout restart deployment faster-whisper -n ai-stack

# Watch pod start
kubectl get pods -n ai-stack -l app=faster-whisper -w

# Verify CUDA device
kubectl logs -l app=faster-whisper -n ai-stack | head -30
```

### Step 12k: Verify GPU Allocation

```bash
# Check both pods have GPU
kubectl get pods -n ai-stack -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.containers[*].resources.limits}{"\n"}{end}'

# Check node GPU usage
kubectl describe node | grep -A10 "Allocated resources"
```

### Troubleshooting GPU Issues

**Problem: Node shows NotReady after containerd restart**
```bash
# Check containerd logs
journalctl -u snap.microk8s.daemon-containerd --no-pager -n 50

# If you see "${RUNTIME}" errors, the nvidia config is wrong
# Delete the broken file and recreate with the minimal config above
sudo rm /etc/containerd/conf.d/99-nvidia.toml
# Then recreate it as shown in Step 12d
```

**Problem: Pods stuck with "no runtime for nvidia is configured"**
```bash
# The nvidia runtime isn't registered - recreate the config
sudo tee /etc/containerd/conf.d/99-nvidia.toml << 'EOF'
version = 2

[plugins."io.containerd.grpc.v1.cri".containerd.runtimes.nvidia]
  runtime_type = "io.containerd.runc.v2"
  [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.nvidia.options]
    BinaryName = "/usr/local/nvidia/toolkit/nvidia-container-runtime"
EOF

sudo snap restart microk8s.daemon-containerd

# Delete stuck pods to force recreation
kubectl delete pods -n gpu-operator -l app=nvidia-device-plugin-daemonset --force
```

**Problem: "Insufficient nvidia.com/gpu" when scheduling pods**
```bash
# You only have 1 GPU but multiple pods need it
# Configure time-slicing as shown in Step 12g
```

---

## Phase 13: Configure Open WebUI TTS/STT

Open WebUI can use local Kokoro (TTS) and Faster-Whisper (STT) services.

### Step 13a: Redeploy Open WebUI

The manifest has been updated with TTS/STT environment variables. Fresh deploy:

```bash
# Delete existing deployment and PVC (fresh start)
kubectl delete deployment openwebui -n ai
kubectl delete pvc openwebui-data -n ai

# If PVC is stuck, force delete
kubectl patch pvc openwebui-data -n ai -p '{"metadata":{"finalizers":null}}'

# Recreate PVC and deployment
kubectl apply -f k8s/clusters/vx-home/apps/ai-stack/openwebui/pvc.yaml
kubectl apply -f k8s/clusters/vx-home/apps/ai-stack/openwebui/deployment.yaml

# Watch pod start
kubectl get pods -n ai -l app=openwebui -w
```

### Step 13b: Verify TTS/STT Connectivity

```bash
# Test Kokoro TTS health
kubectl exec -it deploy/openwebui -n ai -- curl -s http://kokoro:8880/health

# Test Faster-Whisper STT health
kubectl exec -it deploy/openwebui -n ai -- curl -s http://faster-whisper:8000/health
```

### Step 13c: Check Configuration in Logs

```bash
# Look for audio configuration in Open WebUI logs
kubectl logs -l app=openwebui -n ai | grep -i "audio\|tts\|stt"
```

### Step 13d: Browser Test

1. Open https://ai.vx.home
2. Create a new admin account (fresh database)
3. Go to **Settings → Audio**
4. Test **Voice Input** (STT) - click microphone, speak, see transcription
5. Test **Voice Output** (TTS) - enable read aloud, hear response

**TTS/STT Environment Variables (for reference):**
```yaml
# TTS (Kokoro)
AUDIO_TTS_ENGINE: "openai"
AUDIO_TTS_OPENAI_API_BASE_URL: "http://kokoro:8880/v1"

# STT (Faster-Whisper)
AUDIO_STT_ENGINE: "openai"
AUDIO_STT_OPENAI_API_BASE_URL: "http://faster-whisper:8000/v1"
```

See `docs/45-openwebui-env-reference.md` for complete environment variable documentation.

---

## Phase 14: Enable MicroCeph Storage

MicroCeph provides enterprise-grade distributed storage (Ceph) for Kubernetes. It replaces `hostpath-storage` with proper CSI-backed storage that supports:
- **CephFS (ReadWriteMany)** - Shared storage for multiple pods
- **RBD (ReadWriteOnce)** - Block storage for databases

### Step 14a: Install MicroCeph Snap

```bash
sudo snap install microceph --channel=latest/stable
```

### Step 14b: Bootstrap Single-Node Cluster

```bash
sudo microceph cluster bootstrap
sudo microceph status
```

**Expected output:**
```
MicroCeph deployment summary:
- ceph-mds: 1
- ceph-mgr: 1
- ceph-mon: 1
```

### Step 14c: Add OSD (Dedicated Disk - Recommended)

If you have a dedicated disk for Ceph storage (recommended):

```bash
# Identify your disk (should show no partitions/filesystem)
lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT

# Verify disk is clean (should show nothing)
sudo wipefs /dev/sdb

# Add directly to MicroCeph
sudo microceph disk add /dev/sdb --wipe
```

Verify:
```bash
sudo microceph.ceph status
```

**Expected:** `HEALTH_OK` or `HEALTH_WARN` (warn is normal for single-node)

<details>
<summary><strong>Alternative: Loop Device (No Spare Disk)</strong></summary>

If you don't have a dedicated disk, use a file-backed loop device:

```bash
# Create directory and loop file (50GB minimum)
sudo mkdir -p /var/lib/microceph-loop
sudo truncate -s 50G /var/lib/microceph-loop/osd.img

# Create loop device
LOOP_DEV=$(sudo losetup -f --show /var/lib/microceph-loop/osd.img)
echo "Created loop device: $LOOP_DEV"

# Add to MicroCeph
sudo microceph disk add $LOOP_DEV --wipe

# Create systemd service for persistence across reboots
sudo tee /etc/systemd/system/microceph-loop.service << 'EOF'
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

sudo systemctl daemon-reload
sudo systemctl enable microceph-loop.service
```

**Note:** Loop device has ~30-50% I/O overhead vs dedicated disk.
</details>

### Step 14d: Enable rook-ceph Addon

```bash
sudo microk8s enable rook-ceph
```

Wait 2-3 minutes for pods:
```bash
microk8s kubectl get pods -n rook-ceph -w
```

### Step 14e: Connect MicroK8s to MicroCeph

```bash
sudo microk8s connect-external-ceph
```

### Step 14f: Configure Pool for Single-Node

**Critical:** The `connect-external-ceph` command creates a pool with default replication (size=3). With only 1 OSD, this causes PGs to be stuck `inactive/undersized` and PVCs will hang forever.

```bash
# Allow single-replica pools
sudo microceph.ceph config set global mon_allow_pool_size_one true

# Set global defaults
sudo microceph.ceph config set global osd_pool_default_size 1
sudo microceph.ceph config set global osd_pool_default_min_size 1

# Fix the existing pool
sudo microceph.ceph osd pool set microk8s-rbd0 size 1 --yes-i-really-mean-it
sudo microceph.ceph osd pool set microk8s-rbd0 min_size 1

# Verify health (should now show HEALTH_OK or minor warnings)
sudo microceph.ceph health
```

**Expected:** `HEALTH_OK` or `HEALTH_WARN` (warn about auth insecure is normal).

> When expanding to multi-node later, increase these values for redundancy.

### Step 14g: Enable CephFS (for RWX volumes)

The `connect-external-ceph` command only creates the `ceph-rbd` StorageClass. For ReadWriteMany (RWX) volumes needed for horizontally-scalable applications like Open WebUI, enable CephFS:

```bash
./scripts/setup/16-enable-cephfs.sh
```

This script creates:
1. CephFS data and metadata pools
2. The CephFS filesystem
3. A dedicated CephFS user for Kubernetes
4. Kubernetes secrets and StorageClass

**What this enables:**
- **cephfs StorageClass**: ReadWriteMany (RWX) - multiple pods can mount the same volume
- Use for: Open WebUI, shared configs, logs, any horizontally-scaled workload

### Step 14h: Verify StorageClasses

```bash
microk8s kubectl get sc
```

**Expected output (after CephFS enablement):**
```
NAME                          PROVISIONER                    ...
ceph-rbd                      rook-ceph.rbd.csi.ceph.com    ...
cephfs                        rook-ceph.cephfs.csi.ceph.com ...
microk8s-hostpath (default)   microk8s.io/hostpath          ...
```

> **Note:** If you skipped Step 14g, only `ceph-rbd` will be available.

### Step 14i: Test PVC Binding

**Test RBD (ReadWriteOnce):**
```bash
microk8s kubectl apply -f - <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: test-rbd
  namespace: default
spec:
  accessModes: [ReadWriteOnce]
  storageClassName: ceph-rbd
  resources:
    requests:
      storage: 1Gi
EOF

microk8s kubectl get pvc test-rbd -w
# Wait for Bound, then cleanup
microk8s kubectl delete pvc test-rbd
```

**Test CephFS (ReadWriteMany) - if Step 14g was completed:**
```bash
microk8s kubectl apply -f - <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: test-cephfs
  namespace: default
spec:
  accessModes: [ReadWriteMany]
  storageClassName: cephfs
  resources:
    requests:
      storage: 1Gi
EOF

microk8s kubectl get pvc test-cephfs -w
# Wait for Bound, then cleanup
microk8s kubectl delete pvc test-cephfs
```

---

## Phase 15: Install HashiCorp Vault

Vault provides centralized secrets management with audit logging and fine-grained access control.

### Step 15a: Add Helm Repository

```bash
microk8s helm3 repo add hashicorp https://helm.releases.hashicorp.com
microk8s helm3 repo update
```

### Step 15b: Create Vault Namespace

```bash
microk8s kubectl create namespace vault
```

### Step 15c: Install Vault via Helm

```bash
microk8s helm3 install vault hashicorp/vault \
  --namespace vault \
  -f helm-values/vault-values.yaml
```

### Step 15d: Wait for Pod

```bash
microk8s kubectl get pods -n vault -w
```

**Note:** Pod will show `0/1 Ready` until initialized - this is expected.

### Step 15e: Initialize Vault

```bash
microk8s kubectl exec -n vault vault-0 -- vault operator init \
  -key-shares=1 \
  -key-threshold=1 \
  -format=json > .vault-keys
```

**CRITICAL:** Back up `.vault-keys` securely! Contains unseal key and root token.

### Step 15f: Unseal Vault

```bash
UNSEAL_KEY=$(cat .vault-keys | jq -r '.unseal_keys_b64[0]')
microk8s kubectl exec -n vault vault-0 -- vault operator unseal $UNSEAL_KEY
```

### Step 15g: Verify Status

```bash
microk8s kubectl exec -n vault vault-0 -- vault status
```

**Expected:** `Sealed: false`

---

## Phase 16: Configure Vault

### Step 16a: Login with Root Token

```bash
ROOT_TOKEN=$(cat .vault-keys | jq -r '.root_token')
microk8s kubectl exec -n vault vault-0 -- vault login $ROOT_TOKEN
```

### Step 16b: Enable Kubernetes Auth

```bash
microk8s kubectl exec -n vault vault-0 -- vault auth enable kubernetes

microk8s kubectl exec -n vault vault-0 -- vault write auth/kubernetes/config \
  kubernetes_host="https://kubernetes.default.svc:443"
```

### Step 16c: Enable KV Secrets Engine

```bash
microk8s kubectl exec -n vault vault-0 -- vault secrets enable -path=ai kv-v2
```

### Step 16d: Create Policies

```bash
# OpenWebUI policy
microk8s kubectl exec -n vault vault-0 -- vault policy write openwebui-policy - <<'EOF'
path "ai/data/openwebui" {
  capabilities = ["read"]
}
path "ai/metadata/openwebui" {
  capabilities = ["read", "list"]
}
EOF

# PgVector policy
microk8s kubectl exec -n vault vault-0 -- vault policy write pgvector-policy - <<'EOF'
path "ai/data/pgvector" {
  capabilities = ["read"]
}
path "ai/metadata/pgvector" {
  capabilities = ["read", "list"]
}
EOF

# PgAdmin policy
microk8s kubectl exec -n vault vault-0 -- vault policy write pgadmin-policy - <<'EOF'
path "ai/data/pgadmin" {
  capabilities = ["read"]
}
path "ai/metadata/pgadmin" {
  capabilities = ["read", "list"]
}
EOF
```

### Step 16e: Create Roles

```bash
# OpenWebUI role
microk8s kubectl exec -n vault vault-0 -- vault write auth/kubernetes/role/openwebui-role \
  bound_service_account_names=openwebui \
  bound_service_account_namespaces=ai \
  policies=openwebui-policy \
  ttl=1h

# PgVector role
microk8s kubectl exec -n vault vault-0 -- vault write auth/kubernetes/role/pgvector-role \
  bound_service_account_names=pgvector \
  bound_service_account_namespaces=ai \
  policies=pgvector-policy \
  ttl=1h

# PgAdmin role
microk8s kubectl exec -n vault vault-0 -- vault write auth/kubernetes/role/pgadmin-role \
  bound_service_account_names=pgadmin \
  bound_service_account_namespaces=ai \
  policies=pgadmin-policy \
  ttl=1h
```

### Step 16f: Migrate Secrets from Kubernetes to Vault

```bash
# Extract existing secrets
OPENAI_KEY=$(microk8s kubectl get secret ai-secrets -n ai -o jsonpath='{.data.OPENAI_API_KEY}' | base64 -d)
DATABASE_URL=$(microk8s kubectl get secret ai-secrets -n ai -o jsonpath='{.data.DATABASE_URL}' | base64 -d)
POSTGRES_DB=$(microk8s kubectl get secret ai-secrets -n ai -o jsonpath='{.data.POSTGRES_DB}' | base64 -d)
POSTGRES_USER=$(microk8s kubectl get secret ai-secrets -n ai -o jsonpath='{.data.POSTGRES_USER}' | base64 -d)
POSTGRES_PASSWORD=$(microk8s kubectl get secret ai-secrets -n ai -o jsonpath='{.data.POSTGRES_PASSWORD}' | base64 -d)
PGADMIN_EMAIL=$(microk8s kubectl get secret ai-secrets -n ai -o jsonpath='{.data.PGADMIN_DEFAULT_EMAIL}' | base64 -d)
PGADMIN_PASSWORD=$(microk8s kubectl get secret ai-secrets -n ai -o jsonpath='{.data.PGADMIN_DEFAULT_PASSWORD}' | base64 -d)

# Write to Vault
microk8s kubectl exec -n vault vault-0 -- vault kv put ai/openwebui \
  OPENAI_API_KEY="$OPENAI_KEY" \
  DATABASE_URL="$DATABASE_URL" \
  POSTGRES_DB="$POSTGRES_DB" \
  POSTGRES_USER="$POSTGRES_USER" \
  POSTGRES_PASSWORD="$POSTGRES_PASSWORD"

microk8s kubectl exec -n vault vault-0 -- vault kv put ai/pgvector \
  POSTGRES_DB="$POSTGRES_DB" \
  POSTGRES_USER="$POSTGRES_USER" \
  POSTGRES_PASSWORD="$POSTGRES_PASSWORD"

microk8s kubectl exec -n vault vault-0 -- vault kv put ai/pgadmin \
  PGADMIN_DEFAULT_EMAIL="$PGADMIN_EMAIL" \
  PGADMIN_DEFAULT_PASSWORD="$PGADMIN_PASSWORD"
```

### Step 16g: Verify Secrets in Vault

```bash
microk8s kubectl exec -n vault vault-0 -- vault kv list ai/
microk8s kubectl exec -n vault vault-0 -- vault kv get ai/openwebui
```

### Step 16h: Apply Vault Ingress

```bash
microk8s kubectl apply -f k8s/overlays/vx-home/platform/vault/ingress.yaml
```

Access Vault UI at: https://vault.adm.vx.home

---

## Phase 17: Migrate to Kustomize Overlays

The new manifest structure uses Kustomize base/overlay pattern for better maintainability.

### Step 17a: Understand the New Structure

```
k8s/
├── base/                    # Generic manifests (no namespace, no secrets)
│   ├── openwebui/
│   ├── pgvector/
│   ├── redis/
│   ├── pgadmin/
│   ├── kokoro/
│   └── faster-whisper/
├── overlays/
│   └── vx-home/            # Environment-specific patches
│       ├── kustomization.yaml
│       ├── namespaces/
│       ├── cert-manager/
│       ├── ingress/
│       ├── platform/vault/
│       └── apps/           # App-specific patches (Vault annotations, GPU, storage)
└── clusters/vx-home/       # Original structure (kept until migration complete)
```

### Step 17b: Dry-Run New Overlay

```bash
# Preview what would be applied
microk8s kubectl apply -k k8s/overlays/vx-home --dry-run=client
```

### Step 17c: Diff Against Running State

```bash
# See differences from current cluster state
microk8s kubectl diff -k k8s/overlays/vx-home
```

### Step 17d: Apply Non-Critical Apps First

```bash
# Start with apps that don't have critical data
microk8s kubectl apply -k k8s/overlays/vx-home/apps/kokoro
microk8s kubectl apply -k k8s/overlays/vx-home/apps/faster-whisper
```

### Step 17e: Apply Full Overlay

```bash
# Apply entire overlay
microk8s kubectl apply -k k8s/overlays/vx-home
```

### Step 17f: Verify Vault Agent Injection

After applying overlays with Vault annotations:

```bash
# Check for vault-agent-init container
microk8s kubectl get pods -n ai -l app=openwebui -o jsonpath='{.items[0].spec.initContainers[*].name}'

# Should include: vault-agent-init

# Check secrets are injected
microk8s kubectl exec -n ai deploy/openwebui -c openwebui -- cat /vault/secrets/env
```

### Step 17g: Remove Old Kubernetes Secret (After Verification)

Only after confirming Vault injection works:

```bash
# Backup first
microk8s kubectl get secret ai-secrets -n ai -o yaml > ai-secrets-backup.yaml

# Delete old secret
microk8s kubectl delete secret ai-secrets -n ai
```

---

## Phase 18: Adding Worker Nodes

This phase covers adding additional nodes to expand cluster capacity and enable storage replication.

### Prerequisites (New Node)

- Rocky Linux 9.x installed
- Network connectivity to node-00 (10.0.3.5)
- Dedicated disk for Ceph OSD (e.g., /dev/sdb)
- Hostname configured (e.g., `vx-app-01.adm.vx.home`)

### Step 18a: Configure Firewall on New Node

```bash
# On new node (vx-app-01)
sudo firewall-cmd --permanent --add-port=16443/tcp   # MicroK8s API
sudo firewall-cmd --permanent --add-port=10250/tcp   # Kubelet
sudo firewall-cmd --permanent --add-port=10255/tcp   # Kubelet read-only
sudo firewall-cmd --permanent --add-port=25000/tcp   # Cluster agent
sudo firewall-cmd --permanent --add-port=12379/tcp   # etcd
sudo firewall-cmd --permanent --add-port=10257/tcp   # Controller manager
sudo firewall-cmd --permanent --add-port=10259/tcp   # Scheduler
sudo firewall-cmd --permanent --add-port=19001/tcp   # Dqlite
sudo firewall-cmd --permanent --add-port=4789/udp    # Calico VXLAN
sudo firewall-cmd --permanent --add-port=7443/tcp    # MicroCeph cluster API
sudo firewall-cmd --permanent --add-port=3300/tcp    # Ceph MON
sudo firewall-cmd --permanent --add-port=6789/tcp    # Ceph MON legacy
sudo firewall-cmd --permanent --add-port=6800-7300/tcp  # Ceph OSD
sudo firewall-cmd --reload
```

### Step 18b: Install Snap (Rocky Linux)

Rocky Linux requires EPEL and snapd to be installed first:

```bash
# On new node (vx-app-01)
# Install EPEL repository
sudo dnf install -y epel-release

# Install snapd
sudo dnf install -y snapd

# Enable and start snapd
sudo systemctl enable --now snapd.socket

# Create symlink for classic snap support
sudo ln -s /var/lib/snapd/snap /snap

# IMPORTANT: Log out and back in, or reboot, for snap paths to take effect
# Alternatively, run this to refresh your shell:
exec $SHELL
```

### Step 18c: Install MicroK8s on New Node

```bash
# On new node (vx-app-01)
sudo snap install microk8s --classic --channel=1.35/stable
sudo usermod -aG microk8s $USER
newgrp microk8s
```

### Step 18d: Generate Join Token (From Existing Node)

```bash
# On vx-app-00 - generates a one-time join token
microk8s add-node
```

**Output will look like:**
```
From the node you wish to join to this cluster, run the following:
microk8s join 10.0.3.5:25000/abc123def456...

Use the '--worker' flag to join as a worker (no control plane).
```

### Step 18e: Join MicroK8s Cluster (On New Node)

```bash
# On new node (vx-app-01) - use the token from previous step
microk8s join 10.0.3.5:25000/<token>
```

**Note:** All MicroK8s nodes share control plane duties by default. This provides HA but uses more resources. Use `--worker` flag if you want a worker-only node.

### Step 18f: Verify MicroK8s Join

```bash
# On either node
microk8s kubectl get nodes
```

**Expected:**
```
NAME                    STATUS   ROLES    AGE   VERSION
vx-app-00.adm.vx.home   Ready    <none>   7d    v1.35.x
vx-app-01.adm.vx.home   Ready    <none>   1m    v1.35.x
```

### Step 18g: Label Nodes

```bash
# On vx-app-00 (or any node with kubectl access)
# Label GPU node
microk8s kubectl label node vx-app-00.adm.vx.home gpu=true

# Label non-GPU node
microk8s kubectl label node vx-app-01.adm.vx.home gpu=false

# Verify labels
microk8s kubectl get nodes --show-labels | grep gpu
```

### Step 18h: Install MicroCeph on New Node

```bash
# On new node (vx-app-01)
sudo snap install microceph --channel=latest/stable
```

### Step 18i: Generate MicroCeph Join Token (From Existing Node)

```bash
# On vx-app-00
sudo microceph cluster add vx-app-01
```

**Save the output token for the next step.**

### Step 18j: Join MicroCeph Cluster (On New Node)

```bash
# On new node (vx-app-01) - use token from previous step
sudo microceph cluster join <token>
```

### Step 18k: Add OSD on New Node

```bash
# On new node (vx-app-01)
# Verify disk exists
lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT

# Add disk to Ceph (assuming /dev/sdb)
sudo microceph disk add /dev/sdb --wipe
```

### Step 18l: Update Pool Replication

Now that you have 2 OSDs, increase replication for data redundancy:

```bash
# On vx-app-00 (or any node)
# Update pool to replicate across 2 OSDs
sudo microceph.ceph osd pool set microk8s-rbd0 size 2
sudo microceph.ceph osd pool set microk8s-rbd0 min_size 1

# Update global defaults for future pools
sudo microceph.ceph config set global osd_pool_default_size 2
```

**Pool Size Guidance:**
| OSDs | Recommended size | min_size | Notes |
|------|------------------|----------|-------|
| 1    | 1                | 1        | No redundancy |
| 2    | 2                | 1        | Single disk failure tolerance |
| 3+   | 3                | 2        | Full redundancy |

### Step 18m: Verify Multi-Node Cluster

```bash
# MicroK8s cluster
microk8s kubectl get nodes -o wide

# MicroCeph cluster status
sudo microceph status

# Ceph health (should show 2 OSDs)
sudo microceph.ceph status

# OSD tree (should show both nodes)
sudo microceph.ceph osd tree

# Pool replication status
sudo microceph.ceph osd pool ls detail
```

**Expected Ceph output:**
```
cluster:
  id:     ...
  health: HEALTH_OK

services:
  mon: 2 daemons, quorum vx-app-00,vx-app-01
  osd: 2 osds: 2 up, 2 in
```

**Expected OSD tree:**
```
ID  CLASS  WEIGHT   TYPE NAME                STATUS
-1         0.23    root default
-3         0.11        host vx-app-00
 0   ssd   0.11            osd.0              up
-5         0.11        host vx-app-01
 1   ssd   0.11            osd.1              up
```

### Storage Architecture Summary

With 2 nodes and 1 OSD per node (2 OSDs total), storage is configured as:

| Application | Storage Class | Access Mode | Scaling |
|-------------|---------------|-------------|---------|
| Open WebUI | `cephfs` | ReadWriteMany | Horizontal (multiple replicas) |
| pgvector | `ceph-rbd` | ReadWriteOnce | Vertical |
| Redis | `ceph-rbd` | ReadWriteOnce | Vertical |
| Vault | `ceph-rbd` | ReadWriteOnce | Vertical |

**Key points:**
- Both RBD and CephFS pools share all OSDs (pooled storage)
- Data is replicated across both nodes (size=2)
- CephFS enables Open WebUI horizontal scaling under load

---

## Cleanup (If Needed)

To remove everything and start over:

```bash
# Delete all resources in the namespace
kubectl delete namespace ai

# This removes:
# - All Deployments, StatefulSets, Pods
# - All Services
# - All Ingresses
# - All Secrets, ConfigMaps
# - All PVCs (and their data!)

# Recreate the namespace
kubectl create namespace ai
```

**Warning:** Deleting the namespace destroys all PVC data (databases, uploads, etc.)

---

## Quick Reference: Resource Types

| Resource | Purpose | Example |
|----------|---------|---------|
| **Namespace** | Logical isolation | `ai` namespace |
| **Secret** | Sensitive config | Passwords, API keys |
| **ConfigMap** | Non-sensitive config | pgAdmin servers.json |
| **PersistentVolumeClaim** | Storage request | 50Gi for PostgreSQL |
| **StatefulSet** | Stateful workloads | PostgreSQL, Redis |
| **Deployment** | Stateless workloads | Open WebUI, pgAdmin |
| **Service** | Internal networking | ClusterIP for pod access |
| **Ingress** | External HTTP(S) | Route domains to services |
| **Certificate** | TLS certificates | Auto-managed by cert-manager |
| **ClusterIssuer** | CA for certificates | vx-home-ca-issuer |

---

## CKA Exam Relevance

This walkthrough covers these CKA domains:

- **Cluster Architecture (25%):** Namespace management, understanding cluster components, GPU device plugins
- **Workloads & Scheduling (15%):** Deployments, StatefulSets, nodeSelector, resource management, GPU limits
- **Services & Networking (20%):** Services, Ingress, DNS, connectivity testing
- **Storage (10%):** PVCs, StorageClasses, volume mounts
- **Troubleshooting (30%):** Logs, events, describe, exec, connectivity testing

---

*Last Updated: December 30, 2025*
