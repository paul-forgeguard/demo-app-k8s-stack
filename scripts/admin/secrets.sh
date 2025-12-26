#!/usr/bin/env bash
#
# Script: secrets.sh
# Purpose: Manage secrets for the AI stack
# Usage: ./secrets.sh [create|show-url|edit]
#

set -euo pipefail

# Source common functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

# Secrets file paths
SECRETS_EXAMPLE="$K8S_DIR/apps/ai-stack/secrets.example.yaml"
SECRETS_FILE="$K8S_DIR/apps/ai-stack/secrets.yaml"

# ============================================================================
# HELP
# ============================================================================

show_help() {
    print_usage_header "./scripts/admin/secrets.sh" "Manage secrets for the AI stack"

    echo -e "${BOLD}Commands:${NC}"
    echo "  create          Create secrets.yaml from template"
    echo "  show-url        Display DATABASE_URL format with current password"
    echo "  edit            Open secrets.yaml in editor"
    echo "  check           Verify secrets file exists and is valid"
    echo ""

    print_common_options

    echo -e "${BOLD}Examples:${NC}"
    echo "  ./scripts/admin/secrets.sh create"
    echo "  ./scripts/admin/secrets.sh show-url"
    echo "  ./scripts/admin/secrets.sh edit"
    echo ""
}

# ============================================================================
# FUNCTIONS
# ============================================================================

do_create() {
    log_step "Creating secrets.yaml from template..."
    echo ""

    # Check if template exists
    if [[ ! -f "$SECRETS_EXAMPLE" ]]; then
        log_error "Template file not found: $SECRETS_EXAMPLE"
        exit 1
    fi

    # Check if secrets already exist
    if [[ -f "$SECRETS_FILE" ]]; then
        log_warn "secrets.yaml already exists!"
        echo "  Location: $SECRETS_FILE"
        echo ""
        if ! confirm_action "Overwrite existing secrets?"; then
            log_info "Keeping existing secrets.yaml"
            exit 0
        fi
    fi

    # Copy template
    cp "$SECRETS_EXAMPLE" "$SECRETS_FILE"
    log_success "Created: $SECRETS_FILE"
    echo ""

    # Generate passwords
    print_header "Generated Strong Passwords"
    echo ""
    echo "Copy these passwords and update secrets.yaml:"
    echo ""
    echo "POSTGRES_PASSWORD:"
    echo "  $(openssl rand -base64 24)"
    echo ""
    echo "PGADMIN_DEFAULT_PASSWORD:"
    echo "  $(openssl rand -base64 24)"
    echo ""

    print_header "Required Updates"
    echo ""
    echo "Edit secrets.yaml and update these values:"
    echo ""
    echo "  1. POSTGRES_PASSWORD     - Use the generated password above"
    echo "  2. DATABASE_URL          - Include the same password"
    echo "  3. PGADMIN_DEFAULT_PASSWORD - Use the generated password"
    echo "  4. OPENAI_API_KEY        - Your key from platform.openai.com"
    echo ""

    log_info "Edit now with:"
    echo "  ./scripts/admin/secrets.sh edit"
    echo ""
    log_info "Or manually with:"
    echo "  vim $SECRETS_FILE"
    echo ""

    log_warn "SECURITY: secrets.yaml is gitignored and should NEVER be committed!"
}

do_show_url() {
    log_step "Generating DATABASE_URL..."
    echo ""

    if [[ ! -f "$SECRETS_FILE" ]]; then
        log_error "secrets.yaml not found!"
        echo ""
        log_info "Create it first with:"
        echo "  ./scripts/admin/secrets.sh create"
        exit 1
    fi

    # Extract password
    local pg_pass
    pg_pass=$(grep POSTGRES_PASSWORD "$SECRETS_FILE" 2>/dev/null | awk '{print $2}' | tr -d '"' || echo "")

    if [[ -z "$pg_pass" ]]; then
        log_error "Could not find POSTGRES_PASSWORD in secrets.yaml"
        exit 1
    fi

    echo "Your DATABASE_URL should be:"
    echo ""
    echo "  postgresql://openwebui:${pg_pass}@pgvector:5432/openwebui"
    echo ""
    log_info "Add this to your secrets.yaml under stringData:"
    echo ""
    echo "stringData:"
    echo "  DATABASE_URL: \"postgresql://openwebui:${pg_pass}@pgvector:5432/openwebui\""
    echo ""
}

do_edit() {
    if [[ ! -f "$SECRETS_FILE" ]]; then
        log_error "secrets.yaml not found!"
        echo ""
        log_info "Create it first with:"
        echo "  ./scripts/admin/secrets.sh create"
        exit 1
    fi

    # Find editor
    local editor="${EDITOR:-vim}"
    if ! command -v "$editor" &>/dev/null; then
        editor="nano"
        if ! command -v "$editor" &>/dev/null; then
            editor="vi"
        fi
    fi

    log_info "Opening secrets.yaml with: $editor"
    $editor "$SECRETS_FILE"
}

do_check() {
    log_step "Checking secrets configuration..."
    echo ""

    if [[ ! -f "$SECRETS_FILE" ]]; then
        log_error "secrets.yaml not found!"
        echo "  Expected: $SECRETS_FILE"
        echo ""
        log_info "Create it with: ./scripts/admin/secrets.sh create"
        exit 1
    fi

    log_success "secrets.yaml exists"

    # Check for placeholder values
    local issues=0

    if grep -q "CHANGE_ME" "$SECRETS_FILE" 2>/dev/null; then
        log_warn "Found 'CHANGE_ME' placeholder - update required"
        ((issues++))
    fi

    if grep -q "YOUR_.*_HERE" "$SECRETS_FILE" 2>/dev/null; then
        log_warn "Found placeholder values - update required"
        ((issues++))
    fi

    if grep -q "sk-YOUR" "$SECRETS_FILE" 2>/dev/null; then
        log_warn "OpenAI API key not configured"
        ((issues++))
    fi

    # Check git status
    echo ""
    if git ls-files --error-unmatch "$SECRETS_FILE" &>/dev/null; then
        log_error "SECURITY ISSUE: secrets.yaml is tracked by git!"
        log_error "Add to .gitignore immediately!"
        ((issues++))
    else
        log_success "secrets.yaml is NOT tracked by git (correct)"
    fi

    echo ""
    if [[ $issues -eq 0 ]]; then
        log_success "Secrets configuration looks good!"
    else
        log_warn "$issues issue(s) found - review secrets.yaml"
    fi
}

# ============================================================================
# MAIN
# ============================================================================

main() {
    local command="${1:-}"

    # Parse common args
    parse_common_args "$@" || {
        if [[ $? -eq 2 ]]; then
            show_help
            exit 0
        fi
    }

    case "$command" in
        create)
            do_create
            ;;
        show-url|url)
            do_show_url
            ;;
        edit)
            do_edit
            ;;
        check|verify)
            do_check
            ;;
        -h|--help|help|"")
            show_help
            ;;
        *)
            log_error "Unknown command: $command"
            show_help
            exit 1
            ;;
    esac
}

main "$@"
