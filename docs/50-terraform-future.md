# Terraform Migration Path

## Overview

This document outlines the strategy for migrating from manual Kubernetes manifests to **Terraform-managed infrastructure**, enabling true Infrastructure as Code (IaC) for your homelab.

**Current State**: Kubectl + Kustomize (declarative, but manual apply)

**Target State**: Terraform + Git (fully automated, version-controlled infrastructure)

## Why Terraform?

### Benefits for This Homelab

| Benefit | Current (Kustomize) | With Terraform |
|---------|---------------------|----------------|
| **State Management** | No state tracking | Terraform knows what exists |
| **Drift Detection** | Manual `kubectl diff` | Automatic `terraform plan` |
| **Dependencies** | Manual ordering | Automatic dependency graph |
| **External Resources** | Can't manage (DNS, LB, certs) | Full lifecycle management |
| **Rollback** | Manual (`kubectl apply` old YAML) | `terraform apply` old state |
| **Multi-Environment** | Kustomize overlays (limited) | Terraform workspaces + modules |

**CKA Relevance**: While CKA focuses on kubectl, real-world production uses IaC (Terraform, Pulumi, Crossplane).

### What Terraform Can Manage

**Currently Manual**:
- ✅ DNS records (/etc/hosts entries)
- ✅ LetsEncrypt certificates (manual cert-manager setup)
- ✅ MicroK8s addons (manual enable commands)
- ✅ Node configuration (labels, taints)

**Terraform Can Automate**:
- 🔄 Kubernetes resources (Deployments, Services, etc.)
- 🔄 Helm releases (Portainer, future apps)
- 🔄 DNS via provider (Cloudflare, Route53, PowerDNS)
- 🔄 Certificates via cert-manager CRDs
- 🔄 Node configuration via cloud-init or Ansible

## Terraform Repository Structure

### Recommended Layout

```
vx-home-infra/
├── terraform/
│   ├── modules/                       # Reusable modules
│   │   ├── kubernetes-namespace/      # Module: create namespace + defaults
│   │   │   ├── main.tf
│   │   │   ├── variables.tf
│   │   │   └── outputs.tf
│   │   ├── ai-stack/                  # Module: Open WebUI + deps
│   │   │   ├── main.tf
│   │   │   ├── variables.tf
│   │   │   └── outputs.tf
│   │   ├── ingress-route/             # Module: create Ingress
│   │   │   └── main.tf
│   │   └── postgresql-cluster/        # Module: Postgres + pgvector
│   │       └── main.tf
│   │
│   ├── envs/                          # Environment-specific configs
│   │   ├── vx-home/                   # Production homelab
│   │   │   ├── main.tf                # Main entry point
│   │   │   ├── variables.tf           # Environment variables
│   │   │   ├── terraform.tfvars       # Variable values (gitignored!)
│   │   │   ├── terraform.tfvars.example  # Template
│   │   │   ├── backend.tf             # State backend config
│   │   │   ├── providers.tf           # Provider configuration
│   │   │   └── README.md
│   │   └── vx-home-dev/               # Future dev environment (optional)
│   │       └── ...
│   │
│   └── global/                        # Shared infrastructure (DNS, etc.)
│       ├── dns/
│       │   ├── main.tf                # Cloudflare/Route53 DNS records
│       │   └── variables.tf
│       └── certificates/
│           └── main.tf                # cert-manager ClusterIssuers
│
├── k8s/                               # Keep existing Kustomize (migration phase)
│   └── ...
├── scripts/                           # Keep bootstrap scripts
│   └── ...
└── docs/
    └── ...
```

**Separation of Concerns**:
- **modules/**: Generic, reusable components
- **envs/**: Environment-specific values (prod, dev, staging)
- **global/**: Shared infrastructure across environments

### Terraform Files Explained

**main.tf**:
```hcl
# Call modules and wire them together
module "ai_namespace" {
  source = "../../modules/kubernetes-namespace"
  name   = "ai"
}

module "ai_stack" {
  source        = "../../modules/ai-stack"
  namespace     = module.ai_namespace.name
  domain        = var.domain
  openai_api_key = var.openai_api_key
}
```

**variables.tf**:
```hcl
variable "domain" {
  description = "Base domain for services (e.g., vx.home)"
  type        = string
}

variable "openai_api_key" {
  description = "OpenAI API key"
  type        = string
  sensitive   = true
}
```

**terraform.tfvars** (gitignored, user-specific):
```hcl
domain = "vx.home"
openai_api_key = "sk-REAL_KEY_HERE"
```

**terraform.tfvars.example** (tracked in Git):
```hcl
domain = "example.com"
openai_api_key = "sk-REPLACE_ME"
```

**providers.tf**:
```hcl
terraform {
  required_version = ">= 1.5.0"
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.23"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.11"
    }
  }
}

provider "kubernetes" {
  config_path = "~/.kube/config"  # Or MicroK8s config
}

provider "helm" {
  kubernetes {
    config_path = "~/.kube/config"
  }
}
```

**backend.tf** (state storage):
```hcl
terraform {
  backend "local" {
    path = "terraform.tfstate"
  }
  # Future: remote backend (S3, Terraform Cloud, etc.)
}
```

## Migration Phases

### Phase 1: Terraform Setup (Foundation)

**Goal**: Install Terraform, create basic structure

**Steps**:

1. **Install Terraform**:
   ```bash
   # On Rocky Linux
   sudo dnf config-manager --add-repo https://rpm.releases.hashicorp.com/RHEL/hashicorp.repo
   sudo dnf install terraform

   # Verify
   terraform version
   ```

2. **Create directory structure** (see above)

3. **Configure providers**:
   ```bash
   cd terraform/envs/vx-home
   terraform init
   # Downloads Kubernetes + Helm providers
   ```

4. **Import existing resources** (advanced, see below)

### Phase 2: Migrate DNS to Code

**Goal**: Manage DNS records via Terraform

**Current State**: Manual `/etc/hosts` entries

**Target State**: Terraform-managed DNS (Cloudflare, PowerDNS, or Route53)

**Example: Cloudflare Provider**

```hcl
# terraform/global/dns/main.tf
terraform {
  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 4.0"
    }
  }
}

provider "cloudflare" {
  api_token = var.cloudflare_api_token
}

resource "cloudflare_record" "ai_vx_home" {
  zone_id = var.cloudflare_zone_id
  name    = "ai.vx.home"
  value   = var.node_ip
  type    = "A"
  ttl     = 3600
}

resource "cloudflare_record" "ptnr_vx_home" {
  zone_id = var.cloudflare_zone_id
  name    = "ptnr.adm.vx.home"
  value   = var.node_ip
  type    = "A"
  ttl     = 3600
}

resource "cloudflare_record" "control_vx_home" {
  zone_id = var.cloudflare_zone_id
  name    = "control.adm.vx.home"
  value   = var.node_ip
  type    = "A"
  ttl     = 3600
}
```

**Alternative: PowerDNS (self-hosted)**

```hcl
provider "powerdns" {
  api_url    = "http://powerdns.vx.home:8081"
  api_key    = var.powerdns_api_key
  server_id  = "localhost"
}

resource "powerdns_record" "ai" {
  zone    = "vx.home."
  name    = "ai.vx.home."
  type    = "A"
  ttl     = 3600
  records = [var.node_ip]
}
```

### Phase 3: Migrate Kubernetes Resources

**Goal**: Replace `kubectl apply -k` with `terraform apply`

**Strategy**: Incremental migration (not big-bang)

**Example: Migrate Open WebUI Deployment**

```hcl
# terraform/modules/ai-stack/openwebui.tf
resource "kubernetes_deployment_v1" "openwebui" {
  metadata {
    name      = "openwebui"
    namespace = var.namespace
    labels = {
      app = "openwebui"
    }
  }

  spec {
    replicas = var.openwebui_replicas

    selector {
      match_labels = {
        app = "openwebui"
      }
    }

    template {
      metadata {
        labels = {
          app = "openwebui"
        }
      }

      spec {
        container {
          name  = "openwebui"
          image = "ghcr.io/open-webui/open-webui:v0.6.42"

          port {
            container_port = 8080
          }

          env {
            name  = "WEBUI_URL"
            value = "http://${var.domain}"
          }

          env {
            name  = "DATABASE_URL"
            value = "postgresql://openwebui:${var.postgres_password}@pgvector:5432/openwebui"
          }

          env {
            name = "OPENAI_API_KEY"
            value_from {
              secret_key_ref {
                name = kubernetes_secret_v1.ai_secrets.metadata[0].name
                key  = "OPENAI_API_KEY"
              }
            }
          }

          volume_mount {
            name       = "data"
            mount_path = "/app/backend/data"
          }
        }

        volume {
          name = "data"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim_v1.openwebui_data.metadata[0].name
          }
        }
      }
    }
  }
}

resource "kubernetes_service_v1" "openwebui" {
  metadata {
    name      = "openwebui"
    namespace = var.namespace
  }

  spec {
    selector = {
      app = "openwebui"
    }

    port {
      port        = 80
      target_port = 8080
    }

    type = "ClusterIP"
  }
}
```

**Benefits**:
- Variables for replicas, images, passwords (easier to change)
- Dependencies auto-managed (Service waits for Deployment)
- State tracking (Terraform knows what exists)

### Phase 4: Helm Releases via Terraform

**Goal**: Manage Portainer and other Helm charts via Terraform

**Example: Portainer via Terraform**

```hcl
# terraform/modules/portainer/main.tf
resource "helm_release" "portainer" {
  name       = "portainer"
  repository = "https://portainer.github.io/k8s/"
  chart      = "portainer"
  version    = "1.0.45"  # Pin version for reproducibility

  namespace        = kubernetes_namespace_v1.portainer.metadata[0].name
  create_namespace = false  # We create it explicitly

  values = [
    file("${path.module}/values.yaml")
  ]

  set {
    name  = "ingress.hosts[0].host"
    value = var.portainer_domain
  }

  set_sensitive {
    name  = "adminPassword"
    value = var.portainer_admin_password
  }
}

resource "kubernetes_namespace_v1" "portainer" {
  metadata {
    name = "portainer"
  }
}
```

**Benefits over manual Helm**:
- Version pinning (reproducible deployments)
- Values templating (different per environment)
- Integration with other Terraform resources

### Phase 5: cert-manager + Let's Encrypt

**Goal**: Automatic TLS certificates for Ingresses

**cert-manager via Terraform**:

```hcl
# terraform/global/certificates/cert-manager.tf
resource "helm_release" "cert_manager" {
  name       = "cert-manager"
  repository = "https://charts.jetstack.io"
  chart      = "cert-manager"
  version    = "v1.13.0"
  namespace  = "cert-manager"
  create_namespace = true

  set {
    name  = "installCRDs"
    value = "true"
  }
}

# ClusterIssuer for Let's Encrypt
resource "kubectl_manifest" "letsencrypt_prod" {
  depends_on = [helm_release.cert_manager]

  yaml_body = <<-YAML
    apiVersion: cert-manager.io/v1
    kind: ClusterIssuer
    metadata:
      name: letsencrypt-prod
    spec:
      acme:
        server: https://acme-v02.api.letsencrypt.org/directory
        email: ${var.letsencrypt_email}
        privateKeySecretRef:
          name: letsencrypt-prod
        solvers:
        - http01:
            ingress:
              class: nginx
  YAML
}
```

**Ingress with TLS**:

```hcl
resource "kubernetes_ingress_v1" "openwebui" {
  metadata {
    name      = "openwebui"
    namespace = var.namespace
    annotations = {
      "cert-manager.io/cluster-issuer" = "letsencrypt-prod"
    }
  }

  spec {
    ingress_class_name = "public"

    tls {
      hosts       = ["ai.vx.home"]
      secret_name = "openwebui-tls"
    }

    rule {
      host = "ai.vx.home"
      http {
        path {
          path      = "/"
          path_type = "Prefix"
          backend {
            service {
              name = kubernetes_service_v1.openwebui.metadata[0].name
              port {
                number = 80
              }
            }
          }
        }
      }
    }
  }
}
```

**Result**: Automatic HTTPS with valid certificates!

## Advanced: State Management

### Local State (Default)

**Current**:
```hcl
terraform {
  backend "local" {
    path = "terraform.tfstate"
  }
}
```

**Pros**:
- Simple (no setup)
- Fast (no network)

**Cons**:
- No collaboration (state on one machine)
- No locking (risk of concurrent apply)
- No backup (lose file = lose state)

### Remote State (Production)

**Option 1: Terraform Cloud (Free tier)**

```hcl
terraform {
  backend "remote" {
    organization = "your-org"
    workspaces {
      name = "vx-home-infra"
    }
  }
}
```

**Pros**:
- Free for small teams (5 users)
- State locking
- State history
- Web UI for runs

**Option 2: S3 + DynamoDB (AWS)**

```hcl
terraform {
  backend "s3" {
    bucket         = "vx-home-terraform-state"
    key            = "vx-home/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "terraform-locks"
    encrypt        = true
  }
}
```

**Option 3: MinIO (Self-hosted S3)**

```hcl
terraform {
  backend "s3" {
    bucket                      = "terraform-state"
    key                         = "vx-home/terraform.tfstate"
    region                      = "us-east-1"
    endpoint                    = "https://minio.vx.home"
    skip_credentials_validation = true
    skip_metadata_api_check     = true
    force_path_style            = true
  }
}
```

## Workflow: Terraform + GitOps

### GitOps Pattern

```
Developer → Git push → CI/CD → Terraform apply → Kubernetes
```

**Steps**:
1. Developer changes `main.tf` (e.g., scale Open WebUI to 3 replicas)
2. Push to Git (GitHub, GitLab)
3. CI/CD pipeline (GitHub Actions, GitLab CI) runs:
   ```bash
   terraform init
   terraform plan -out=plan.tfplan
   terraform apply plan.tfplan
   ```
4. Kubernetes resources updated automatically

**Example: GitHub Actions**

```yaml
# .github/workflows/terraform.yml
name: Terraform
on:
  push:
    branches: [main]
    paths:
      - 'terraform/**'

jobs:
  terraform:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3

      - name: Setup Terraform
        uses: hashicorp/setup-terraform@v2

      - name: Terraform Init
        run: terraform init
        working-directory: terraform/envs/vx-home

      - name: Terraform Plan
        run: terraform plan -out=plan.tfplan
        working-directory: terraform/envs/vx-home

      - name: Terraform Apply
        run: terraform apply plan.tfplan
        working-directory: terraform/envs/vx-home
        env:
          KUBE_CONFIG_PATH: ${{ secrets.KUBECONFIG }}
```

## Comparison: Terraform vs FluxCD/ArgoCD

| Feature | Terraform | FluxCD/ArgoCD |
|---------|-----------|---------------|
| **State Management** | Terraform state file | Kubernetes cluster state |
| **Language** | HCL | YAML (Kustomize/Helm) |
| **Scope** | Any infrastructure (DNS, VMs, K8s) | Kubernetes only |
| **Reconciliation** | On `terraform apply` | Continuous (every N minutes) |
| **Drift Detection** | `terraform plan` | Automatic sync |
| **Learning Curve** | Medium (new language) | Low (uses kubectl/kustomize) |

**Recommendation for Homelab**:
- **Now**: Terraform (simpler for single-node)
- **Phase 3**: Add FluxCD (GitOps automation)

## Implementation Timeline

**Month 1**: Foundation
- Install Terraform
- Create module structure
- Import existing Namespace + Secrets

**Month 2**: Core Infrastructure
- Migrate Deployments + StatefulSets to Terraform
- Keep Kustomize as fallback

**Month 3**: External Resources
- DNS via Terraform (Cloudflare/PowerDNS)
- cert-manager + Let's Encrypt

**Month 4**: Automation
- GitHub Actions for CI/CD
- Remote state backend

**Month 5**: Advanced
- Multi-environment (dev/prod)
- FluxCD integration

## CKA Learning Points

### IaC Concepts

**Declarative vs Imperative**:
- Declarative: "I want 3 replicas" (Terraform, kubectl apply)
- Imperative: "Create 3 pods" (kubectl create, run)

**CKA Exam**: Tests imperative commands (faster for time-constrained scenarios), but production uses declarative.

### State Management

**Kubernetes Native State**:
- etcd stores all K8s resource state
- kubectl communicates with API server → etcd

**Terraform State**:
- Tracks resources Terraform manages
- Separate from Kubernetes (can manage non-K8s resources)

## Resources

**Terraform**:
- [Terraform Kubernetes Provider](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs)
- [Terraform Helm Provider](https://registry.terraform.io/providers/hashicorp/helm/latest/docs)
- [Terraform Best Practices](https://www.terraform-best-practices.com/)

**GitOps**:
- [FluxCD Documentation](https://fluxcd.io/)
- [ArgoCD Documentation](https://argo-cd.readthedocs.io/)

**cert-manager**:
- [cert-manager Documentation](https://cert-manager.io/docs/)
- [Let's Encrypt with Kubernetes](https://cert-manager.io/docs/tutorials/acme/nginx-ingress/)

## Summary

**Terraform Migration Benefits**:
- ✅ Full infrastructure as code (K8s + DNS + certs)
- ✅ Version control for all changes
- ✅ Automated deployments via CI/CD
- ✅ State tracking and drift detection

**Migration Path**:
1. Install Terraform, create structure
2. Migrate DNS to code
3. Incrementally migrate K8s resources
4. Add cert-manager for TLS
5. Implement GitOps automation

**Timeline**: 4-5 months for full migration (can be done incrementally)

**CKA Value**: While Terraform isn't on the CKA exam, it's essential for real-world Kubernetes operations.

---

**This is Phase 2+**. Complete current setup first, validate everything works, then migrate to Terraform when ready.
