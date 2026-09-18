#!/bin/bash
# uninstall-nvm.sh
# Entry point for the install-nvm project (uninstall)
# Reads the manifest and removes only what install-nvm created
#
# Usage:
#   ./uninstall-nvm.sh                # uninstall with confirmation
#   ./uninstall-nvm.sh --dry-run      # show plan, do not remove
#   ./uninstall-nvm.sh --yes          # no confirmation
#   ./uninstall-nvm.sh --keep-node    # keep Node.js versions
#   ./uninstall-nvm.sh --keep-bashrc  # leave ~/.bashrc untouched
#   ./uninstall-nvm.sh --purge        # remove everything, including ~/.npm-global and logs
#   ./uninstall-nvm.sh --help         # help
#   ./uninstall-nvm.sh --debug        # debug output

set -o pipefail

# ============================================================
# Determine the script directory
# ============================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR

# ============================================================
# Argument parsing
# ============================================================
DEBUG=false
DRY_RUN=false
UNINSTALL_YES=false
KEEP_NODE=false
KEEP_BASHRC=false
PURGE=false

print_help() {
    cat <<EOF
uninstall-nvm.sh — remove NVM and install-nvm traces

Usage:
  ./uninstall-nvm.sh [options]

Options:
  --help, -h        Show this help
  --debug           Enable debug output
  --dry-run         Show uninstall plan, do not remove anything
  --yes, -y         Do not ask for confirmation
  --keep-node       Keep Node.js versions in ~/.nvm/versions/
  --keep-bashrc     Leave ~/.bashrc untouched
  --purge           Remove everything, including ~/.npm-global and project logs

Examples:
  ./uninstall-nvm.sh                    # standard uninstall with confirmation
  ./uninstall-nvm.sh --dry-run          # show plan
  ./uninstall-nvm.sh --yes              # no confirmation
  ./uninstall-nvm.sh --keep-node        # keep Node.js versions
  ./uninstall-nvm.sh --purge --yes      # full cleanup

What is removed:
  • ~/.nvm/ (all files and directories from the manifest)
  • The block # >>> install-nvm >>> ... # <<< install-nvm <<< in ~/.bashrc
  • The prefix setting in ~/.npmrc (if present)
  • NPM_CONFIG_PREFIX in ~/.bashrc (if present)

What is NOT removed:
  • System packages (curl, git) — needed by others
  • ~/.npm-global — only with --purge
  • Project logs — only with --purge
  • Node.js versions — only with --keep-node

Safety:
  • A backup of ~/.bashrc is created before modification
  • A backup of ~/.npmrc is created before modification
  • Backups: *.bak.uninstall.YYYYMMDD_HHMMSS

Logs:
  Written to ${SCRIPT_DIR}/logs/

Documentation:
  ${SCRIPT_DIR}/README.md
  ${SCRIPT_DIR}/MOTIVATION.md
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        --help|-h)
            print_help
            exit 0
            ;;
        --debug)
            DEBUG=true
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --yes|-y)
            UNINSTALL_YES=true
            shift
            ;;
        --keep-node)
            KEEP_NODE=true
            shift
            ;;
        --keep-bashrc)
            KEEP_BASHRC=true
            shift
            ;;
        --purge)
            PURGE=true
            shift
            ;;
        *)
            echo "Unknown option: $1" >&2
            echo "Use --help for usage information." >&2
            exit 2
            ;;
    esac
done

# ============================================================
# Load configuration
# ============================================================
CONFIG_FILE="${SCRIPT_DIR}/config/nvm.conf"
if [ ! -f "$CONFIG_FILE" ]; then
    echo "ERROR: not found: $CONFIG_FILE" >&2
    exit 1
fi
# shellcheck disable=SC1090
source "$CONFIG_FILE"

# Override log level when --debug is given
if [ "$DEBUG" = true ]; then
    LOG_LEVEL="DEBUG"
fi

# ============================================================
# Export flags to modules
# ============================================================
export KEEP_NODE
export KEEP_BASHRC
export PURGE
export UNINSTALL_YES
export DRY_RUN

# ============================================================
# Load modules
# Order matters: logger → manifest → checks → uninstaller
# ============================================================
LIB_DIR="${SCRIPT_DIR}/lib"

# Verify all modules are present
for module in logger.sh manifest.sh checks.sh uninstaller.sh; do
    if [ ! -f "${LIB_DIR}/${module}" ]; then
        echo "ERROR: not found: ${LIB_DIR}/${module}" >&2
        exit 1
    fi
done

# Source in the correct order
# shellcheck disable=SC1091
source "${LIB_DIR}/logger.sh"

# shellcheck disable=SC1091
source "${LIB_DIR}/manifest.sh"

# shellcheck disable=SC1091
source "${LIB_DIR}/checks.sh"

# shellcheck disable=SC1091
source "${LIB_DIR}/uninstaller.sh"

# ============================================================
# Initialize the logger
# ============================================================
LOG_DIR_ABS="${SCRIPT_DIR}/${LOG_DIR#./}"
if ! init_logger "$LOG_DIR_ABS" "$LOG_LEVEL"; then
    echo "ERROR: failed to initialize logger" >&2
    exit 1
fi

# ============================================================
# Signal handling
# ============================================================
on_interrupt() {
    log_warn "Interrupted by user (Ctrl+C)"
    close_logger 130
    exit 130
}

on_error() {
    local exit_code=$?
    log_error "Script exited with an error (code: $exit_code)"
    close_logger "$exit_code"
    exit "$exit_code"
}

trap on_interrupt INT TERM
trap on_error ERR

# ============================================================
# Main logic
# ============================================================
main() {
    log_separator
    log_info "uninstall-nvm.sh — start"
    log_info "Project directory: $SCRIPT_DIR"
    log_info "Log level: $LOG_LEVEL"

    # Flags
    if [ "$DRY_RUN" = true ]; then
        log_warn "--dry-run mode: no removal will be performed"
    fi
    if [ "$UNINSTALL_YES" = true ]; then
        log_warn "--yes mode: no confirmation will be requested"
    fi
    if [ "$KEEP_NODE" = true ]; then
        log_warn "--keep-node mode: Node.js versions are preserved"
    fi
    if [ "$KEEP_BASHRC" = true ]; then
        log_warn "--keep-bashrc mode: ~/.bashrc is not touched"
    fi
    if [ "$PURGE" = true ]; then
        log_warn "--purge mode: ~/.npm-global and logs will be removed"
    fi

    # --- Verify that NVM is even installed ---
    if [ ! -d "$NVM_DIR" ]; then
        log_error "NVM not found: $NVM_DIR"
        log_info "Nothing to remove."
        close_logger 0
        return 0
    fi

    # --- Dry-run mode ---
    if [ "$DRY_RUN" = true ]; then
        log_info "Checking manifest"
        if check_manifest_exists; then
            show_uninstall_plan
        else
            log_warn "Manifest not found — plan unavailable"
            log_info "Fallback mode will be used"
        fi
        log_info "Log: $(get_log_file)"
        close_logger 0
        return 0
    fi

    # --- Actual uninstall ---
    if ! run_uninstallation; then
        log_error "Uninstall failed."
        log_info "See log: $(get_log_file)"
        close_logger 1
        return 1
    fi

    log_info "Log: $(get_log_file)"
    close_logger 0
    return 0
}

# ============================================================
# Run
# ============================================================
main "$@"
exit $?