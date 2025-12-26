# Claude Code Maintenance Guide

## Purpose

This file provides instructions for future Claude Code sessions (or human maintainers) on how to maintain and update this repository as improvements and fixes are discovered.

## Critical Instructions

### 0. Research First - Don't Waste Time Guessing

**CRITICAL**: When investigating configuration issues or setting up tools:

- **ALWAYS** search official documentation first before attempting to figure things out on the fly
- **DO NOT** waste user time by running multiple diagnostic commands when a quick doc lookup would give the answer
- **STICK TO** official documentation only unless the user authorizes looking elsewhere
- **USE** WebSearch or WebFetch to look up official docs immediately
- The goal is efficiency - documentation exists for a reason

### 1. Actually Diagnose Issues - Don't Just Theorize

**CRITICAL**: When troubleshooting issues, you MUST actually run diagnostic commands to investigate:

- **DO NOT** accept the user's diagnosis at face value without verification
- **DO NOT** provide theoretical solutions without checking actual configuration
- **ALWAYS** run kubectl/diagnostic commands to see real state (get, describe, logs, etc.)
- **VERIFY** configuration with actual YAML output, not assumptions
- **CHECK** logs from both the affected pod and related components (Ingress, etc.)
- Let the user fix the issue themselves - your role is to diagnose and guide

**Example troubleshooting workflow:**
1. Run `kubectl get` and `kubectl describe` to see actual state
2. Check pod logs with `kubectl logs`
3. Verify Service endpoints with `kubectl get endpoints`
4. Check related controller logs (Ingress controller, etc.)
5. Only THEN explain what you found and guide the user to the fix

### 2. Documentation is Sacred

**ALWAYS** update documentation when making changes:

- If you fix a broken installation step, update the relevant doc in `docs/`
- If you discover a better way to do something, document it
- If you add a new feature or component, create or update documentation
- If troubleshooting reveals new issues, add to `docs/90-troubleshooting.md`

### 3. Keep Everything In Sync (The Synchronization Rule)

**CRITICAL**: When modifying configuration that affects multiple files, you MUST update ALL related locations. Partial updates create confusion and break the installation flow.

**For any Kubernetes feature change, update ALL of these:**

| Location | Purpose | Example |
|----------|---------|---------|
| `scripts/setup/` | One-time setup scripts | Enable addon, configure component |
| `scripts/admin/` | Day-to-day admin scripts | Deploy, logs, restart |
| `scripts/lib/common.sh` | Shared functions | Logging, kubectl helpers |
| `k8s/clusters/` | Declarative manifests | Deployment, Service, Ingress YAML |
| `docs/*.md` | Feature documentation | How it works, configuration options |
| `docs/INSTALLATION-WALKTHROUGH.md` | Step-by-step guide | User commands with verification |
| `docs/90-troubleshooting.md` | Common issues | Error messages and solutions |
| `claude.md` | Maintenance notes | Version tracking, patterns |

**Checklist before completing ANY change:**

- [ ] Did I update/create the script in `scripts/setup/` or `scripts/admin/`?
- [ ] Did I update/create the manifest YAML files?
- [ ] Did I update the relevant `docs/*.md` file?
- [ ] Did I update `docs/INSTALLATION-WALKTHROUGH.md` with user commands?
- [ ] Did I add troubleshooting info to `docs/90-troubleshooting.md`?
- [ ] Did I update `claude.md` if this is a new pattern?

**Example - Adding TLS with cert-manager:**
1. `scripts/setup/05-enable-addons.sh` - Add cert-manager to addon list
2. `scripts/setup/06-configure-cert-manager.sh` - Script for CA setup
3. `k8s/clusters/vx-home/cert-manager/clusterissuer.yaml` - ClusterIssuer manifest
4. `k8s/clusters/vx-home/ingress/*.yaml` - Add TLS annotations and spec
5. `docs/15-cert-manager.md` - Comprehensive guide
6. `docs/INSTALLATION-WALKTHROUGH.md` - Add Step 5 for cert-manager
7. `docs/90-troubleshooting.md` - Add cert-manager issues section

**Never leave partial updates** - the installation flow depends on consistency across all locations.

### 4. Version Tracking

**When updating container images:**

1. Document the version change in git commit message
2. Update any version references in documentation
3. Test the new version before committing
4. Note any breaking changes in README or relevant doc

**Current versions (as of 2025-12-22):**
- MicroK8s: 1.32/stable channel
- Open WebUI: v0.6.42
- Postgres (pgvector): pg16
- Redis: 8-alpine
- Kokoro: v0.2.4
- Faster-Whisper: latest-cpu
- pgAdmin: latest

### 5. Common Improvements Needed

As you work through installation, you may discover:

#### Installation Issues

- **SELinux problems** → Update `scripts/setup/01-selinux-config.sh` and `docs/10-microk8s-install.md`
- **Firewall issues** → Update `scripts/setup/07-configure-firewall.sh`
- **Permission problems** → Document in troubleshooting guide
- **Missing dependencies** → Add to prerequisite checks in scripts

#### Configuration Issues

- **Wrong environment variables** → Update manifest YAML files AND secrets.example.yaml
- **Incorrect service URLs** → Check Ingress configs, update docs
- **Database connection problems** → Update DATABASE_URL format in manifests and docs
- **Port mismatches** → Verify Service targetPort matches container port

#### Documentation Gaps

- **Unclear steps** → Rewrite for clarity, add examples
- **Missing explanations** → Add "Why this matters" sections
- **Broken links** → Fix all internal doc references
- **Outdated screenshots** → Remove or update (prefer text instructions)

### 6. Testing Changes

**Before committing changes:**

1. Test on a clean MicroK8s installation (if possible)
2. Verify all links in documentation work
3. Run through quickstart guide end-to-end
4. Check that admin scripts work (`./scripts/vx-admin.sh`)
5. Validate YAML syntax: `kubectl kustomize k8s/clusters/vx-home`

### 7. Kubernetes Manifest Updates

**When modifying manifests:**

- Maintain consistent labeling (`app.kubernetes.io/*`)
- Keep resource requests/limits reasonable
- Test with `kubectl apply --dry-run=client`
- Verify Kustomize references are correct
- Document any new ConfigMaps or Secrets needed

### 8. Script Improvements

**When improving scripts:**

- Maintain colored output for readability
- Add error checking (`set -euo pipefail`)
- Provide clear success/failure messages
- Include "Next steps" guidance at end
- Make scripts idempotent (safe to run multiple times)

### 9. Security Updates

**If security issues are found:**

1. **Immediate** - Create issue/document the problem
2. Update affected configuration
3. Add to security section of relevant docs
4. Consider adding to `docs/90-troubleshooting.md`
5. Update `.gitignore` if secrets were exposed

### 10. Learning Notes for CKA Students

**When adding content for CKA learners:**

- Explain the "why" not just the "what"
- Compare alternatives (e.g., Deployment vs StatefulSet)
- Reference official Kubernetes documentation
- Add "CKA Learning Point" callouts
- Include troubleshooting workflows

### 11. Terraform Migration Notes

**As Terraform code is added:**

- Keep Kustomize manifests in sync initially
- Document migration path in `docs/50-terraform-future.md`
- Update admin scripts to support both approaches
- Maintain backwards compatibility during transition

## Quick Reference: File Locations

### Documentation
- Main README: `README.md`
- Installation guide: `docs/10-microk8s-install.md`
- AI stack config: `docs/30-ai-stack-openwebui.md`
- Troubleshooting: `docs/90-troubleshooting.md`

### Kubernetes Manifests
- Namespace: `k8s/clusters/vx-home/namespace-ai.yaml`
- Secrets template: `k8s/clusters/vx-home/apps/ai-stack/secrets.example.yaml`
- Individual components: `k8s/clusters/vx-home/apps/ai-stack/<component>/`
- Ingress: `k8s/clusters/vx-home/ingress/`
- Main Kustomize: `k8s/clusters/vx-home/kustomization.yaml`

### Scripts
- Interactive menu: `scripts/vx-admin.sh`
- Setup scripts (run once): `scripts/setup/`
- Admin scripts (day-to-day): `scripts/admin/`
- Shared functions: `scripts/lib/common.sh`
- SELinux config (critical): `scripts/setup/01-selinux-config.sh`

### Configuration
- Gitignore: `.gitignore` (never commit secrets!)

## Common Tasks

### Adding a New Service

1. Create directory: `k8s/clusters/vx-home/apps/ai-stack/<service>/`
2. Add manifests: deployment.yaml, service.yaml, (optional) configmap.yaml
3. Update `k8s/clusters/vx-home/apps/ai-stack/kustomization.yaml`
4. Add admin scripts if needed
5. Document in `docs/30-ai-stack-openwebui.md` or create new doc
6. Update main README.md with new service
7. Test deployment

### Fixing a Broken Installation Step

1. Identify which doc/script has the issue
2. Fix the doc/script
3. Test the fix
4. Update related documentation
5. Add to troubleshooting guide if it's a common issue
6. Commit with clear message: "Fix: <brief description>"

### Updating a Container Image

1. Find all references to the image (grep is your friend)
2. Update image tags in manifests
3. Update version documentation
4. Test the new image
5. Document any new env vars or breaking changes
6. Update this file's version tracking section

## Git Commit Message Format

Use clear, descriptive commit messages:

```
Type: Brief description (50 chars max)

Longer explanation if needed (wrap at 72 chars).

- Specific changes made
- Why the change was needed
- Any breaking changes

Refs: #issue-number (if applicable)
```

**Types:**
- `Fix:` - Bug fixes
- `Add:` - New features
- `Update:` - Updates to existing features
- `Docs:` - Documentation changes
- `Refactor:` - Code restructuring
- `Test:` - Testing improvements

**IMPORTANT - No AI Attribution Lines:**
- Do NOT add lines like "Generated with Claude Code" or similar
- Do NOT add "Co-Authored-By: Claude" or any AI co-author attribution
- Do NOT add emoji signatures (🤖) or AI-related footers
- Keep commit messages clean and professional
- This applies to commits, code comments, and documentation

## Known Issues / TODOs

### Current (as of 2025-12-22)

- [x] DATABASE_URL is now generated by `scripts/admin/secrets.sh create`
- [ ] Test path-based routing for pgAdmin at control.adm.vx.home/pgadmin
- [ ] Verify IngressClass name matches MicroK8s default
- [ ] Add health check endpoints verification to admin scripts
- [ ] Consider adding metrics-server by default for `kubectl top`

### Future Enhancements

- [ ] GPU enablement guide with specific A2 instructions
- [ ] Terraform modules implementation
- [ ] Multi-node scaling documentation
- [ ] Backup/restore procedures
- [ ] Monitoring stack (Prometheus/Grafana) integration
- [ ] Network policies for pod-to-pod security

## Contact / Support

For issues with this repository:
- Check `docs/90-troubleshooting.md` first
- Review git commit history for recent changes
- Open an issue in the repository (if using GitHub/GitLab)
- Refer to official documentation links in docs/

## Final Notes

**Remember:** This is a learning environment and homelab. It's okay to experiment, break things, and rebuild. The goal is to learn Kubernetes deeply while building something useful.

**Documentation debt is real debt:** Don't let it accumulate. Fix it as you go.

**Future you will thank present you:** Write clear docs, use descriptive names, add comments where logic isn't obvious.

---

Last updated: 2025-12-23
Maintainer: VX Home Infrastructure Project
License: MIT (or specify your license)
