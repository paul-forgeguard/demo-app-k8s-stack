#!/usr/bin/env bash
#
# Common functions library for VX Home scripts
# Source this file in other scripts: source "$(dirname "$0")/../lib/common.sh"
#

# Prevent multiple sourcing
[[ -n "${_VX_COMMON_LOADED:-}" ]] && return
_VX_COMMON_LOADED=1

# ============================================================================
# CONFIGURATION
# ============================================================================

# Project paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
K8S_DIR="$PROJECT_ROOT/k8s/clusters/vx-home"

# Namespace
AI_NAMESPACE="ai"

# Verbosity (set VX_VERBOSE=1 for debug output)
VERBOSE="${VX_VERBOSE:-0}"

# ============================================================================
# COLORS
# ============================================================================

# Check if stdout is a terminal (for color support)
if [[ -t 1 ]]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    CYAN='\033[0;36m'
    BOLD='\033[1m'
    DIM='\033[2m'
    NC='\033[0m'  # No Color
else
    RED=''
    GREEN=''
    YELLOW=''
    BLUE=''
    CYAN=''
    BOLD=''
    DIM=''
    NC=''
fi

# ============================================================================
# LOGGING FUNCTIONS
# ============================================================================

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

log_debug() {
    [[ "$VERBOSE" == "1" ]] && echo -e "${DIM}[DEBUG]${NC} $1"
}

log_step() {
    echo -e "${CYAN}[STEP]${NC} ${BOLD}$1${NC}"
}

log_success() {
    echo -e "${GREEN}[OK]${NC} $1"
}

# Print a header/section title
print_header() {
    local title="$1"
    local width=50
    echo ""
    echo -e "${BOLD}${title}${NC}"
    printf '%.0s─' $(seq 1 $width)
    echo ""
}

# Print a separator line
print_separator() {
    printf '%.0s─' $(seq 1 50)
    echo ""
}

# ============================================================================
# USER INTERACTION
# ============================================================================

# Confirm a dangerous action
# Usage: confirm_action "Delete all resources?" || exit 0
confirm_action() {
    local message="${1:-Are you sure?}"
    local default="${2:-n}"  # Default to no

    if [[ "$default" == "y" ]]; then
        read -p "$message (Y/n): " -n 1 -r
    else
        read -p "$message (y/N): " -n 1 -r
    fi
    echo

    if [[ "$default" == "y" ]]; then
        [[ ! $REPLY =~ ^[Nn]$ ]]
    else
        [[ $REPLY =~ ^[Yy]$ ]]
    fi
}

# Select from a list of options
# Usage: selected=$(select_option "Choose:" "option1" "option2" "option3")
select_option() {
    local prompt="$1"
    shift
    local options=("$@")

    echo -e "${BOLD}$prompt${NC}"
    for i in "${!options[@]}"; do
        echo "  [$((i+1))] ${options[$i]}"
    done

    while true; do
        read -p "Enter choice [1-${#options[@]}]: " choice
        if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#options[@]} )); then
            echo "${options[$((choice-1))]}"
            return 0
        fi
        log_error "Invalid choice. Please enter a number between 1 and ${#options[@]}"
    done
}

# ============================================================================
# KUBERNETES CHECKS
# ============================================================================

# Check if microk8s is available
check_microk8s_installed() {
    if ! command -v microk8s &> /dev/null; then
        log_error "MicroK8s is not installed"
        echo ""
        log_error "Install it with: sudo ./scripts/setup/03-install-microk8s.sh"
        return 1
    fi
    return 0
}

# Check if microk8s is running
check_microk8s_running() {
    check_microk8s_installed || return 1

    if ! microk8s status 2>/dev/null | grep -q "microk8s is running"; then
        log_error "MicroK8s is not running"
        echo ""
        log_error "Current status:"
        microk8s status 2>&1 | head -10 || true
        echo ""
        log_error "To start: microk8s start"
        return 1
    fi
    return 0
}

# Get the kubectl command (handles both microk8s kubectl and standalone kubectl)
get_kubectl() {
    if command -v microk8s &> /dev/null; then
        echo "microk8s kubectl"
    elif command -v kubectl &> /dev/null; then
        echo "kubectl"
    else
        log_error "Neither microk8s nor kubectl found"
        return 1
    fi
}

# Get the helm command
get_helm() {
    if command -v microk8s &> /dev/null && microk8s helm3 version &> /dev/null; then
        echo "microk8s helm3"
    elif command -v helm &> /dev/null; then
        echo "helm"
    else
        log_error "Neither microk8s helm3 nor helm found"
        return 1
    fi
}

# ============================================================================
# POD/APP HELPERS
# ============================================================================

# Available apps in the AI stack
AVAILABLE_APPS=("openwebui" "pgvector" "redis" "pgadmin" "kokoro" "faster-whisper" "control-portal-nginx")

# Check if app name is valid
is_valid_app() {
    local app="$1"
    for valid_app in "${AVAILABLE_APPS[@]}"; do
        [[ "$app" == "$valid_app" ]] && return 0
    done
    return 1
}

# Get pod name for an app
get_pod_name() {
    local app="$1"
    local kubectl
    kubectl=$(get_kubectl) || return 1

    $kubectl get pods -n "$AI_NAMESPACE" -l "app=$app" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null
}

# Show available apps with their status
show_available_apps() {
    local kubectl
    kubectl=$(get_kubectl) || return 1

    echo ""
    log_info "Available apps in '$AI_NAMESPACE' namespace:"
    echo ""
    printf "  %-20s %-10s %-8s\n" "APP" "STATUS" "READY"
    printf '  %.0s─' $(seq 1 40)
    echo ""

    for app in "${AVAILABLE_APPS[@]}"; do
        local status ready
        status=$($kubectl get pods -n "$AI_NAMESPACE" -l "app=$app" --no-headers 2>/dev/null | awk '{print $3}' | head -1)
        ready=$($kubectl get pods -n "$AI_NAMESPACE" -l "app=$app" --no-headers 2>/dev/null | awk '{print $2}' | head -1)

        if [[ -n "$status" ]]; then
            if [[ "$status" == "Running" ]]; then
                printf "  ${GREEN}%-20s${NC} %-10s %-8s\n" "$app" "$status" "$ready"
            else
                printf "  ${YELLOW}%-20s${NC} %-10s %-8s\n" "$app" "$status" "$ready"
            fi
        else
            printf "  ${DIM}%-20s${NC} %-10s %-8s\n" "$app" "Not found" "-"
        fi
    done
    echo ""
}

# ============================================================================
# ERROR HANDLING
# ============================================================================

# Die with error message
die() {
    log_error "$1"
    exit "${2:-1}"
}

# Check if a command exists
require_command() {
    local cmd="$1"
    local install_hint="${2:-}"

    if ! command -v "$cmd" &> /dev/null; then
        log_error "Required command not found: $cmd"
        [[ -n "$install_hint" ]] && echo "  Install with: $install_hint"
        return 1
    fi
    return 0
}

# ============================================================================
# HELP TEXT HELPERS
# ============================================================================

# Print script usage header
print_usage_header() {
    local script_name="$1"
    local description="$2"

    echo ""
    echo -e "${BOLD}Usage:${NC} $script_name [OPTIONS] <command>"
    echo ""
    echo "$description"
    echo ""
}

# Print common options
print_common_options() {
    echo -e "${BOLD}Options:${NC}"
    echo "  -h, --help      Show this help message"
    echo "  -v, --verbose   Enable verbose output"
    echo ""
}

# ============================================================================
# UTILITY FUNCTIONS
# ============================================================================

# Get the node IP address
get_node_ip() {
    hostname -I | awk '{print $1}'
}

# Check if running as root
is_root() {
    [[ "$EUID" -eq 0 ]]
}

# Require root privileges
require_root() {
    if ! is_root; then
        log_error "This script must be run with sudo or as root"
        exit 1
    fi
}

# Parse common arguments (-v, --verbose, -h, --help)
# Usage: parse_common_args "$@"
parse_common_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -v|--verbose)
                VERBOSE=1
                export VX_VERBOSE=1
                shift
                ;;
            -h|--help)
                return 2  # Special return code for "show help"
                ;;
            *)
                shift
                ;;
        esac
    done
    return 0
}
