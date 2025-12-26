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
kubectl get nodes --show-labels | grep ai-stt-tts
```

**Expected output:** `ai-stt-tts=true`

If missing, label your node:
```bash
kubectl label node vx-app-00.adm.vx.home ai-stt-tts=true
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

These services have a `nodeSelector` requiring `ai-stt-tts=true` label. They won't schedule if the label is missing.

### Step 5a: Deploy Kokoro (Text-to-Speech)

**What is Kokoro?**
High-quality text-to-speech engine. Runs on CPU (GPU version available).

```bash
kubectl apply -f k8s/clusters/vx-home/apps/ai-stack/kokoro/deployment.yaml
kubectl apply -f k8s/clusters/vx-home/apps/ai-stack/kokoro/service.yaml
```

**Key configuration:**
- Uses `nodeSelector: ai-stt-tts: "true"` - only schedules on labeled nodes
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
- Also requires `ai-stt-tts: "true"` node label
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

*Last Updated: December 25, 2025*
