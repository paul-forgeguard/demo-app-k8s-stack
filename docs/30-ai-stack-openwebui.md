# AI Stack Deployment and Configuration

## Overview

This guide covers deploying and configuring the complete AI stack:
- **Open WebUI**: ChatGPT-like interface
- **Postgres + pgvector**: Vector database for RAG
- **Redis**: Session management and caching
- **pgAdmin**: Database administration
- **Kokoro TTS**: Text-to-speech service
- **Faster-Whisper STT**: Speech-to-text service

**Target URL**: `http://ai.vx.home`

## Prerequisites

Ensure you've completed:
- ✅ [MicroK8s Installation](10-microk8s-install.md)
- ✅ [Portainer Installation](20-portainer.md)
- ✅ Node labeled with `gpu=true`

## Deployment Steps

### Step 1: Create Secrets

The AI stack requires secrets for:
- Database passwords
- pgAdmin credentials
- OpenAI API key

**Create secrets from template**:

```bash
# Copy example to actual secrets file
cp k8s/clusters/vx-home/apps/ai-stack/secrets.example.yaml \
   k8s/clusters/vx-home/apps/ai-stack/secrets.yaml
```

**Edit with your values**:

```bash
# Edit the secrets file
vim k8s/clusters/vx-home/apps/ai-stack/secrets.yaml
```

**Replace these placeholders**:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: ai-secrets
  namespace: ai
type: Opaque
stringData:
  # Postgres
  POSTGRES_DB: openwebui
  POSTGRES_USER: openwebui
  POSTGRES_PASSWORD: "YOUR_STRONG_PASSWORD_HERE"  # <-- CHANGE THIS

  # pgAdmin
  PGADMIN_DEFAULT_EMAIL: "admin@vx.home"
  PGADMIN_DEFAULT_PASSWORD: "YOUR_PGADMIN_PASSWORD"  # <-- CHANGE THIS

  # OpenAI
  OPENAI_API_KEY: "sk-YOUR_OPENAI_API_KEY_HERE"  # <-- CHANGE THIS
```

**Password Best Practices**:
- Minimum 16 characters
- Mix of uppercase, lowercase, numbers, symbols
- Don't reuse passwords from other services
- Generate with: `openssl rand -base64 24`

**Get OpenAI API Key**:
1. Go to https://platform.openai.com/api-keys
2. Create new secret key
3. Copy to secrets.yaml

**CKA Learning Point**: Never commit secrets.yaml to Git (.gitignore prevents this)

### Step 2: Deploy the AI Stack

**Using admin script** (recommended):

```bash
# Deploy all resources
./scripts/admin/deploy.sh apply
```

**Using kubectl directly**:

```bash
# Apply with Kustomize
microk8s kubectl apply -k k8s/clusters/vx-home
```

**What this deploys**:
1. **Namespace**: `ai`
2. **Secrets**: `ai-secrets` (passwords, API keys)
3. **StatefulSets**: pgvector, redis (with PVCs)
4. **Deployments**: openwebui, pgadmin, kokoro, faster-whisper
5. **Services**: ClusterIP services for all pods
6. **Ingress**: Route `ai.vx.home` to Open WebUI
7. **ConfigMaps**: pgAdmin server configuration

**Watch deployment progress**:

```bash
# Watch pods come up
microk8s kubectl get pods -n ai -w

# Expected output:
# NAME                          READY   STATUS              RESTARTS   AGE
# pgvector-0                    0/1     ContainerCreating   0          5s
# redis-0                       0/1     ContainerCreating   0          5s
# openwebui-XXX                 0/1     Pending             0          5s
# pgadmin-XXX                   0/1     Pending             0          5s
# kokoro-XXX                    0/1     Pending             0          5s
# faster-whisper-XXX            0/1     Pending             0          5s
```

**Normal startup order** (2-5 minutes total):
1. PVCs bound (automatic with hostpath-storage)
2. pgvector-0, redis-0 start (StatefulSets start sequentially)
3. Once databases are ready, other pods start
4. All pods reach Running state

**Check final status**:

```bash
# All pods should be Running
microk8s kubectl get pods -n ai

# Example output:
# NAME                          READY   STATUS    RESTARTS   AGE
# pgvector-0                    1/1     Running   0          3m
# redis-0                       1/1     Running   0          3m
# openwebui-7d8f9-abc12         1/1     Running   0          2m
# pgadmin-5c7b8-def34           1/1     Running   0          2m
# kokoro-9a1e4-ghi56            1/1     Running   0          2m
# faster-whisper-3f6d2-jkl78    1/1     Running   0          2m
```

### Step 3: Initialize pgvector Extension

Postgres needs the vector extension enabled:

**Using admin script**:

```bash
./scripts/admin/init-pgvector.sh
```

**Manual method**:

```bash
# Connect to postgres pod
microk8s kubectl exec -it -n ai statefulset/pgvector -- psql -U openwebui -d openwebui

# Run SQL command
CREATE EXTENSION IF NOT EXISTS vector;

# Verify
\dx
# Output should show: vector | X.X.X | ...

# Exit
\q
```

**Troubleshooting**:
- If "role does not exist": Check POSTGRES_USER in secrets
- If "database does not exist": Check POSTGRES_DB in secrets
- If "permission denied": pgvector image may have issues (check logs)

### Step 4: Configure DNS

Add DNS entry for Open WebUI:

```bash
# Get your node IP
NODE_IP=$(hostname -I | awk '{print $1}')

# Add to /etc/hosts
echo "$NODE_IP ai.vx.home" | sudo tee -a /etc/hosts
```

**For multi-machine setup**:
Add to your workstation's `/etc/hosts` or configure in your DNS server.

### Step 5: Access Open WebUI

Open browser: `http://ai.vx.home`

**First-Time Setup**:
1. **Create Admin Account**:
   - Email: (your email)
   - Password: (strong password)
   - This is the Open WebUI admin, separate from Portainer

2. **Verify Connection**:
   - You should see the Open WebUI chat interface
   - Similar to ChatGPT web interface

## Open WebUI Configuration

### Admin Panel Access

1. Click **profile icon** (top-right)
2. Click **Admin Panel**
3. Navigate to **Settings**

### Configure Vector Database (RAG)

**Enable pgvector**:

1. **Admin Panel** → **Settings** → **Documents**
2. **Vector Database**:
   - Type: **PGVector**
   - Connection String: `postgresql://openwebui:YOUR_PASSWORD@pgvector:5432/openwebui`
     - Replace YOUR_PASSWORD with POSTGRES_PASSWORD from secrets.yaml
3. **Save**

**Verify Connection**:
- No error message = success
- Check: Upload a test document and ensure it's processed

### Configure Embedding Model (RAG)

**Recommended models** (research-validated):

1. **Admin Panel** → **Settings** → **Documents**
2. **Embedding**:
   - Engine: **Sentence Transformers** (default)
   - Model: `BAAI/bge-m3`
   - Download Model (first run may take a few minutes)
3. **Reranker**:
   - Enable: **Yes**
   - Model: `BAAI/bge-reranker-v2-m3`
4. **Hybrid Search**:
   - Enable: **Yes** (better retrieval accuracy)
5. **Save**

**What these do**:
- **bge-m3**: Converts text to vector embeddings (semantic search)
- **bge-reranker-v2-m3**: Re-ranks results for better relevance
- **Hybrid Search**: Combines semantic + keyword search

**CKA Learning Point**: While not directly K8s, understanding app-level configuration is part of holistic cluster management.

### Configure Text-to-Speech (Kokoro)

1. **Admin Panel** → **Settings** → **Audio**
2. **Text-to-Speech**:
   - Engine: **OpenAI TTS** (Kokoro is OpenAI-compatible)
   - API Base URL: `http://kokoro:8880`
   - API Key: (leave empty or enter dummy value)
   - Model: `af_bella` (voice name)
3. **Test**: Use TTS in a chat to verify

**Troubleshooting**:
- If TTS fails: Check `kubectl logs -n ai <kokoro-pod>`
- Verify Kokoro service: `kubectl get svc -n ai kokoro`

### Configure Speech-to-Text (Faster-Whisper)

1. **Admin Panel** → **Settings** → **Audio**
2. **Speech-to-Text**:
   - Engine: **OpenAI Whisper** (Faster-Whisper is OpenAI-compatible)
   - API Base URL: `http://faster-whisper:8000`
   - API Key: (leave empty or enter dummy value)
3. **Test**: Use voice input in chat to verify

### Configure Image Generation (gpt-image-1)

**Method: Install Pipe/Function**

1. **Admin Panel** → **Workspace** → **Functions**
2. **Community Functions** → Search: "GPT Image 1"
3. **Install** the GPT-Image-1 function
4. **Configure**:
   - OpenAI API Key: (your key from secrets)
   - Model: `gpt-image-1`
5. **Enable** the function

**Test**:
- In chat, type: "Generate an image of a sunset over mountains"
- Open WebUI calls OpenAI gpt-image-1

**Alternative**: Use DALL-E 3 (also OpenAI):
- No function needed, configure in Settings → Images
- Set model to `dall-e-3`

### Configure OpenAI API

**Already configured via environment variables** (from Deployment YAML):
- `OPENAI_API_KEY`: From secrets
- `OPENAI_API_BASE_URL`: `https://api.openai.com/v1`

**Verify**:
1. **Admin Panel** → **Settings** → **Connections**
2. Should show OpenAI as connected

**Test**:
- Start a chat with model: `gpt-4-turbo` or `gpt-3.5-turbo`
- Send a message, verify response

## Accessing Other Services

### pgAdmin (Database Administration)

pgAdmin is **not exposed via Ingress** (internal use only).

**Access via port-forward**:

```bash
# Forward local port 8081 to pgAdmin port 80
microk8s kubectl port-forward -n ai svc/pgadmin 8081:80

# Open browser: http://localhost:8081
```

**Login**:
- Email: `admin@vx.home` (or value from secrets)
- Password: PGADMIN_DEFAULT_PASSWORD (from secrets)

**pgvector server should be pre-configured** (via ConfigMap):
- **Name**: pgvector (openwebui)
- **Host**: pgvector
- **Port**: 5432
- **Database**: openwebui
- **Username**: openwebui
- **Password**: (prompted on first connection, use POSTGRES_PASSWORD)

**Explore Database**:
- **Servers** → pgvector → Databases → openwebui → Schemas → public → Extensions → vector
- **Tables**: Open WebUI creates tables automatically (documents, embeddings, etc.)

### Redis (Cache/Sessions)

Redis is headless (no UI).

**Access via redis-cli**:

```bash
# Shell into redis pod
microk8s kubectl exec -it -n ai statefulset/redis -- redis-cli

# Example commands:
127.0.0.1:6379> PING
# Output: PONG

127.0.0.1:6379> KEYS *
# Shows all keys (session IDs, cache entries)

127.0.0.1:6379> INFO
# Shows server info, memory usage, etc.

127.0.0.1:6379> exit
```

**Redis is used by Open WebUI for**:
- WebSocket coordination (multi-instance)
- Session caching
- Rate limiting

## Verification Checklist

### Infrastructure

- [ ] All pods Running: `kubectl get pods -n ai`
- [ ] All PVCs Bound: `kubectl get pvc -n ai`
- [ ] Ingress has ADDRESS: `kubectl get ingress -n ai`
- [ ] Services have Endpoints: `kubectl get endpoints -n ai`

### Application

- [ ] Open WebUI accessible at http://ai.vx.home
- [ ] Can create admin account and log in
- [ ] Chat works with OpenAI GPT models
- [ ] Document upload works (RAG with pgvector)
- [ ] Text-to-speech works (Kokoro)
- [ ] Speech-to-text works (Faster-Whisper)
- [ ] Image generation works (gpt-image-1)

### Database

- [ ] pgAdmin accessible via port-forward
- [ ] Can connect to pgvector from pgAdmin
- [ ] Vector extension enabled: `SELECT * FROM pg_extension WHERE extname='vector';`
- [ ] Open WebUI tables exist

### Troubleshooting Commands

```bash
# Check pod logs
kubectl logs -n ai <pod-name>

# Check pod events
kubectl describe pod -n ai <pod-name>

# Check service endpoints
kubectl get endpoints -n ai <service-name>

# Test DNS from a pod
kubectl run -it --rm debug --image=busybox --restart=Never -n ai -- nslookup pgvector

# Test database connection
kubectl exec -it -n ai statefulset/pgvector -- psql -U openwebui -d openwebui -c "SELECT version();"
```

## Common Issues

### Issue: Open WebUI shows "Database connection error"

**Cause**: Open WebUI can't connect to Postgres

**Diagnosis**:
```bash
# Check pgvector pod
kubectl get pods -n ai -l app=pgvector
# Should be Running

# Check DATABASE_URL in openwebui deployment
kubectl get deployment -n ai openwebui -o yaml | grep DATABASE_URL

# Test connection from openwebui pod
kubectl exec -it -n ai <openwebui-pod> -- curl http://pgvector:5432
# Should connect (may show binary data)
```

**Solution**:
- Verify POSTGRES_PASSWORD in secrets matches DATABASE_URL
- Check Service: `kubectl get svc -n ai pgvector`

### Issue: RAG not working (documents don't get embedded)

**Symptoms**: Upload document, but can't search/query it

**Diagnosis**:
```bash
# Check Open WebUI logs for embedding errors
kubectl logs -n ai <openwebui-pod> | grep -i embed

# Check pgvector for documents table
kubectl exec -it -n ai statefulset/pgvector -- psql -U openwebui -d openwebui -c "\dt"
# Should show tables like: documents, document_embeddings, etc.
```

**Solutions**:
1. Verify pgvector extension enabled
2. Check embedding model downloaded (Admin Panel → Documents)
3. Verify vector database connection string in settings

### Issue: TTS/STT not working

**Diagnosis**:
```bash
# Check Kokoro pod
kubectl get pods -n ai -l app=kokoro
kubectl logs -n ai <kokoro-pod>

# Check Faster-Whisper pod
kubectl get pods -n ai -l app=faster-whisper
kubectl logs -n ai <faster-whisper-pod>

# Test service connectivity from openwebui pod
kubectl exec -it -n ai <openwebui-pod> -- curl http://kokoro:8880
kubectl exec -it -n ai <openwebui-pod> -- curl http://faster-whisper:8000
```

**Solutions**:
- Verify API base URLs in Open WebUI settings
- Check services exist: `kubectl get svc -n ai kokoro faster-whisper`
- Verify nodeSelector matched (if pods are Pending due to no matching node)

### Issue: Can't access http://ai.vx.home from other machines

**Diagnosis**:
```bash
# From node, test Ingress
curl http://ai.vx.home
# Should work

# From other machine, test node IP directly
curl http://<node-ip>
# If this fails: firewall issue
```

**Solutions**:
1. Add DNS entry on client machine or DNS server
2. Check firewall: `sudo firewall-cmd --list-all` (should show http service)
3. Verify Ingress controller: `kubectl get pods -n ingress`

## Performance Tuning

### Resource Limits (Future)

Currently no resource limits are set. For production:

```yaml
# Example: Add to openwebui Deployment
resources:
  requests:
    memory: "512Mi"
    cpu: "500m"
  limits:
    memory: "2Gi"
    cpu: "2000m"
```

### Scaling Open WebUI

With Redis enabled, can scale horizontally:

```bash
# Scale to 3 replicas
kubectl scale deployment -n ai openwebui --replicas=3

# Verify
kubectl get pods -n ai -l app=openwebui
```

**Redis handles**:
- Session sharing across replicas
- WebSocket coordination

### Storage Monitoring

```bash
# Check PVC usage
kubectl get pvc -n ai

# Check actual disk usage on node
df -h /var/snap/microk8s/common/default-storage
```

**Set up monitoring** (Phase 2):
- Prometheus alerts for disk usage > 80%
- Grafana dashboard for storage trends

## Security Best Practices

### Network Policies (Future)

Restrict pod-to-pod traffic:

```yaml
# Example: Only allow openwebui to talk to pgvector
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: pgvector-policy
  namespace: ai
spec:
  podSelector:
    matchLabels:
      app: pgvector
  policyTypes:
  - Ingress
  ingress:
  - from:
    - podSelector:
        matchLabels:
          app: openwebui
    ports:
    - protocol: TCP
      port: 5432
```

### TLS for Ingress (Future)

```bash
# Enable cert-manager
microk8s enable cert-manager

# Configure Ingress with TLS
# See docs/50-terraform-future.md
```

### Secrets Management (Future)

Consider external secrets:
- Vault integration
- External Secrets Operator
- Sealed Secrets

## Next Steps

✅ **AI Stack Deployed and Configured!**

**Explore**:
- Upload documents and test RAG
- Try different OpenAI models (gpt-4-turbo, gpt-3.5-turbo)
- Generate images with gpt-image-1
- Use TTS and STT features

**Future Enhancements**:
- [GPU Enablement](40-gpu-notes.md) for TTS/STT
- [Terraform Migration](50-terraform-future.md) for infrastructure automation
- Observability (Prometheus, Grafana)
- Multi-node scaling

**Learning**:
- Practice kubectl troubleshooting
- Experiment with different configurations
- Break and fix things (CKA practice!)

---

**Resources**:
- [Open WebUI Documentation](https://docs.openwebui.com/)
- [pgvector Documentation](https://github.com/pgvector/pgvector)
- [Kubernetes Debugging Guide](https://kubernetes.io/docs/tasks/debug/)
