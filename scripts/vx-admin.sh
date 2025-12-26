#!/usr/bin/env bash
#
# Script: vx-admin.sh
# Purpose: Master admin script for VX Home AI Stack
# Usage: ./vx-admin.sh [command] [subcommand] [args]
#
# Can be run interactively (no args) or with CLI arguments
#

set -euo pipefail

# Source common functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

# Script paths
ADMIN_DIR="$SCRIPT_DIR/admin"
SETUP_DIR="$SCRIPT_DIR/setup"
MICROK8S_DIR="$SCRIPT_DIR/microk8s"  # Legacy, will be moved to setup

# ============================================================================
# HELP
# ============================================================================

show_help() {
    echo ""
    echo -e "${BOLD}VX Home Admin - Command Reference${NC}"
    echo "════════════════════════════════════════════════════════════════════"
    echo ""
    echo -e "${BOLD}Usage:${NC}"
    echo "  ./vx-admin.sh                    # Interactive menu"
    echo "  ./vx-admin.sh <command> [args]   # Direct command"
    echo ""
    echo -e "${BOLD}Deployment Commands:${NC}"
    echo "  deploy apply              Deploy AI stack to Kubernetes"
    echo "  deploy delete             Remove AI stack from Kubernetes"
    echo "  deploy diff               Show pending changes"
    echo ""
    echo -e "${BOLD}Status Commands:${NC}"
    echo "  status                    Show full cluster status"
    echo "  status pods               Show pods only"
    echo "  status services           Show services only"
    echo "  status ingress            Show ingress only"
    echo "  status events             Show recent events"
    echo ""
    echo -e "${BOLD}Log Commands:${NC}"
    echo "  logs <app>                Stream logs for app"
    echo "  logs <app> --tail 100     Last 100 lines"
    echo "  logs <app> --previous     Previous container logs"
    echo ""
    echo -e "${BOLD}Restart Commands:${NC}"
    echo "  restart <app>             Restart an app"
    echo "  restart --all             Restart all apps"
    echo ""
    echo -e "${BOLD}Portainer Commands:${NC}"
    echo "  portainer install         Install Portainer CE"
    echo "  portainer uninstall       Remove Portainer"
    echo "  portainer status          Show Portainer status"
    echo ""
    echo -e "${BOLD}Secrets Commands:${NC}"
    echo "  secrets create            Create secrets.yaml"
    echo "  secrets show-url          Show DATABASE_URL"
    echo "  secrets check             Verify secrets exist"
    echo "  secrets edit              Edit secrets.yaml"
    echo ""
    echo -e "${BOLD}Database Commands:${NC}"
    echo "  init-pgvector             Initialize pgvector extension"
    echo ""
    echo -e "${BOLD}Testing Commands:${NC}"
    echo "  test                      Run all tests"
    echo "  test dns                  Test DNS resolution"
    echo "  test ingress              Test Ingress endpoints"
    echo "  test tls                  Test TLS certificates"
    echo ""
    echo -e "${BOLD}Maintenance Commands:${NC}"
    echo "  clean                     Clean failed/evicted pods"
    echo ""
    echo -e "${BOLD}Setup Commands (run once, as root):${NC}"
    echo "  setup list                List setup scripts"
    echo "  setup <script-number>     Run specific setup script"
    echo ""
    echo -e "${BOLD}Options:${NC}"
    echo "  -h, --help                Show this help"
    echo "  -v, --verbose             Enable verbose output"
    echo ""
    echo -e "${BOLD}Examples:${NC}"
    echo "  ./vx-admin.sh                        # Interactive menu"
    echo "  ./vx-admin.sh deploy apply           # Deploy stack"
    echo "  ./vx-admin.sh logs openwebui         # Stream logs"
    echo "  ./vx-admin.sh restart redis          # Restart Redis"
    echo "  ./vx-admin.sh test dns               # Test DNS"
    echo ""
}

# ============================================================================
# INTERACTIVE MENU FUNCTIONS
# ============================================================================

show_main_menu() {
    clear
    echo ""
    echo -e "${BOLD}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}║              VX Home Admin - Main Menu                         ║${NC}"
    echo -e "${BOLD}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "  ${CYAN}[1]${NC} Deploy/Manage AI Stack"
    echo -e "  ${CYAN}[2]${NC} View Status & Logs"
    echo -e "  ${CYAN}[3]${NC} Portainer Management"
    echo -e "  ${CYAN}[4]${NC} Secrets Management"
    echo -e "  ${CYAN}[5]${NC} Testing & Diagnostics"
    echo -e "  ${CYAN}[6]${NC} Maintenance"
    echo -e "  ${CYAN}[7]${NC} Initial Setup (run once)"
    echo ""
    echo -e "  ${DIM}[h]${NC} Help"
    echo -e "  ${DIM}[q]${NC} Quit"
    echo ""
    echo -n "  Select option: "
}

show_deploy_menu() {
    clear
    echo ""
    echo -e "${BOLD}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}║              Deploy/Manage AI Stack                            ║${NC}"
    echo -e "${BOLD}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "  ${CYAN}[1]${NC} Apply - Deploy AI stack to Kubernetes"
    echo -e "  ${CYAN}[2]${NC} Delete - Remove AI stack from Kubernetes"
    echo -e "  ${CYAN}[3]${NC} Diff - Show what would change"
    echo ""
    echo -e "  ${DIM}[b]${NC} Back to main menu"
    echo ""
    echo -n "  Select option: "
}

show_status_menu() {
    clear
    echo ""
    echo -e "${BOLD}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}║              View Status & Logs                                ║${NC}"
    echo -e "${BOLD}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "  ${CYAN}[1]${NC} Full Status - Show all resources"
    echo -e "  ${CYAN}[2]${NC} Pods - Show pod status"
    echo -e "  ${CYAN}[3]${NC} Services - Show services"
    echo -e "  ${CYAN}[4]${NC} Ingress - Show ingress routes"
    echo -e "  ${CYAN}[5]${NC} Events - Show recent events"
    echo -e "  ${CYAN}[6]${NC} Certificates - Show TLS certs"
    echo -e "  ${CYAN}[7]${NC} Logs - Stream app logs"
    echo ""
    echo -e "  ${DIM}[b]${NC} Back to main menu"
    echo ""
    echo -n "  Select option: "
}

show_portainer_menu() {
    clear
    echo ""
    echo -e "${BOLD}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}║              Portainer Management                              ║${NC}"
    echo -e "${BOLD}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "  ${CYAN}[1]${NC} Status - Show Portainer status"
    echo -e "  ${CYAN}[2]${NC} Install - Install Portainer CE"
    echo -e "  ${CYAN}[3]${NC} Uninstall - Remove Portainer"
    echo ""
    echo -e "  ${DIM}[b]${NC} Back to main menu"
    echo ""
    echo -n "  Select option: "
}

show_secrets_menu() {
    clear
    echo ""
    echo -e "${BOLD}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}║              Secrets Management                                ║${NC}"
    echo -e "${BOLD}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "  ${CYAN}[1]${NC} Check - Verify secrets exist in cluster"
    echo -e "  ${CYAN}[2]${NC} Create - Generate new secrets.yaml"
    echo -e "  ${CYAN}[3]${NC} Edit - Edit secrets.yaml"
    echo -e "  ${CYAN}[4]${NC} Show DATABASE_URL - Display connection string"
    echo ""
    echo -e "  ${DIM}[b]${NC} Back to main menu"
    echo ""
    echo -n "  Select option: "
}

show_testing_menu() {
    clear
    echo ""
    echo -e "${BOLD}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}║              Testing & Diagnostics                             ║${NC}"
    echo -e "${BOLD}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "  ${CYAN}[1]${NC} All Tests - Run all diagnostic tests"
    echo -e "  ${CYAN}[2]${NC} DNS - Test DNS resolution"
    echo -e "  ${CYAN}[3]${NC} Ingress - Test HTTP/HTTPS endpoints"
    echo -e "  ${CYAN}[4]${NC} TLS - Test certificates"
    echo ""
    echo -e "  ${DIM}[b]${NC} Back to main menu"
    echo ""
    echo -n "  Select option: "
}

show_maintenance_menu() {
    clear
    echo ""
    echo -e "${BOLD}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}║              Maintenance                                       ║${NC}"
    echo -e "${BOLD}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "  ${CYAN}[1]${NC} Clean - Remove failed/evicted pods"
    echo -e "  ${CYAN}[2]${NC} Restart App - Restart a specific app"
    echo -e "  ${CYAN}[3]${NC} Init pgvector - Initialize PostgreSQL extension"
    echo ""
    echo -e "  ${DIM}[b]${NC} Back to main menu"
    echo ""
    echo -n "  Select option: "
}

show_setup_menu() {
    clear
    echo ""
    echo -e "${BOLD}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}║              Initial Setup (run once, as root)                 ║${NC}"
    echo -e "${BOLD}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo ""

    # Check for setup scripts in both locations
    local setup_dir
    if [[ -d "$SETUP_DIR" ]]; then
        setup_dir="$SETUP_DIR"
    elif [[ -d "$MICROK8S_DIR" ]]; then
        setup_dir="$MICROK8S_DIR"
    else
        echo -e "  ${RED}No setup scripts found${NC}"
        echo ""
        echo -e "  ${DIM}[b]${NC} Back to main menu"
        echo ""
        echo -n "  Select option: "
        return
    fi

    echo -e "  ${YELLOW}Note: These scripts should be run as root (sudo)${NC}"
    echo ""

    # List setup scripts
    local i=1
    for script in "$setup_dir"/*.sh; do
        if [[ -f "$script" ]]; then
            local name
            name=$(basename "$script")
            echo -e "  ${CYAN}[$i]${NC} $name"
            ((i++))
        fi
    done

    echo ""
    echo -e "  ${DIM}[b]${NC} Back to main menu"
    echo ""
    echo -n "  Select option: "
}

select_app_interactive() {
    echo ""
    echo -e "${BOLD}Available Apps:${NC}"
    echo ""

    local apps=("openwebui" "pgvector" "redis" "pgadmin" "kokoro" "faster-whisper")
    local i=1
    for app in "${apps[@]}"; do
        echo -e "  ${CYAN}[$i]${NC} $app"
        ((i++))
    done

    echo ""
    echo -n "  Select app (1-${#apps[@]}): "
    read -r choice

    if [[ "$choice" =~ ^[1-6]$ ]]; then
        echo "${apps[$((choice-1))]}"
    else
        echo ""
    fi
}

press_enter_to_continue() {
    echo ""
    echo -n "  Press Enter to continue..."
    read -r
}

run_script() {
    local script="$1"
    shift

    if [[ -x "$script" ]]; then
        echo ""
        "$script" "$@"
    else
        log_error "Script not found or not executable: $script"
    fi
}

# ============================================================================
# INTERACTIVE MENU LOOPS
# ============================================================================

menu_deploy() {
    while true; do
        show_deploy_menu
        read -r choice
        case "$choice" in
            1) run_script "$ADMIN_DIR/deploy.sh" apply; press_enter_to_continue ;;
            2) run_script "$ADMIN_DIR/deploy.sh" delete; press_enter_to_continue ;;
            3) run_script "$ADMIN_DIR/deploy.sh" diff; press_enter_to_continue ;;
            b|B) return ;;
            *) ;;
        esac
    done
}

menu_status() {
    while true; do
        show_status_menu
        read -r choice
        case "$choice" in
            1) run_script "$ADMIN_DIR/status.sh"; press_enter_to_continue ;;
            2) run_script "$ADMIN_DIR/status.sh" pods; press_enter_to_continue ;;
            3) run_script "$ADMIN_DIR/status.sh" services; press_enter_to_continue ;;
            4) run_script "$ADMIN_DIR/status.sh" ingress; press_enter_to_continue ;;
            5) run_script "$ADMIN_DIR/status.sh" events; press_enter_to_continue ;;
            6) run_script "$ADMIN_DIR/status.sh" certificates; press_enter_to_continue ;;
            7)
                local app
                app=$(select_app_interactive)
                if [[ -n "$app" ]]; then
                    run_script "$ADMIN_DIR/logs.sh" "$app"
                fi
                press_enter_to_continue
                ;;
            b|B) return ;;
            *) ;;
        esac
    done
}

menu_portainer() {
    while true; do
        show_portainer_menu
        read -r choice
        case "$choice" in
            1) run_script "$ADMIN_DIR/portainer.sh" status; press_enter_to_continue ;;
            2) run_script "$ADMIN_DIR/portainer.sh" install; press_enter_to_continue ;;
            3) run_script "$ADMIN_DIR/portainer.sh" uninstall; press_enter_to_continue ;;
            b|B) return ;;
            *) ;;
        esac
    done
}

menu_secrets() {
    while true; do
        show_secrets_menu
        read -r choice
        case "$choice" in
            1) run_script "$ADMIN_DIR/secrets.sh" check; press_enter_to_continue ;;
            2) run_script "$ADMIN_DIR/secrets.sh" create; press_enter_to_continue ;;
            3) run_script "$ADMIN_DIR/secrets.sh" edit; press_enter_to_continue ;;
            4) run_script "$ADMIN_DIR/secrets.sh" show-url; press_enter_to_continue ;;
            b|B) return ;;
            *) ;;
        esac
    done
}

menu_testing() {
    while true; do
        show_testing_menu
        read -r choice
        case "$choice" in
            1) run_script "$ADMIN_DIR/test.sh" all; press_enter_to_continue ;;
            2) run_script "$ADMIN_DIR/test.sh" dns; press_enter_to_continue ;;
            3) run_script "$ADMIN_DIR/test.sh" ingress; press_enter_to_continue ;;
            4) run_script "$ADMIN_DIR/test.sh" tls; press_enter_to_continue ;;
            b|B) return ;;
            *) ;;
        esac
    done
}

menu_maintenance() {
    while true; do
        show_maintenance_menu
        read -r choice
        case "$choice" in
            1) run_script "$ADMIN_DIR/clean.sh"; press_enter_to_continue ;;
            2)
                local app
                app=$(select_app_interactive)
                if [[ -n "$app" ]]; then
                    run_script "$ADMIN_DIR/restart.sh" "$app"
                fi
                press_enter_to_continue
                ;;
            3) run_script "$ADMIN_DIR/init-pgvector.sh"; press_enter_to_continue ;;
            b|B) return ;;
            *) ;;
        esac
    done
}

menu_setup() {
    while true; do
        show_setup_menu
        read -r choice

        case "$choice" in
            b|B) return ;;
            [1-9]|[1-9][0-9])
                # Find setup directory
                local setup_dir
                if [[ -d "$SETUP_DIR" ]]; then
                    setup_dir="$SETUP_DIR"
                elif [[ -d "$MICROK8S_DIR" ]]; then
                    setup_dir="$MICROK8S_DIR"
                else
                    log_error "No setup scripts found"
                    press_enter_to_continue
                    continue
                fi

                # Get script by index
                local scripts=("$setup_dir"/*.sh)
                local idx=$((choice - 1))

                if [[ $idx -ge 0 ]] && [[ $idx -lt ${#scripts[@]} ]]; then
                    local script="${scripts[$idx]}"
                    if [[ -f "$script" ]]; then
                        echo ""
                        log_warn "This script should be run as root."
                        echo ""
                        echo "  Run: sudo $script"
                        echo ""
                        if confirm_action "Run this script now?"; then
                            if [[ $EUID -eq 0 ]]; then
                                run_script "$script"
                            else
                                sudo "$script"
                            fi
                        fi
                    fi
                else
                    log_error "Invalid selection"
                fi
                press_enter_to_continue
                ;;
            *) ;;
        esac
    done
}

run_interactive() {
    while true; do
        show_main_menu
        read -r choice
        case "$choice" in
            1) menu_deploy ;;
            2) menu_status ;;
            3) menu_portainer ;;
            4) menu_secrets ;;
            5) menu_testing ;;
            6) menu_maintenance ;;
            7) menu_setup ;;
            h|H) show_help; press_enter_to_continue ;;
            q|Q)
                echo ""
                log_info "Goodbye!"
                echo ""
                exit 0
                ;;
            *) ;;
        esac
    done
}

# ============================================================================
# CLI COMMAND HANDLING
# ============================================================================

handle_cli() {
    local command="${1:-}"
    shift || true

    case "$command" in
        deploy)
            run_script "$ADMIN_DIR/deploy.sh" "$@"
            ;;
        status)
            run_script "$ADMIN_DIR/status.sh" "$@"
            ;;
        logs)
            run_script "$ADMIN_DIR/logs.sh" "$@"
            ;;
        restart)
            run_script "$ADMIN_DIR/restart.sh" "$@"
            ;;
        portainer)
            run_script "$ADMIN_DIR/portainer.sh" "$@"
            ;;
        secrets)
            run_script "$ADMIN_DIR/secrets.sh" "$@"
            ;;
        init-pgvector)
            run_script "$ADMIN_DIR/init-pgvector.sh" "$@"
            ;;
        test)
            run_script "$ADMIN_DIR/test.sh" "$@"
            ;;
        clean)
            run_script "$ADMIN_DIR/clean.sh" "$@"
            ;;
        setup)
            local subcommand="${1:-list}"
            shift || true

            # Find setup directory
            local setup_dir
            if [[ -d "$SETUP_DIR" ]]; then
                setup_dir="$SETUP_DIR"
            elif [[ -d "$MICROK8S_DIR" ]]; then
                setup_dir="$MICROK8S_DIR"
            else
                log_error "No setup scripts found"
                exit 1
            fi

            case "$subcommand" in
                list)
                    echo ""
                    log_info "Available setup scripts:"
                    echo ""
                    for script in "$setup_dir"/*.sh; do
                        if [[ -f "$script" ]]; then
                            echo "  $(basename "$script")"
                        fi
                    done
                    echo ""
                    log_info "Run with: sudo $setup_dir/<script-name>"
                    ;;
                *)
                    # Try to find script by number or name
                    local script=""
                    if [[ "$subcommand" =~ ^[0-9]+$ ]]; then
                        # By number
                        local scripts=("$setup_dir"/*.sh)
                        local idx=$((subcommand - 1))
                        if [[ $idx -ge 0 ]] && [[ $idx -lt ${#scripts[@]} ]]; then
                            script="${scripts[$idx]}"
                        fi
                    else
                        # By name
                        script="$setup_dir/$subcommand"
                        if [[ ! -f "$script" ]]; then
                            # Try with .sh
                            script="$setup_dir/${subcommand}.sh"
                        fi
                    fi

                    if [[ -f "$script" ]]; then
                        log_warn "Running setup script: $(basename "$script")"
                        if [[ $EUID -eq 0 ]]; then
                            run_script "$script" "$@"
                        else
                            log_error "Setup scripts must be run as root"
                            echo ""
                            echo "  Run: sudo $script"
                            exit 1
                        fi
                    else
                        log_error "Setup script not found: $subcommand"
                        echo ""
                        log_info "Available scripts:"
                        for s in "$setup_dir"/*.sh; do
                            echo "  $(basename "$s")"
                        done
                        exit 1
                    fi
                    ;;
            esac
            ;;
        -h|--help|help)
            show_help
            ;;
        *)
            log_error "Unknown command: $command"
            echo ""
            show_help
            exit 1
            ;;
    esac
}

# ============================================================================
# MAIN
# ============================================================================

main() {
    # Handle verbose flag globally
    for arg in "$@"; do
        if [[ "$arg" == "-v" ]] || [[ "$arg" == "--verbose" ]]; then
            export VERBOSE=1
        fi
    done

    # No arguments = interactive mode
    if [[ $# -eq 0 ]]; then
        run_interactive
    else
        handle_cli "$@"
    fi
}

main "$@"
