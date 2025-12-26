# Portainer CE Installation and Usage

## Overview

**Portainer Community Edition (CE)** is a web-based Kubernetes management UI that provides:
- Visual cluster management (no kubectl needed for basic operations)
- Pod logs and shell access via web interface
- Resource visualization (deployments, services, PVCs)
- Application deployment wizard

**Target URL**: `https://ptnr.adm.vx.home`

## Installation Methods

### Method 1: Helm (Recommended)

This is the official Portainer installation method.

**Step 1: Verify prerequisites**

```bash
# Ensure helm3 addon is enabled
microk8s status | grep helm3
# Output: helm3: enabled

# Ensure default StorageClass exists
microk8s kubectl get sc
# Output: microk8s-hostpath (default)
```

**Step 2: Add Portainer Helm repository**

```bash
# Add repo
microk8s helm3 repo add portainer https://portainer.github.io/k8s/

# Update repos
microk8s helm3 repo update
```

**Step 3: Install Portainer with Ingress**

```bash
# Get your Ingress class name (usually 'nginx' or 'public')
microk8s kubectl get ingressclass
# Note the NAME column

# Install Portainer
microk8s helm3 upgrade --install --create-namespace -n portainer \
  portainer portainer/portainer \
  --set service.type=ClusterIP \
  --set tls.force=true \
  --set image.tag=lts \
  --set ingress.enabled=true \
  --set ingress.ingressClassName=public \
  --set ingress.annotations."nginx\.ingress\.kubernetes\.io/backend-protocol"=HTTPS \
  --set ingress.hosts[0].host=ptnr.adm.vx.home \
  --set ingress.hosts[0].paths[0].path="/"
```

**Explanation of flags**:
- `--create-namespace`: Creates `portainer` namespace if it doesn't exist
- `service.type=ClusterIP`: Don't expose via NodePort (use Ingress instead)
- `tls.force=true`: Portainer serves HTTPS internally
- `ingress.enabled=true`: Create Ingress resource
- `ingress.ingressClassName=public`: Match your Ingress controller
- `backend-protocol=HTTPS`: Tell Nginx to use HTTPS to backend
- `ingress.hosts[0]`: Your custom hostname

**Step 4: Wait for deployment**

```bash
# Watch pods come up
microk8s kubectl get pods -n portainer -w
# Wait for: portainer-XXX   1/1   Running

# Check Ingress
microk8s kubectl get ingress -n portainer
# Note the ADDRESS column (should show IP)
```

### Method 2: MicroK8s Community Addon (Alternative)

MicroK8s provides a Portainer addon, but it's less configurable.

```bash
# Enable community addon repository
microk8s enable community

# Install Portainer
microk8s enable portainer
```

**Note**: This uses default settings (no Ingress customization). Use Method 1 for production-like setup.

### Method 3: Admin Script (Convenience)

The repository includes an admin script:

```bash
# Uses Helm method with pre-configured settings
./scripts/admin/portainer.sh install
```

## Post-Installation Configuration

### 1. Add DNS Entry

Add to your `/etc/hosts` or DNS server:

```bash
# Get your node IP
NODE_IP=$(hostname -I | awk '{print $1}')
echo "$NODE_IP ptnr.adm.vx.home" | sudo tee -a /etc/hosts
```

### 2. Access Portainer

Open in browser: `https://ptnr.adm.vx.home`

**First-Time Setup**:
1. You'll see a certificate warning (self-signed cert) – accept it
2. Create admin user:
   - Username: `admin`
   - Password: (choose strong password, minimum 12 characters)
3. Select environment type: **Kubernetes**
4. Portainer auto-detects the local cluster

### 3. Initial Configuration

**After login**:

1. **Home Dashboard**: Shows cluster overview
2. **Environment**: Select "local" (the MicroK8s cluster)
3. **Namespace**: Select `ai` to see your AI stack

**Useful Portainer Features**:

| Feature | Purpose | CKA Learning Value |
|---------|---------|-------------------|
| **Applications** | View Deployments, StatefulSets | Visual representation of `kubectl get deploy,sts` |
| **Services** | View Services and endpoints | Understand Service → Pod mapping |
| **Volumes** | View PVCs and PVs | Storage troubleshooting |
| **Logs** | View pod logs in browser | Alternative to `kubectl logs` |
| **Console** | Shell into pods | Alternative to `kubectl exec -it` |

## Using Portainer

### View AI Stack Resources

1. **Home** → **local** (environment)
2. **Namespace dropdown** → Select **ai**
3. **Applications** → See Open WebUI, pgvector, redis, etc.

### View Pod Logs

1. **Applications** → Click application (e.g., **openwebui**)
2. Click pod name
3. **Logs** tab → View logs in real-time

**CKA Equivalent**:
```bash
microk8s kubectl logs -n ai <pod-name> -f
```

### Shell into Pod

1. **Applications** → Click application
2. Click pod name
3. **Console** tab → Click **Connect**
4. Shell opens in browser

**CKA Equivalent**:
```bash
microk8s kubectl exec -it -n ai <pod-name> -- /bin/bash
```

### View Persistent Volumes

1. **Volumes** (left menu)
2. See all PVCs and their status
3. Click PVC → See which pod is using it

**CKA Equivalent**:
```bash
microk8s kubectl get pvc -n ai
microk8s kubectl describe pvc <pvc-name> -n ai
```

## Troubleshooting

### Issue: Can't access https://ptnr.adm.vx.home

**Diagnosis**:

```bash
# Check Portainer pod
microk8s kubectl get pods -n portainer
# Should be Running

# Check Ingress
microk8s kubectl get ingress -n portainer
# Should have ADDRESS set

# Check Ingress controller
microk8s kubectl get pods -n ingress
# Should be Running

# Test from node itself
curl -k https://ptnr.adm.vx.home
# Should get HTML response (Portainer login page)
```

**Common Issues**:

1. **DNS not configured**: Add to /etc/hosts
2. **Ingress class mismatch**: Check `ingressClassName` in Ingress resource
3. **Firewall blocking**: Ensure port 443 open (see [10-microk8s-install.md](10-microk8s-install.md#step-4-configure-firewall))

### Issue: Certificate Error

**If you've configured cert-manager:** The certificate should be trusted if you've imported the CA. See [cert-manager documentation](15-cert-manager.md#trusting-the-ca-certificate).

**Verify certificate is issued:**
```bash
kubectl get certificate -n portainer
# Should show: portainer-tls   True   portainer-tls   Xs
```

**If certificate is not issued:**
```bash
# Check cert-manager logs
kubectl logs -n cert-manager -l app=cert-manager

# Check ClusterIssuer is ready
kubectl get clusterissuers
```

**If you haven't configured cert-manager yet:** Portainer uses a self-signed certificate by default. Either accept the browser warning or configure cert-manager - see [cert-manager documentation](15-cert-manager.md).

### Issue: "Invalid credentials" on first login

**Cause**: You may have partially created an admin user.

**Solution**:
```bash
# Delete Portainer PVC to reset
microk8s kubectl delete pvc -n portainer portainer

# Restart Portainer pod
microk8s kubectl rollout restart deployment portainer -n portainer
```

### Issue: Portainer can't connect to Kubernetes API

**Cause**: RBAC permissions or network issue.

**Diagnosis**:
```bash
# Check Portainer service account
microk8s kubectl get sa -n portainer

# Check ClusterRoleBinding
microk8s kubectl get clusterrolebinding | grep portainer

# Check Portainer logs
microk8s kubectl logs -n portainer <portainer-pod-name>
```

**Solution**: Portainer Helm chart should create these automatically. If missing:
```bash
# Re-install Portainer
microk8s helm3 uninstall portainer -n portainer
./scripts/admin/portainer.sh install
```

## CKA Learning Points

### Helm Charts

**What is Helm?**
- Package manager for Kubernetes
- Charts = pre-configured YAML templates
- Values = customization parameters

**Helm Workflow**:
```bash
# Add repository
microk8s helm3 repo add <name> <url>

# Search charts
microk8s helm3 search repo portainer

# Install chart
microk8s helm3 install <release-name> <chart>

# List installed releases
microk8s helm3 list -A

# Uninstall
microk8s helm3 uninstall <release-name> -n <namespace>
```

**CKA Exam**: While CKA focuses on kubectl, understanding Helm is valuable for real-world Kubernetes.

### Ingress HTTPS Backend

**Normal Ingress** (HTTP backend):
```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
spec:
  rules:
  - host: app.example.com
    http:  # Ingress talks HTTP to backend
      paths:
      - backend:
          service:
            name: app
            port:
              number: 80
```

**Portainer's requirement** (HTTPS backend):
```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  annotations:
    nginx.ingress.kubernetes.io/backend-protocol: "HTTPS"  # Tell Nginx to use HTTPS
spec:
  rules:
  - host: ptnr.adm.vx.home
    http:
      paths:
      - backend:
          service:
            name: portainer
            port:
              number: 9443  # Portainer HTTPS port
```

**Why the annotation?**
- Portainer serves HTTPS on port 9443 (not HTTP on 80)
- Nginx Ingress Controller needs to know to use HTTPS
- Without annotation: Nginx sends HTTP, Portainer rejects

**CKA Learning**: Ingress annotations are controller-specific. Different controllers (Nginx, Traefik, HAProxy) use different annotations.

## Security Considerations

### Default Security Posture

Portainer has:
- ✅ Authentication required (admin user)
- ✅ RBAC integration (respects Kubernetes permissions)
- ✅ HTTPS for web UI
- ⚠️ Self-signed certificate (browser warnings)

### Hardening (Production)

1. **Enable TLS with real certificates**:
   ```bash
   microk8s enable cert-manager
   # Configure Ingress with cert-manager annotations
   ```

2. **Restrict access** (firewall or Ingress auth):
   ```yaml
   # Ingress basic auth
   annotations:
     nginx.ingress.kubernetes.io/auth-type: basic
     nginx.ingress.kubernetes.io/auth-secret: basic-auth
   ```

3. **Limit Portainer permissions** (least-privilege RBAC):
   - By default, Portainer has cluster-admin
   - For production, create custom Role with minimal permissions

## Alternative: kubectl Only (CKA Exam)

**Portainer is convenient, but the CKA exam requires kubectl proficiency.**

**Common Portainer tasks via kubectl**:

| Portainer Action | kubectl Command |
|------------------|-----------------|
| View deployments | `kubectl get deploy -n ai` |
| View pod logs | `kubectl logs -n ai <pod>` |
| Shell into pod | `kubectl exec -it -n ai <pod> -- bash` |
| View services | `kubectl get svc -n ai` |
| View PVCs | `kubectl get pvc -n ai` |
| Delete pod | `kubectl delete pod -n ai <pod>` |
| Scale deployment | `kubectl scale deploy -n ai <deploy> --replicas=3` |

**Practice both**: Use Portainer for convenience, but ensure you can do everything with kubectl for exam readiness.

## Uninstallation

If you need to remove Portainer:

```bash
# Via Helm
microk8s helm3 uninstall portainer -n portainer

# Delete namespace (removes all resources)
microk8s kubectl delete namespace portainer

# Remove Helm repo (optional)
microk8s helm3 repo remove portainer
```

## Next Steps

✅ **Portainer Installed!**

Proceed to:
- **[AI Stack Deployment](30-ai-stack-openwebui.md)**: Deploy Open WebUI and supporting services

**Portainer Tips**:
- Explore the interface – it's a great visual complement to kubectl
- Use it for quick troubleshooting (logs, console)
- But always learn the kubectl equivalent (CKA exam!)

---

**Resources**:
- [Portainer Documentation](https://docs.portainer.io/)
- [Portainer Kubernetes Install Guide](https://docs.portainer.io/start/install-ce/server/kubernetes/baremetal)
- [Helm Documentation](https://helm.sh/docs/)
