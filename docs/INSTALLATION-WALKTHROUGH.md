# Complete Installation Walkthrough

> **Step-by-step commands for installing the MicroK8s AI Stack**
>
> This guide assumes you're running commands as root (sudo -i) unless otherwise noted.

---

## Pre-Installation: Start Root Shell

```bash
# Enter root shell (if not already)
sudo -i
```

---

## Step 1: Configure SELinux (CRITICAL - Must be first!)

```bash
# Navigate to project
cd /home/administrator/projects/demo-app-k8s-stack

# Run SELinux configuration script
./scripts/setup/01-selinux-config.sh
```

**When prompted "Set SELinux to Permissive mode? (y/N):"** → Type `y` and press Enter

**Expected output:** "SELinux configuration completed!"

**Verify:**
```bash
getenforce
```
**Should show:** `Permissive`

---

## Step 2: Install snapd

```bash
# Run snapd installation script
./scripts/setup/02-install-snapd.sh
```

**Expected output:** "snapd installation completed successfully!"

**Verify:**
```bash
snap version
```
**Should show:** snap and snapd version numbers

**Activate snap in current shell:**
```bash
export PATH=$PATH:/snap/bin
```

---

## Step 3: Install MicroK8s

```bash
# Run MicroK8s installation script
./scripts/setup/03-install-microk8s.sh
```

**Expected output:** "MicroK8s installation completed!"

**This will:**
- Install MicroK8s snap
- Add user 'administrator' to microk8s group
- Wait for MicroK8s to be ready

**Verify:**
```bash
microk8s status
```
**Should show:** "microk8s is running"

**Check Kubernetes version:**
```bash
microk8s kubectl version --short
```
**Should show:** Server Version: v1.35.x

**Check node:**
```bash
microk8s kubectl get nodes
```
**Should show:** One node in "Ready" status

---

## Step 4: Enable MicroK8s Addons

```bash
# Run addon enablement script
./scripts/setup/05-enable-addons.sh
```

**Expected output:** "Addon enablement completed!"

**This enables:**
- dns (CoreDNS)
- ingress (NGINX)
- hostpath-storage (PV provisioner)
- helm3 (Helm package manager)
- cert-manager (TLS certificates)

**Verify DNS:**
```bash
microk8s kubectl get pods -n kube-system -l k8s-app=kube-dns
```
**Should show:** coredns pod in "Running" status

**Verify Ingress:**
```bash
microk8s kubectl get pods -n ingress
```
**Should show:** nginx-ingress-controller pod in "Running" status

**Verify Storage:**
```bash
microk8s kubectl get storageclass
```
**Should show:** microk8s-hostpath with (default)

**Verify Helm:**
```bash
microk8s helm3 version --short
```
**Should show:** Helm version

**Verify cert-manager:**
```bash
microk8s kubectl get pods -n cert-manager
```
**Should show:** cert-manager, cert-manager-webhook, cert-manager-cainjector pods in "Running" status

---

## Step 5: Configure cert-manager CA (TLS)

```bash
# Run cert-manager CA configuration script
./scripts/setup/06-configure-cert-manager.sh
```

**Expected output:** "cert-manager CA configuration completed!"

**This creates:**
- `selfsigned-issuer` - Bootstrap ClusterIssuer
- `vx-home-ca` - CA Certificate (10-year validity)
- `vx-home-ca-issuer` - ClusterIssuer for signing TLS certificates

**Verify ClusterIssuers:**
```bash
microk8s kubectl get clusterissuers
```
**Should show:** Both `selfsigned-issuer` and `vx-home-ca-issuer` with READY: True

**Verify CA Certificate:**
```bash
microk8s kubectl get certificate -n cert-manager
```
**Should show:** `vx-home-ca` with READY: True

---

## Step 6: Configure Firewall

```bash
# Run firewall configuration script
./scripts/setup/07-configure-firewall.sh
```

**If prompted about starting firewalld:** → Type `y` if you want it running

**Expected output:** "Firewall configuration completed!"

**Verify:**
```bash
firewall-cmd --list-all
```
**Should show:**
- services: http https
- ports: 16443/tcp 10250/tcp 10255/tcp 25000/tcp
- masquerade: yes

---

## Step 7: Label Node for TTS/STT

```bash
# Run node labeling script
./scripts/setup/08-label-node.sh
```

**Expected output:** "Node labeling completed!"

**Verify:**
```bash
microk8s kubectl get nodes --show-labels | grep gpu
```
**Should show:** `gpu=true` in the labels

---

## Step 8: Install Portainer with TLS (Optional but Recommended)

**Exit root shell and run as regular user:**
```bash
# Exit root
exit
```

**Now as regular user (administrator):**
```bash
cd /home/administrator/projects/demo-app-k8s-stack

# Install Portainer
./scripts/admin/portainer.sh install
```

**Expected output:** "Portainer installed with TLS! Access at: https://ptnr.adm.vx.home"

**Note:** The TLS certificate is signed by your homelab CA (vx-home-ca-issuer). To avoid browser warnings, trust the CA certificate - see [cert-manager documentation](15-cert-manager.md#trusting-the-ca-certificate).

**Add DNS entry for Portainer:**
```bash
# Get node IP
NODE_IP=$(hostname -I | awk '{print $1}')
echo $NODE_IP

# Add to /etc/hosts (need root)
echo "$NODE_IP ptnr.adm.vx.home" | sudo tee -a /etc/hosts
```

**Verify Portainer is running:**
```bash
microk8s kubectl get pods -n portainer
```
**Should show:** portainer pod in "Running" status

**Check Portainer Ingress:**
```bash
microk8s kubectl get ingress -n portainer
```
**Should show:** ptnr.adm.vx.home with an ADDRESS

---

## Step 9: Create Secrets for AI Stack

**Create secrets file from template:**
```bash
cd /home/administrator/projects/demo-app-k8s-stack

# Copy example to real secrets file
cp k8s/clusters/vx-home/apps/ai-stack/secrets.example.yaml \
   k8s/clusters/vx-home/apps/ai-stack/secrets.yaml
```

**Generate strong passwords:**
```bash
# Generate Postgres password
openssl rand -base64 24
# Copy this output

# Generate pgAdmin password
openssl rand -base64 24
# Copy this output
```

**Edit secrets file:**
```bash
vim k8s/clusters/vx-home/apps/ai-stack/secrets.yaml
```

**Or use nano if you prefer:**
```bash
nano k8s/clusters/vx-home/apps/ai-stack/secrets.yaml
```

**Update these lines:**
```yaml
POSTGRES_PASSWORD: "PASTE_FIRST_GENERATED_PASSWORD_HERE"
DATABASE_URL: "postgresql://openwebui:PASTE_SAME_PASSWORD_HERE@pgvector:5432/openwebui"
PGADMIN_DEFAULT_PASSWORD: "PASTE_SECOND_GENERATED_PASSWORD_HERE"
OPENAI_API_KEY: "sk-YOUR_REAL_OPENAI_KEY_FROM_PLATFORM"
```

**Save and exit:**
- **vim**: Press `Esc`, type `:wq`, press Enter
- **nano**: Press `Ctrl+X`, type `y`, press Enter

**Verify file exists and is not tracked by git:**
```bash
ls -la k8s/clusters/vx-home/apps/ai-stack/secrets.yaml
git status
```
**Should show:** secrets.yaml exists but is NOT in untracked files (gitignored)

---

## Step 10: Deploy AI Stack

```bash
# Apply all Kubernetes manifests
./scripts/admin/deploy.sh apply
```

**Expected output:** Various "created" or "configured" messages

**Watch deployment progress:**
```bash
# Watch pods come up (Ctrl+C to exit when all Running)
microk8s kubectl get pods -n ai -w
```

**Wait for all pods to reach "Running" status (2-5 minutes)**

**Order they'll start:**
1. PVCs bind immediately
2. pgvector-0 starts
3. redis-0 starts
4. Once databases ready: openwebui, pgadmin, kokoro, faster-whisper start

**Check final status:**
```bash
./scripts/admin/status.sh
```

**Should show:**
- All pods: 1/1 Running
- All PVCs: Bound
- Services: All with ClusterIP
- Ingress: ADDRESS populated

---

## Step 11: Initialize pgvector Extension

```bash
# Run pgvector initialization
./scripts/admin/init-pgvector.sh
```

**You'll see a psql prompt, then output:** `CREATE EXTENSION`

**Verify:**
```bash
microk8s kubectl exec -it -n ai statefulset/pgvector -- psql -U openwebui -d openwebui -c "\dx"
```

**Should show:** `vector` in the extensions list

---

## Step 12: Configure DNS for AI Stack

```bash
# Get node IP
NODE_IP=$(hostname -I | awk '{print $1}')
echo "Node IP: $NODE_IP"

# Add DNS entries (need root)
echo "$NODE_IP ai.adm.vx.home" | sudo tee -a /etc/hosts
echo "$NODE_IP control.adm.vx.home" | sudo tee -a /etc/hosts
```

**Verify DNS entries:**
```bash
cat /etc/hosts | grep vx.home
```

**Should show:**
```
<IP> ptnr.adm.vx.home
<IP> ai.adm.vx.home
<IP> control.adm.vx.home
```

---

## Step 13: Test Services

**Test Open WebUI (HTTPS):**
```bash
curl -Ik https://ai.adm.vx.home
```
**Should show:** HTTP 200 or 302 (redirect). Certificate warning if CA not trusted yet.

**Test Control Portal (HTTPS):**
```bash
curl -Ik https://control.adm.vx.home
```
**Should show:** HTTP 200

**Test pgAdmin (HTTPS):**
```bash
curl -Ik https://control.adm.vx.home/pgadmin/
```
**Should show:** HTTP 200 or 302

**Test Portainer (HTTPS):**
```bash
curl -Ik https://ptnr.adm.vx.home
```
**Should show:** HTTP 200

**Verify TLS certificates were issued:**
```bash
microk8s kubectl get certificates -A
```
**Should show:** All certificates with READY: True

---

## Step 14: Access Open WebUI in Browser

**Open browser and go to:** `https://ai.adm.vx.home`

**First-time setup:**
1. Create admin account:
   - Email: your email
   - Password: your password (strong, 12+ characters)
2. Log in

---

## Step 15: Configure Open WebUI

**In Open WebUI, click profile icon → Admin Panel → Settings**

### Configure Vector Database (RAG):

1. Go to **Settings** → **Documents**
2. **Vector Database**: Select "PGVector"
3. **Connection String**:
   ```
   postgresql://openwebui:YOUR_POSTGRES_PASSWORD@pgvector:5432/openwebui
   ```
   (Use the password from your secrets.yaml)
4. **Save**

### Configure Embedding Model:

Still in **Documents** section:
1. **Embedding Engine**: Sentence Transformers (should be default)
2. **Embedding Model**: Enter `BAAI/bge-m3`
3. Click to download model (first time will take a moment)
4. **Reranker**: Enable and select `BAAI/bge-reranker-v2-m3`
5. **Hybrid Search**: Enable
6. **Save**

### Configure Text-to-Speech:

1. Go to **Settings** → **Audio**
2. **Text-to-Speech**:
   - Engine: OpenAI TTS
   - API Base URL: `http://kokoro:8880`
   - API Key: (leave empty or enter dummy)
   - Model: `af_bella`
3. **Save**

### Configure Speech-to-Text:

Still in **Audio** section:
1. **Speech-to-Text**:
   - Engine: OpenAI Whisper
   - API Base URL: `http://faster-whisper:8000`
   - API Key: (leave empty or enter dummy)
2. **Save**

### Configure Image Generation:

1. Go to **Workspace** → **Functions**
2. Search Community Functions for: "GPT Image 1"
3. Install the GPT-Image-1 function
4. Configure with your OpenAI API key
5. Enable the function

---

## Step 16: Access pgAdmin

**Open browser and go to:** `https://control.adm.vx.home/pgadmin`

**Login:**
- Email: `admin@vx.home`
- Password: YOUR_PGADMIN_PASSWORD (from secrets.yaml)

**Connect to pgvector:**
- Server should be pre-configured as "pgvector (openwebui)"
- Click on it
- When prompted for password: Enter YOUR_POSTGRES_PASSWORD (from secrets.yaml)

**Explore:**
- Servers → pgvector → Databases → openwebui → Schemas → public → Tables
- You'll see Open WebUI tables (created automatically)

---

## Step 17: Access Portainer

**Open browser and go to:** `https://ptnr.adm.vx.home`

**Note:** If you see a certificate warning, you can trust the CA - see [cert-manager documentation](15-cert-manager.md#trusting-the-ca-certificate).

**First-time setup:**
1. Create admin user:
   - Username: `admin`
   - Password: (strong, 12+ characters)
2. Select environment type: Kubernetes
3. Portainer auto-detects local cluster
4. You're in!

**Explore:**
- Home → local (environment)
- Namespace dropdown → Select "ai"
- Applications → See all your deployments
- Click on openwebui → View pods, logs, console

---

## Verification Checklist

**Run this to verify everything:**
```bash
# Check all pods running
microk8s kubectl get pods -n ai

# Expected output: All pods showing 1/1 Running
# - pgvector-0
# - redis-0
# - openwebui-xxxxx
# - pgadmin-xxxxx
# - kokoro-xxxxx
# - faster-whisper-xxxxx
# - control-portal-nginx-xxxxx

# Check services
microk8s kubectl get svc -n ai

# Check ingress
microk8s kubectl get ingress -n ai

# Check persistent volumes
microk8s kubectl get pvc,pv -n ai
```

**All should be healthy!**

---

## Useful Commands Reference

```bash
# Quick status check
./scripts/admin/status.sh

# View logs for a specific app
./scripts/admin/logs.sh openwebui
./scripts/admin/logs.sh pgvector
./scripts/admin/logs.sh kokoro

# Restart an app
./scripts/admin/restart.sh openwebui

# Shell into a pod
microk8s kubectl exec -it -n ai <pod-name> -- /bin/bash

# Port-forward a service (useful for testing)
microk8s kubectl port-forward -n ai svc/pgadmin 8081:80
# Then access: http://localhost:8081

# Watch pod status
microk8s kubectl get pods -n ai -w

# Check pod events (for troubleshooting)
microk8s kubectl describe pod -n ai <pod-name>

# Clean up failed pods
./scripts/admin/clean.sh
```

---

## Common Aliases (Optional but Helpful)

Add to `~/.bashrc`:

```bash
# MicroK8s kubectl alias
alias k='microk8s kubectl'

# Quick pod list
alias kgp='microk8s kubectl get pods'

# Quick logs
alias kl='microk8s kubectl logs'

# Quick describe
alias kd='microk8s kubectl describe'
```

Apply aliases:
```bash
source ~/.bashrc
```

Then you can use:
```bash
k get pods -n ai
kgp -n ai
kl -n ai openwebui-xxxxx
kd pod -n ai openwebui-xxxxx
```

---

## Summary of What You Now Have

✅ **MicroK8s** - Kubernetes 1.35 cluster
✅ **cert-manager** - TLS certificates via vx-home-ca-issuer
✅ **Portainer** - Web UI at https://ptnr.adm.vx.home
✅ **Open WebUI** - AI interface at https://ai.adm.vx.home
✅ **pgAdmin** - Database UI at https://control.adm.vx.home/pgadmin
✅ **Postgres + pgvector** - Vector database for RAG
✅ **Redis** - Caching and session management
✅ **Kokoro TTS** - Text-to-speech service
✅ **Faster-Whisper STT** - Speech-to-text service

**All running CPU-only, ready for GPU enablement later (Phase 2)**

---

## Troubleshooting

**If you encounter issues:**

1. **Check pod status:**
   ```bash
   microk8s kubectl get pods -n ai
   ```

2. **Check pod logs:**
   ```bash
   microk8s kubectl logs -n ai <pod-name>
   ```

3. **Check pod events:**
   ```bash
   microk8s kubectl describe pod -n ai <pod-name>
   ```

4. **Common issues:** See [90-troubleshooting.md](90-troubleshooting.md)

5. **MicroK8s not starting:**
   ```bash
   getenforce  # Should be Permissive
   microk8s inspect  # Generates detailed report
   ```

6. **Pods stuck in Pending:**
   ```bash
   microk8s kubectl describe pod -n ai <pod-name>
   # Look at Events section for reasons
   ```

7. **Ingress not working:**
   ```bash
   microk8s kubectl get pods -n ingress
   # Ingress controller should be Running
   ```

---

## Next Steps After Installation

1. **Test RAG**: Upload a document to Open WebUI and ask questions about it
2. **Test TTS**: Use voice output in a chat
3. **Test STT**: Use voice input in a chat
4. **Test Image Generation**: Ask it to generate an image
5. **Explore Portainer**: Browse your cluster resources
6. **Practice kubectl**: Get comfortable with command-line management

---

**Ready to start? Begin with Step 1: SELinux configuration!** 🚀
