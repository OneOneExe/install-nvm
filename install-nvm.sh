#!/bin/bash
# install-nvm.sh
# Entry point for the install-nvm project
# Sources the modules and runs the NVM installation
#
# Usage:
#   ./install-nvm.sh              — standard install
#   ./install-nvm.sh --help       — help
#   ./install-nvm.sh --debug      — with debug output
#   ./install-nvm.sh --dry-run    — checks only, no install
#   ./install-nvm.sh --force      — reinstall even if NVM exists
#
# Module load order:
#   logger.sh → manifest.sh → checks.sh → installer.sh

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
FORCE=false

print_help() {
    cat <<EOF
install-nvm.sh — install NVM (Node Version Manager)

Usage:
  ./install-nvm.sh [options]

Options:
  --help, -h      Show this help
  --debug         Enable debug output (LOG_LEVEL=DEBUG)
  --dry-run       Run checks only, no installation
  --force         Reinstall NVM even if it is already installed
                  Existing Node.js versions are preserved

Examples:
  ./install-nvm.sh                    # standard install
  ./install-nvm.sh --dry-run          # checks only
  ./install-nvm.sh --debug            # with debug output
  ./install-nvm.sh --force            # reinstall
  ./install-nvm.sh --dry-run --debug  # checks + debug

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
        --force)
            FORCE=true
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

# Override FORCE from command-line arguments
if [ "$FORCE" = true ]; then
    export FORCE=true
else
    export FORCE="${FORCE:-false}"
fi

# ============================================================
# Load modules
# Order matters: logger → manifest → checks → installer
# ============================================================
LIB_DIR="${SCRIPT_DIR}/lib"

# Verify all modules are present
for module in logger.sh manifest.sh checks.sh installer.sh; do
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
source "${LIB_DIR}/installer.sh"

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
    log_info "install-nvm.sh — start"
    log_info "Project directory: $SCRIPT_DIR"
    log_info "Log level: $LOG_LEVEL"

    if [ "$FORCE" = true ]; then
        log_warn "--force mode: reinstall allowed"
    fi

    if [ "$DRY_RUN" = true ]; then
        log_warn "--dry-run mode: installation will not run"
    fi

    # --- Step 1: Checks ---
    if ! run_all_checks; then
        log_error "Checks failed. Installation aborted."
        log_info "Hint: if NVM is already installed and you want to reinstall —"
        log_info "      run: ./install-nvm.sh --force"
        close_logger 1
        return 1
    fi

    # --- Step 2: Installation (skipped in dry-run) ---
    if [ "$DRY_RUN" = true ]; then
        log_info "Checks passed. Installation skipped (--dry-run)."
        log_info "Log: $(get_log_file)"
        close_logger 0
        return 0
    fi

    if ! run_installation; then
        log_error "Installation failed."
        log_info "See log: $(get_log_file)"
        close_logger 1
        return 1
    fi

    # --- Step 3: Final instructions ---
    log_separator
    log_success "Installation completed successfully"
    log_info "Log: $(get_log_file)"

    show_next_steps

    close_logger 0
    return 0
}

# ============================================================
# Run
# ============================================================
main "$@"
exit $?