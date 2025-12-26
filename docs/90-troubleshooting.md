# Troubleshooting Guide

## Overview

This guide covers common issues you may encounter with the MicroK8s AI stack, organized by component. Each issue includes:
- **Symptoms**: What you observe
- **Diagnosis**: How to investigate
- **Solution**: How to fix it
- **Prevention**: How to avoid it

**CKA Exam Note**: Troubleshooting is 30% of the CKA exam. Practice these workflows!

## General Troubleshooting Workflow

### The Kubernetes Debugging Hierarchy

```
1. Check Pod Status
   ├─→ Pending? Check scheduling (resources, nodeSelector, PVCs)
   ├─→ CrashLoopBackOff? Check logs, liveness probes
   ├─→ ImagePullBackOff? Check image name, registry auth
   └─→ Running but not working? Check logs, service endpoints

2. Check Service Connectivity
   ├─→ No endpoints? Pods not matching selector
   ├─→ Wrong port? Check targetPort vs port
   └─→ DNS not resolving? Check CoreDNS

3. Check Ingress
   ├─→ No ADDRESS? Ingress controller not running
   ├─→ 404? Wrong path or backend service
   ├─→ 502? Backend pod not ready
   └─→ 503? No backend endpoints

4. Check Persistent Volumes
   ├─→ PVC pending? No matching PV or StorageClass
   ├─→ PVC bound but pod pending? Access mode mismatch
   └─→ Pod running but no data? Wrong mount path

5. Check Logs and Events
   ├─→ Pod logs: kubectl logs
   ├─→ Pod events: kubectl describe pod
   ├─→ Node events: kubectl describe node
   └─→ System logs: journalctl
```

### Essential kubectl Commands

```bash
# Pod troubleshooting
kubectl get pods -n ai                          # Status overview
kubectl describe pod <pod-name> -n ai           # Detailed info + events
kubectl logs <pod-name> -n ai                   # Current logs
kubectl logs <pod-name> -n ai --previous        # Logs from previous crash
kubectl exec -it <pod-name> -n ai -- /bin/bash  # Shell into pod

# Service troubleshooting
kubectl get svc -n ai                           # Service list
kubectl get endpoints -n ai                     # Service → Pod mapping
kubectl describe svc <svc-name> -n ai           # Service details

# Networking
kubectl run -it --rm debug --image=busybox --restart=Never -- sh  # Debug pod
  # From inside: nslookup <service>, wget <service>, ping <service>

# Resources
kubectl get pvc -n ai                           # PersistentVolumeClaims
kubectl get pv                                  # PersistentVolumes (cluster-wide)
kubectl describe pvc <pvc-name> -n ai           # PVC details

# Events (recent cluster events)
kubectl get events -n ai --sort-by='.lastTimestamp'
```

## MicroK8s Issues

### Issue: MicroK8s won't start

**Symptoms**:
```bash
microk8s status
# Output: MicroK8s is not running
```

**Diagnosis**:
```bash
# Check systemd service
sudo systemctl status snap.microk8s.daemon-kubelite.service

# Check logs
sudo journalctl -u snap.microk8s.daemon-kubelite.service -n 100 --no-pager

# Check MicroK8s inspection report
microk8s inspect
# Generates: /var/snap/microk8s/common/inspection-report-XXXXXX.tar.gz
```

**Common Causes & Solutions**:

1. **SELinux in enforcing mode**:
   ```bash
   getenforce
   # If Enforcing: Run ./scripts/setup/01-selinux-config.sh
   ```

2. **Port conflicts** (another K8s or Docker running):
   ```bash
   sudo netstat -tulnp | grep -E '16443|10250'
   # If in use: Stop conflicting service or change MicroK8s ports
   ```

3. **Disk space full**:
   ```bash
   df -h /var/snap/microk8s
   # If >90%: Clean up old images, logs
   microk8s kubectl delete pod --field-selector=status.phase=Failed -A
   ```

4. **Snap daemon not running**:
   ```bash
   sudo systemctl status snapd.socket
   sudo systemctl restart snapd.socket
   sudo systemctl restart snap.microk8s.daemon-kubelite.service
   ```

### Issue: MicroK8s addons won't enable

**Symptoms**:
```bash
microk8s enable dns
# Output: Error or hangs
```

**Diagnosis**:
```bash
# Check addon status
microk8s status

# Check for errors in daemon logs
sudo journalctl -u snap.microk8s.daemon-kubelite.service -f
```

**Solutions**:

1. **Network issues** (can't download addon resources):
   ```bash
   # Test internet connectivity
   curl -I https://github.com

   # Check firewall isn't blocking outbound
   sudo firewall-cmd --list-all
   ```

2. **Corrupted addon**:
   ```bash
   # Disable and re-enable
   microk8s disable <addon>
   microk8s enable <addon>
   ```

3. **Insufficient resources**:
   ```bash
   # Check node resources
   kubectl describe nodes
   # Look for: Allocatable vs Requested

   # Check system resources
   free -h
   df -h
   ```

## Pod Issues

### Issue: Pods stuck in Pending

**Symptoms**:
```bash
kubectl get pods -n ai
# NAME          READY   STATUS    RESTARTS   AGE
# pgvector-0    0/1     Pending   0          5m
```

**Diagnosis**:
```bash
# Check pod events
kubectl describe pod pgvector-0 -n ai
# Look at Events section (bottom)
```

**Common Causes & Solutions**:

1. **No matching node** (nodeSelector/nodeAffinity):
   ```
   Events: 0/1 nodes available: 1 node(s) didn't match node selector
   ```
   **Solution**:
   ```bash
   # Check pod nodeSelector
   kubectl get pod pgvector-0 -n ai -o yaml | grep -A5 nodeSelector

   # Check node labels
   kubectl get nodes --show-labels

   # Fix: Add label to node or remove nodeSelector
   kubectl label node <node-name> ai-stt-tts=true
   ```

2. **Insufficient resources** (CPU/memory/GPU):
   ```
   Events: 0/1 nodes available: 1 Insufficient cpu/memory/nvidia.com/gpu
   ```
   **Solution**:
   ```bash
   # Check node capacity
   kubectl describe nodes | grep -A10 Allocatable

   # Check pod requests
   kubectl get pod pgvector-0 -n ai -o yaml | grep -A10 resources

   # Fix: Reduce requests or add more nodes
   ```

3. **PVC not bound**:
   ```
   Events: pod has unbound immediate PersistentVolumeClaims
   ```
   **Solution**:
   ```bash
   # Check PVC status
   kubectl get pvc -n ai
   # Look for STATUS = Pending

   # Check PVC events
   kubectl describe pvc <pvc-name> -n ai

   # Common fix: Ensure hostpath-storage addon enabled
   microk8s enable hostpath-storage
   ```

4. **Image pull failure**:
   ```
   Events: Failed to pull image "ghcr.io/open-webui/open-webui:v0.6.42"
   ```
   **Solution**:
   ```bash
   # Check image name spelling
   # Check internet connectivity
   # Check registry authentication (if private)

   # Manual pull test
   microk8s ctr image pull ghcr.io/open-webui/open-webui:v0.6.42
   ```

### Issue: Pods in CrashLoopBackOff

**Symptoms**:
```bash
kubectl get pods -n ai
# NAME              READY   STATUS             RESTARTS   AGE
# openwebui-XXX     0/1     CrashLoopBackOff   5          10m
```

**Diagnosis**:
```bash
# Check current logs
kubectl logs -n ai openwebui-XXX

# Check previous crash logs
kubectl logs -n ai openwebui-XXX --previous

# Check pod events
kubectl describe pod -n ai openwebui-XXX
```

**Common Causes & Solutions**:

1. **Configuration error** (wrong env var, missing secret):
   ```
   Logs: Error: DATABASE_URL is required
   ```
   **Solution**:
   ```bash
   # Check secret exists
   kubectl get secret -n ai ai-secrets

   # Check deployment env vars
   kubectl get deployment -n ai openwebui -o yaml | grep -A20 env

   # Fix secret or deployment
   ```

2. **Database connection failed**:
   ```
   Logs: could not connect to server: Connection refused
   ```
   **Solution**:
   ```bash
   # Check database pod running
   kubectl get pods -n ai -l app=pgvector

   # Test connection from openwebui pod
   kubectl exec -it -n ai openwebui-XXX -- curl http://pgvector:5432
   # Should connect (may show binary data)

   # Check DATABASE_URL format
   # Format: postgresql://user:password@host:port/database
   ```

3. **Permission issues** (file system, user privileges):
   ```
   Logs: Permission denied: /app/backend/data
   ```
   **Solution**:
   ```bash
   # Check volume mount
   kubectl get pod -n ai openwebui-XXX -o yaml | grep -A10 volumeMounts

   # Check PVC ownership
   kubectl exec -it -n ai openwebui-XXX -- ls -ld /app/backend/data
   ```

4. **Liveness/readiness probe failing**:
   ```
   Events: Liveness probe failed: HTTP probe failed with statuscode: 500
   ```
   **Solution**:
   ```bash
   # Check probe configuration
   kubectl get deployment -n ai openwebui -o yaml | grep -A10 livenessProbe

   # Test probe endpoint manually
   kubectl exec -it -n ai openwebui-XXX -- curl localhost:8080/health

   # Fix: Adjust probe settings or fix app health endpoint
   ```

### Issue: ImagePullBackOff

**Symptoms**:
```bash
kubectl get pods -n ai
# NAME          READY   STATUS             RESTARTS   AGE
# kokoro-XXX    0/1     ImagePullBackOff   0          2m
```

**Diagnosis**:
```bash
kubectl describe pod -n ai kokoro-XXX
# Events: Failed to pull image "ghcr.io/remsky/kokoro-fastapi-cpu:v0.2.4"
#         Error: manifest unknown
```

**Causes & Solutions**:

1. **Image name typo**:
   ```bash
   # Verify image exists
   # Check: https://ghcr.io/remsky/kokoro-fastapi-cpu
   # Or: docker pull ghcr.io/remsky/kokoro-fastapi-cpu:v0.2.4
   ```

2. **Wrong tag**:
   ```bash
   # List available tags
   # GitHub: https://github.com/remsky/Kokoro-FastAPI/pkgs/container/kokoro-fastapi-cpu
   ```

3. **Private registry (needs auth)**:
   ```bash
   # Create image pull secret
   kubectl create secret docker-registry ghcr-secret \
     --docker-server=ghcr.io \
     --docker-username=<github-username> \
     --docker-password=<github-pat> \
     -n ai

   # Add to Deployment
   # spec.template.spec.imagePullSecrets:
   #   - name: ghcr-secret
   ```

4. **Network issues**:
   ```bash
   # Test from node
   curl -I https://ghcr.io

   # Check firewall allows outbound HTTPS
   sudo firewall-cmd --list-all
   ```

## Service/Networking Issues

### Issue: Service has no endpoints

**Symptoms**:
```bash
kubectl get endpoints -n ai openwebui
# NAME        ENDPOINTS   AGE
# openwebui   <none>      5m
```

**Diagnosis**:
```bash
# Check service selector
kubectl get svc -n ai openwebui -o yaml | grep -A5 selector

# Check pod labels
kubectl get pods -n ai --show-labels | grep openwebui
```

**Solution**:

**Cause**: Label mismatch between Service selector and Pod labels.

```bash
# Service selector:     app: openwebui
# Pod labels:           app: open-webui  # Note: hyphen vs no-hyphen

# Fix: Update Service or Deployment to match labels
kubectl edit svc -n ai openwebui
# OR
kubectl edit deployment -n ai openwebui
```

### Issue: DNS not resolving (nslookup fails)

**Symptoms**:
```bash
kubectl run -it --rm debug --image=busybox --restart=Never -- nslookup pgvector
# Error: Server:    10.152.183.10
#        ** server can't find pgvector: NXDOMAIN
```

**Diagnosis**:
```bash
# Check CoreDNS running
kubectl get pods -n kube-system -l k8s-app=kube-dns

# Check service exists
kubectl get svc -n ai pgvector
```

**Causes & Solutions**:

1. **Wrong namespace**:
   ```bash
   # From pod in 'ai' namespace:
   nslookup pgvector                      # Works (same namespace)
   nslookup pgvector.ai                   # Works (explicit namespace)
   nslookup pgvector.ai.svc.cluster.local # Works (FQDN)
   nslookup pgvector.default              # Fails (wrong namespace)
   ```

2. **CoreDNS not running**:
   ```bash
   kubectl get pods -n kube-system -l k8s-app=kube-dns
   # If not Running:
   microk8s disable dns
   microk8s enable dns
   ```

3. **CoreDNS misconfigured**:
   ```bash
   # Check CoreDNS logs
   kubectl logs -n kube-system -l k8s-app=kube-dns

   # Check CoreDNS ConfigMap
   kubectl get cm -n kube-system coredns -o yaml
   ```

## Ingress Issues

### Issue: Ingress shows no ADDRESS

**Symptoms**:
```bash
kubectl get ingress -n ai
# NAME        CLASS   HOSTS          ADDRESS   PORTS   AGE
# openwebui   public  ai.vx.home               80      5m
```

**Diagnosis**:
```bash
# Check Ingress controller running
kubectl get pods -n ingress

# Check Ingress events
kubectl describe ingress -n ai openwebui
```

**Solutions**:

1. **Ingress controller not running**:
   ```bash
   microk8s enable ingress
   ```

2. **Wrong ingressClassName**:
   ```bash
   # Check available IngressClasses
   kubectl get ingressclass

   # Update Ingress to match
   kubectl edit ingress -n ai openwebui
   # spec.ingressClassName: public  # (or nginx, or whatever exists)
   ```

### Issue: Ingress returns 404

**Symptoms**:
```bash
curl http://ai.vx.home
# Output: 404 Not Found
```

**Diagnosis**:
```bash
# Check Ingress configuration
kubectl get ingress -n ai openwebui -o yaml

# Check backend service exists
kubectl get svc -n ai openwebui

# Check Ingress controller logs
kubectl logs -n ingress <nginx-controller-pod>
```

**Solutions**:

1. **Path mismatch**:
   ```yaml
   # Ingress path: /api
   # User requests: /
   # Result: 404

   # Fix: Change path to /
   spec.rules[0].http.paths[0].path: "/"
   ```

2. **Backend service wrong**:
   ```yaml
   # Ingress backend: wrong-service-name
   # Actual service: openwebui
   ```

### Issue: Ingress returns 502/503

**Symptoms**:
```bash
curl http://ai.vx.home
# Output: 502 Bad Gateway OR 503 Service Unavailable
```

**Diagnosis**:
```bash
# Check backend pod running
kubectl get pods -n ai -l app=openwebui

# Check service endpoints
kubectl get endpoints -n ai openwebui

# Check pod logs
kubectl logs -n ai <openwebui-pod>
```

**Solutions**:

1. **502: Backend pod not ready**:
   ```bash
   # Pod exists but not healthy
   kubectl describe pod -n ai <openwebui-pod>
   # Check Readiness probe
   ```

2. **503: No endpoints**:
   ```bash
   # Service has no pods (selector mismatch or pods not running)
   kubectl get endpoints -n ai openwebui
   # If <none>: Fix service selector or start pods
   ```

## cert-manager / TLS Issues

### Issue: Certificate not being issued

**Symptoms**:
```bash
kubectl get certificate -n ai
# NAME           READY   SECRET         AGE
# openwebui-tls  False   openwebui-tls  5m
```

**Diagnosis**:
```bash
# Check certificate status
kubectl describe certificate openwebui-tls -n ai

# Check CertificateRequest
kubectl get certificaterequest -n ai

# Check cert-manager logs
kubectl logs -n cert-manager -l app=cert-manager
```

**Solutions**:

1. **ClusterIssuer not ready**:
   ```bash
   kubectl get clusterissuers
   # If vx-home-ca-issuer shows READY: False

   # Check CA certificate
   kubectl get certificate -n cert-manager vx-home-ca

   # Re-apply cert-manager configuration
   kubectl apply -f k8s/clusters/vx-home/cert-manager/
   ```

2. **Wrong issuer name in annotation**:
   ```yaml
   # Check Ingress annotation
   metadata:
     annotations:
       cert-manager.io/cluster-issuer: "vx-home-ca-issuer"  # Must match exactly
   ```

3. **cert-manager webhook not ready**:
   ```bash
   kubectl get pods -n cert-manager
   # All pods should be Running

   # Restart if needed
   kubectl rollout restart deployment -n cert-manager cert-manager
   kubectl rollout restart deployment -n cert-manager cert-manager-webhook
   ```

### Issue: Browser shows certificate warning despite cert-manager

**Symptoms**: Browser shows "Your connection is not private" even though certificate is issued.

**Diagnosis**:
```bash
# Verify certificate is issued
kubectl get certificate -n ai
# Should show READY: True

# Check certificate issuer
kubectl get secret openwebui-tls -n ai -o jsonpath='{.data.tls\.crt}' | \
  base64 -d | openssl x509 -noout -issuer
# Should show: issuer=CN = VX Home CA
```

**Solutions**:

1. **CA not trusted on client**:
   ```bash
   # Export CA certificate
   kubectl get secret vx-home-ca-secret -n cert-manager \
     -o jsonpath='{.data.ca\.crt}' | base64 -d > ~/vx-home-ca.crt

   # Trust it - see docs/15-cert-manager.md for platform-specific instructions
   ```

2. **Old certificate cached**:
   - Clear browser cache
   - Try incognito/private window
   - Restart browser

3. **Firefox (uses separate cert store)**:
   - Firefox Settings → Privacy & Security → Certificates → View Certificates
   - Import the CA certificate to the Authorities tab

### Issue: cert-manager pods not starting

**Symptoms**:
```bash
kubectl get pods -n cert-manager
# NAME                                      READY   STATUS
# cert-manager-XXX                          0/1     Pending
```

**Diagnosis**:
```bash
kubectl describe pod -n cert-manager <pod-name>
```

**Solutions**:

1. **Resource constraints**:
   ```bash
   # Check node resources
   kubectl describe nodes | grep -A10 Allocatable
   ```

2. **Webhook certificate bootstrap failed**:
   ```bash
   # Delete webhook secret to force regeneration
   kubectl delete secret -n cert-manager cert-manager-webhook-ca
   kubectl rollout restart deployment -n cert-manager cert-manager-webhook
   ```

## Storage Issues

### Issue: PVC stuck in Pending

**Symptoms**:
```bash
kubectl get pvc -n ai
# NAME             STATUS    VOLUME   CAPACITY   ACCESS MODES   STORAGECLASS        AGE
# openwebui-data   Pending                                      microk8s-hostpath   5m
```

**Diagnosis**:
```bash
kubectl describe pvc -n ai openwebui-data
# Events: waiting for a volume to be created, either by external provisioner ...
```

**Solutions**:

1. **StorageClass doesn't exist**:
   ```bash
   kubectl get sc
   # If microk8s-hostpath missing:
   microk8s enable hostpath-storage
   ```

2. **No provisioner**:
   ```bash
   # Check provisioner pod running
   kubectl get pods -n kube-system -l app.kubernetes.io/name=hostpath-provisioner
   ```

3. **Access mode not supported**:
   ```yaml
   # PVC requests: ReadWriteMany
   # hostpath-storage only supports: ReadWriteOnce
   # Fix: Change to ReadWriteOnce (single-node is fine for this)
   ```

### Issue: Pod running but volume is empty

**Symptoms**:
```bash
# Pod logs show: "No data found"
# Expected data is missing
```

**Diagnosis**:
```bash
# Check volume mount
kubectl get pod -n ai <pod> -o yaml | grep -A10 volumeMounts

# Shell into pod and check
kubectl exec -it -n ai <pod> -- ls -la /app/backend/data
```

**Solutions**:

1. **Wrong mount path**:
   ```yaml
   # Container expects: /app/backend/data
   # Volume mounted at: /data
   # Fix: Correct mount path
   ```

2. **Volume not mounted**:
   ```yaml
   # Volume defined but not in volumeMounts
   # Fix: Add volumeMount
   ```

3. **PVC bound to wrong PV**:
   ```bash
   # Check PVC → PV binding
   kubectl get pvc -n ai -o wide
   kubectl get pv -o wide
   ```

## Database Issues

### Issue: Can't connect to Postgres

**Symptoms**:
- Open WebUI logs: "Connection refused" or "could not connect to server"

**Diagnosis**:
```bash
# Check pgvector pod running
kubectl get pods -n ai -l app=pgvector

# Test connection from another pod
kubectl run -it --rm psql-test --image=postgres:16 --restart=Never -n ai -- \
  psql -h pgvector -U openwebui -d openwebui
```

**Solutions**:

1. **Service not pointing to pod**:
   ```bash
   kubectl get endpoints -n ai pgvector
   # If <none>: Fix service selector
   ```

2. **Wrong password**:
   ```bash
   # Check secret
   kubectl get secret -n ai ai-secrets -o jsonpath='{.data.POSTGRES_PASSWORD}' | base64 -d
   # Compare with DATABASE_URL in openwebui deployment
   ```

3. **Database not initialized**:
   ```bash
   # Check pgvector logs
   kubectl logs -n ai statefulset/pgvector
   # Look for: database system is ready to accept connections
   ```

### Issue: pgvector extension not available

**Symptoms**:
```sql
ERROR:  extension "vector" does not exist
```

**Solution**:
```bash
# Run init script
./scripts/admin/init-pgvector.sh

# OR manually:
kubectl exec -it -n ai statefulset/pgvector -- psql -U openwebui -d openwebui -c "CREATE EXTENSION IF NOT EXISTS vector;"
```

## Performance Issues

### Issue: Pods using too much CPU/memory

**Diagnosis**:
```bash
# Enable metrics-server
microk8s enable metrics-server

# Check pod resources
kubectl top pods -n ai

# Check node resources
kubectl top nodes
```

**Solutions**:

1. **Add resource limits** (prevent runaway):
   ```yaml
   resources:
     limits:
       memory: "2Gi"
       cpu: "2000m"
     requests:
       memory: "512Mi"
       cpu: "500m"
   ```

2. **Scale horizontally** (more replicas, less per-pod load):
   ```bash
   kubectl scale deployment -n ai openwebui --replicas=3
   ```

3. **Optimize application**:
   - Reduce embedding model size
   - Enable Redis caching
   - Tune Postgres connections

## Disk Space Issues

### Issue: Node disk full

**Symptoms**:
```bash
df -h /var/snap/microk8s
# Output: Filesystem      Size  Used Avail Use% Mounted on
#         /dev/sda1       100G   98G    2G  98% /
```

**Solutions**:

1. **Clean up unused images**:
   ```bash
   microk8s ctr images list | grep -v REGISTRY
   microk8s ctr images remove <image-name>
   ```

2. **Delete failed pods**:
   ```bash
   kubectl delete pod --field-selector=status.phase=Failed -A
   ```

3. **Clean up old logs**:
   ```bash
   sudo journalctl --vacuum-time=7d
   ```

4. **Increase volume size** (if hostpath):
   - Expand underlying disk (VM or physical)
   - Resize filesystem

## Monitoring and Prevention

### Set Up Alerts (Future)

```bash
# Enable observability stack
microk8s enable observability

# Access Grafana
kubectl port-forward -n observability svc/grafana 3000:3000

# Create alerts for:
# - Disk usage > 80%
# - Pod crashes > 5 in 10 minutes
# - Service endpoints == 0
```

### Regular Maintenance

```bash
# Weekly checks
kubectl get pods -A  # All pods Running?
df -h  # Disk space OK?
microk8s status  # All addons healthy?

# Monthly cleanup
kubectl delete pod --field-selector=status.phase=Failed -A
microk8s ctr images prune  # Remove unused images
```

## CKA Exam Tips

### Time-Saving Debugging Commands

```bash
# Aliases (add to ~/.bashrc)
alias k='kubectl'
alias kgp='kubectl get pods'
alias kd='kubectl describe'
alias kl='kubectl logs'

# Quick pod status
k get po -A -o wide | grep -v Running

# Recent events (last 10 minutes)
k get events --sort-by='.lastTimestamp' | tail -20

# Pod logs + grep for errors
k logs <pod> -n ai | grep -i error

# Exec shortcuts
k exec -it <pod> -n ai -- bash  # Shell
k exec -it <pod> -n ai -- env   # Environment vars
```

### Practice Scenarios

1. **Pod won't start**: Diagnose and fix within 5 minutes
2. **Service not reachable**: End-to-end network troubleshooting
3. **PVC won't bind**: Storage troubleshooting workflow
4. **Application crash**: Logs analysis and configuration fix

---

**Remember**: 90% of Kubernetes issues are configuration errors. Always check:
1. Labels and selectors match
2. Resource names spelled correctly
3. Namespaces are correct
4. Secrets/ConfigMaps exist and have correct keys
5. Network policies (if any) allow traffic

**CKA Exam**: Practice troubleshooting under time pressure. Speed comes from systematic workflows, not random commands!
