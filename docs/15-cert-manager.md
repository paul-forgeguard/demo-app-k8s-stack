# cert-manager and TLS Certificates

## Overview

**cert-manager** is a Kubernetes addon that automates the management and issuance of TLS certificates. This homelab uses cert-manager with a self-signed CA (Certificate Authority) to provide TLS for all web services.

**Services with TLS enabled:**
- `https://ptnr.adm.vx.home` - Portainer
- `https://ai.adm.vx.home` - Open WebUI
- `https://control.adm.vx.home` - Control Portal (pgAdmin)

## How It Works

### The CA Chain

We use a three-level certificate hierarchy:

```
┌─────────────────────────────┐
│   selfsigned-issuer         │  ← Bootstrap (ClusterIssuer)
│   (self-signed)             │
└─────────────┬───────────────┘
              │ signs
              ▼
┌─────────────────────────────┐
│   vx-home-ca                │  ← CA Certificate (10-year validity)
│   (Certificate)             │
└─────────────┬───────────────┘
              │ used by
              ▼
┌─────────────────────────────┐
│   vx-home-ca-issuer         │  ← Production Issuer (ClusterIssuer)
│   (CA issuer)               │
└─────────────┬───────────────┘
              │ signs
              ▼
┌─────────────────────────────┐
│   Application Certificates  │  ← Your TLS certs (auto-generated)
│   (portainer-tls, etc.)     │
└─────────────────────────────┘
```

### Automatic Certificate Issuance

When you create an Ingress with the cert-manager annotation:

```yaml
metadata:
  annotations:
    cert-manager.io/cluster-issuer: "vx-home-ca-issuer"
spec:
  tls:
    - secretName: myapp-tls
      hosts:
        - myapp.adm.vx.home
```

cert-manager automatically:
1. Creates a Certificate resource
2. Generates a private key
3. Requests signing from `vx-home-ca-issuer`
4. Stores the certificate in the specified Secret

## Installation

### Step 1: Enable cert-manager addon

```bash
microk8s enable cert-manager
```

### Step 2: Wait for cert-manager to be ready

```bash
kubectl wait --for=condition=Available deployment/cert-manager -n cert-manager --timeout=120s
kubectl wait --for=condition=Available deployment/cert-manager-webhook -n cert-manager --timeout=120s
kubectl wait --for=condition=Available deployment/cert-manager-cainjector -n cert-manager --timeout=120s
```

### Step 3: Configure the CA

```bash
# Using setup script
./scripts/setup/06-configure-cert-manager.sh

# Or manually
kubectl apply -f k8s/clusters/vx-home/cert-manager/
kubectl wait --for=condition=Ready certificate/vx-home-ca -n cert-manager --timeout=60s
```

### Step 4: Verify setup

```bash
# Check ClusterIssuers
kubectl get clusterissuers
# NAME                 READY   AGE
# selfsigned-issuer    True    Xs
# vx-home-ca-issuer    True    Xs

# Check CA Certificate
kubectl get certificate -n cert-manager
# NAME         READY   SECRET              AGE
# vx-home-ca   True    vx-home-ca-secret   Xs
```

## Trusting the CA Certificate

Since we use a self-signed CA, you need to trust it on client machines to avoid browser warnings.

### Export the CA Certificate

```bash
kubectl get secret vx-home-ca-secret -n cert-manager \
  -o jsonpath='{.data.ca\.crt}' | base64 -d > ~/vx-home-ca.crt
```

### Linux (Debian/Ubuntu/Rocky/RHEL)

```bash
# Copy to system CA directory
sudo cp ~/vx-home-ca.crt /usr/local/share/ca-certificates/vx-home-ca.crt

# Update CA certificates
sudo update-ca-certificates

# Verify
curl https://ptnr.adm.vx.home  # Should work without -k flag
```

### macOS

```bash
# Add to System Keychain (requires admin password)
sudo security add-trusted-cert -d -r trustRoot \
  -k /Library/Keychains/System.keychain ~/vx-home-ca.crt

# Verify
curl https://ptnr.adm.vx.home
```

### Windows

1. Open `certmgr.msc` (Certificate Manager)
2. Navigate to: **Trusted Root Certification Authorities** → **Certificates**
3. Right-click → **All Tasks** → **Import...**
4. Select `vx-home-ca.crt`
5. Place in "Trusted Root Certification Authorities"
6. Finish the wizard

### Firefox (All Platforms)

Firefox uses its own certificate store, not the system store:

1. Open Firefox Settings
2. Search for "certificates"
3. Click **View Certificates...**
4. Go to **Authorities** tab
5. Click **Import...**
6. Select `vx-home-ca.crt`
7. Check "Trust this CA to identify websites"
8. Click OK

## Using TLS in Your Services

### Adding TLS to an Ingress

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: myapp
  namespace: ai
  annotations:
    cert-manager.io/cluster-issuer: "vx-home-ca-issuer"
spec:
  ingressClassName: public
  tls:
    - secretName: myapp-tls
      hosts:
        - myapp.adm.vx.home
  rules:
  - host: myapp.adm.vx.home
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: myapp
            port:
              number: 80
```

### Verifying a Certificate

```bash
# Check certificate status
kubectl get certificate -n ai
# NAME           READY   SECRET         AGE
# myapp-tls      True    myapp-tls      Xs

# View certificate details
kubectl describe certificate myapp-tls -n ai

# Check the actual certificate
kubectl get secret myapp-tls -n ai -o jsonpath='{.data.tls\.crt}' | \
  base64 -d | openssl x509 -text -noout | head -20
```

## Troubleshooting

### Certificate not being issued

**Symptoms:** Certificate shows `Ready: False`

**Diagnosis:**
```bash
# Check Certificate status
kubectl describe certificate <name> -n <namespace>

# Check cert-manager logs
kubectl logs -n cert-manager -l app=cert-manager
```

**Common causes:**
1. ClusterIssuer not ready - check `kubectl get clusterissuers`
2. Wrong issuer name in annotation
3. cert-manager webhook not ready

### Certificate shows "Pending"

```bash
# Check CertificateRequest
kubectl get certificaterequest -n <namespace>

# Describe the request
kubectl describe certificaterequest <name> -n <namespace>
```

### Browser still shows certificate warning

1. **CA not trusted** - Follow the "Trusting the CA Certificate" section above
2. **Old certificate cached** - Clear browser cache or restart browser
3. **Wrong hostname** - Check that the certificate covers the hostname you're accessing

### cert-manager pods not starting

```bash
# Check pod status
kubectl get pods -n cert-manager

# Check events
kubectl get events -n cert-manager --sort-by='.lastTimestamp'

# Check webhook configuration
kubectl get validatingwebhookconfigurations | grep cert-manager
```

## CKA Learning Points

### PKI (Public Key Infrastructure)

**Key concepts:**
- **Certificate Authority (CA):** Entity that signs certificates
- **Certificate Chain:** Hierarchy from root CA to end-entity certificate
- **Self-signed:** Certificate signed by its own private key (bootstrap)
- **CA-signed:** Certificate signed by a CA's private key (production)

**Why a CA chain?**
- Self-signed certs for each service = trust each individually
- CA-signed certs = trust one CA, all services trusted

### Kubernetes Certificate Resources

cert-manager introduces these CRDs:

| Resource | Purpose |
|----------|---------|
| `Certificate` | Requests a certificate from an Issuer |
| `CertificateRequest` | Internal request object |
| `Issuer` | Namespace-scoped certificate issuer |
| `ClusterIssuer` | Cluster-wide certificate issuer |

### X.509 Certificate Fields

Key fields in a TLS certificate:
- **Subject/CN:** Common Name (hostname)
- **SAN:** Subject Alternative Names (additional hostnames)
- **Issuer:** Who signed this certificate
- **Validity:** Not Before / Not After dates
- **Public Key:** For encryption/verification

```bash
# View certificate fields
openssl x509 -in cert.pem -text -noout
```

## Alternative: Let's Encrypt

For production environments with public DNS, you can use Let's Encrypt:

```yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: your-email@example.com
    privateKeySecretRef:
      name: letsencrypt-prod-key
    solvers:
    - http01:
        ingress:
          class: nginx
```

**Requirements:**
- Public DNS pointing to your server
- Port 80 accessible from internet (for HTTP-01 challenge)
- Valid email address

## Resources

- [cert-manager Documentation](https://cert-manager.io/docs/)
- [Kubernetes TLS Secrets](https://kubernetes.io/docs/concepts/configuration/secret/#tls-secrets)
- [NGINX Ingress TLS](https://kubernetes.github.io/ingress-nginx/user-guide/tls/)
- [MicroK8s cert-manager Addon](https://microk8s.io/docs/addon-cert-manager)
