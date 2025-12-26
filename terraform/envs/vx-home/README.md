# Terraform Configuration for VX Home

## Status: Placeholder for Future Phase 2

This directory is reserved for future Terraform infrastructure-as-code implementation.

## Planned Usage

When migrating to Terraform (Phase 2), this directory will contain:

- `main.tf` - Main Terraform configuration
- `variables.tf` - Variable definitions
- `terraform.tfvars` - Variable values (gitignored!)
- `terraform.tfvars.example` - Variable template
- `providers.tf` - Provider configurations (Kubernetes, Helm, DNS, etc.)
- `backend.tf` - State backend configuration

## Current State

For now, use:
- `kubectl apply -k k8s/clusters/vx-home` for deployments
- Kustomize for configuration management
- Manual DNS configuration

## Migration Path

See [docs/50-terraform-future.md](../../../docs/50-terraform-future.md) for the complete Terraform migration strategy.

## Resources

- [Terraform Kubernetes Provider](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs)
- [Terraform Helm Provider](https://registry.terraform.io/providers/hashicorp/helm/latest/docs)
- [Terraform Best Practices](https://www.terraform-best-practices.com/)
