#!/bin/bash
# tests/verify.sh
# Post-install verification for NVM
# Run separately: ./tests/verify.sh
#
# Depends on: config/nvm.conf, lib/logger.sh
#
# What it checks:
#   • NVM is installed and working
#   • Node.js is available (>= 20)
#   • npm is available
#   • ~/.npmrc does not contain a conflicting prefix
#   • NPM_CONFIG_PREFIX is absent
#   • PATH contains $NVM_DIR
#   • Default Node.js is set
#   • ~/.bashrc contains NVM_DIR
#   • List of installed Node.js versions
#
# Usage:
#   ./tests/verify.sh
#   ./tests/verify.sh --debug

set -o pipefail

# ============================================================
# Determine the project directory
# ============================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
readonly SCRIPT_DIR
readonly PROJECT_DIR

# ============================================================
# Argument parsing
# ============================================================
DEBUG=false

while [ $# -gt 0 ]; do
    case "$1" in
        --help|-h)
            cat <<EOF
tests/verify.sh — verify NVM installation

Usage:
  ./tests/verify.sh [options]

Options:
  --help, -h    Show this help
  --debug       Enable debug output

Checks:
  • NVM is installed and working
  • Node.js is available (>= 20)
  • npm is available
  • ~/.npmrc does not contain a conflicting prefix
  • NPM_CONFIG_PREFIX is absent
  • PATH contains \$NVM_DIR
  • Default Node.js is set
  • ~/.bashrc contains NVM_DIR
  • List of installed Node.js versions

Exit codes:
  0 — all checks passed (warnings possible)
  1 — one or more checks failed
EOF
            exit 0
            ;;
        --debug)
            DEBUG=true
            shift
            ;;
        *)
            echo "Unknown option: $1" >&2
            exit 2
            ;;
    esac
done

# ============================================================
# Load config and logger
# ============================================================
CONFIG_FILE="${PROJECT_DIR}/config/nvm.conf"
if [ ! -f "$CONFIG_FILE" ]; then
    echo "ERROR: not found: $CONFIG_FILE" >&2
    exit 1
fi
# shellcheck disable=SC1090
source "$CONFIG_FILE"

if [ "$DEBUG" = true ]; then
    LOG_LEVEL="DEBUG"
fi

LOGGER_FILE="${PROJECT_DIR}/lib/logger.sh"
if [ ! -f "$LOGGER_FILE" ]; then
    echo "ERROR: not found: $LOGGER_FILE" >&2
    exit 1
fi
# shellcheck disable=SC1091
source "$LOGGER_FILE"

# ============================================================
# Initialize the logger
# ============================================================
VERIFY_LOG_DIR="${PROJECT_DIR}/logs"
if ! init_logger "$VERIFY_LOG_DIR" "$LOG_LEVEL"; then
    echo "ERROR: failed to initialize logger" >&2
    exit 1
fi

# ============================================================
# Activate NVM (if not already active)
# nvm.sh is incompatible with pipefail and NPM_CONFIG_PREFIX
# ============================================================
activate_nvm_if_needed() {
    if command -v nvm &>/dev/null; then
        log_debug "NVM is already active"
        return 0
    fi

    export NVM_DIR
    if [ ! -s "$NVM_DIR/nvm.sh" ]; then
        log_debug "nvm.sh not found — cannot activate"
        return 0
    fi

    local old_pipefail
    old_pipefail=$(set -o | grep pipefail | awk '{print $2}')
    set +o pipefail

    local old_npm_prefix="${NPM_CONFIG_PREFIX:-}"
    if [ -n "$old_npm_prefix" ]; then
        unset NPM_CONFIG_PREFIX
    fi

    # shellcheck disable=SC1091
    \. "$NVM_DIR/nvm.sh"

    [ "$old_pipefail" = "on" ] && set -o pipefail

    log_debug "NVM activated from $NVM_DIR/nvm.sh"
}

# ============================================================
# Result counters
# ============================================================
PASSED=0
FAILED=0
WARNED=0

# ============================================================
# Helper functions for checks
# ============================================================
pass() {
    PASSED=$((PASSED + 1))
    log_success "✓ $1"
}

fail() {
    FAILED=$((FAILED + 1))
    log_error "✗ $1"
}

warn() {
    WARNED=$((WARNED + 1))
    log_warn "! $1"
}

# ============================================================
# Check 1: NVM installed
# ============================================================
check_nvm_installed() {
    log_info "--- Check 1: NVM installed ---"

    if [ ! -d "$NVM_DIR" ]; then
        fail "NVM directory not found: $NVM_DIR"
        return 1
    fi

    if [ ! -s "$NVM_DIR/nvm.sh" ]; then
        fail "Not found: $NVM_DIR/nvm.sh"
        return 1
    fi

    pass "NVM installed in $NVM_DIR"
    return 0
}

# ============================================================
# Check 2: NVM works
# ============================================================
check_nvm_works() {
    log_info "--- Check 2: NVM works ---"

    if ! command -v nvm &>/dev/null; then
        fail "nvm command not found in PATH"
        return 1
    fi

    local version
    version=$(nvm --version 2>/dev/null) || {
        fail "nvm does not respond to --version"
        return 1
    }

    pass "nvm --version → v${version}"
    return 0
}

# ============================================================
# Check 3: Node.js available
# ============================================================
check_node() {
    log_info "--- Check 3: Node.js available ---"

    if ! command -v node &>/dev/null; then
        fail "node command not found in PATH"
        return 1
    fi

    local version
    version=$(node -v 2>/dev/null) || {
        fail "node does not respond to -v"
        return 1
    }

    local major
    major=$(echo "$version" | sed 's/^v//' | cut -d. -f1)
    if [ "$major" -lt 20 ] 2>/dev/null; then
        warn "Node.js $version — older than 20, CLI may have issues"
    fi

    pass "node -v → ${version}"
    return 0
}

# ============================================================
# Check 4: npm available
# ============================================================
check_npm() {
    log_info "--- Check 4: npm available ---"

    if ! command -v npm &>/dev/null; then
        fail "npm command not found in PATH"
        return 1
    fi

    local version
    version=$(npm -v 2>/dev/null) || {
        fail "npm does not respond to -v"
        return 1
    }

    pass "npm -v → ${version}"
    return 0
}

# ============================================================
# Check 5: ~/.npmrc does not contain a conflicting prefix
# ============================================================
check_npmrc_no_prefix() {
    log_info "--- Check 5: ~/.npmrc free of prefix ---"

    local npmrc="$HOME/.npmrc"

    if [ ! -f "$npmrc" ]; then
        pass "~/.npmrc does not exist — no conflicts"
        return 0
    fi

    if grep -qE '^[[:space:]]*prefix[[:space:]]*=' "$npmrc"; then
        fail "prefix setting found in ~/.npmrc — conflict with NVM"
        warn "Remove the prefix line or run: npm config delete prefix"
        return 1
    fi

    pass "~/.npmrc does not contain prefix"
    return 0
}

# ============================================================
# Check 6: NPM_CONFIG_PREFIX is absent
# ============================================================
check_npm_config_prefix_absent() {
    log_info "--- Check 6: NPM_CONFIG_PREFIX absent ---"

    if [ -n "${NPM_CONFIG_PREFIX:-}" ]; then
        fail "NPM_CONFIG_PREFIX is set: $NPM_CONFIG_PREFIX"
        warn "NPM_CONFIG_PREFIX is incompatible with NVM"
        warn "Run: unset NPM_CONFIG_PREFIX"
        return 1
    fi

    local bashrc="$HOME/.bashrc"
    if [ -f "$bashrc" ] && grep -q "NPM_CONFIG_PREFIX" "$bashrc"; then
        fail "NPM_CONFIG_PREFIX found in ~/.bashrc — conflict with NVM"
        warn "Remove NPM_CONFIG_PREFIX lines from ~/.bashrc"
        return 1
    fi

    pass "NPM_CONFIG_PREFIX is not set (session + ~/.bashrc)"
    return 0
}

# ============================================================
# Check 7: PATH
# ============================================================
check_path() {
    log_info "--- Check 7: PATH ---"

    if [[ ":$PATH:" == *":${NVM_DIR}:"* ]] || [[ "$PATH" == *"${NVM_DIR}"* ]]; then
        pass "PATH contains \$NVM_DIR"
    else
        warn "PATH does not contain \$NVM_DIR"
        warn "In a new terminal nvm may be unavailable"
    fi

    if [[ ":$PATH:" == *":${HOME}/.npm-global/bin:"* ]]; then
        warn "PATH contains ~/.npm-global/bin — incompatible with NVM"
        warn "Remove from ~/.bashrc: export PATH=\"\$HOME/.npm-global/bin:\$PATH\""
    fi

    return 0
}

# ============================================================
# Check 8: Default Node.js
# ============================================================
check_default_node() {
    log_info "--- Check 8: Default Node.js ---"

    local raw_output
    raw_output=$(nvm alias default 2>/dev/null) || {
        fail "nvm alias default does not respond"
        return 1
    }

    local clean_output
    clean_output=$(strip_ansi "$raw_output")

    local default_alias
    default_alias=$(echo "$clean_output" | grep -oE 'lts/[a-z]+|v[0-9]+\.[0-9]+\.[0-9]+' | head -n 1)

    if [ -z "$default_alias" ]; then
        fail "Alias 'default' is not set"
        log_debug "Raw output of nvm alias default: $raw_output"
        return 1
    fi

    pass "nvm alias default → $default_alias"
    return 0
}

# ============================================================
# Check 9: ~/.bashrc is configured
# ============================================================
check_bashrc() {
    log_info "--- Check 9: ~/.bashrc configured ---"

    local bashrc="$HOME/.bashrc"
    if [ ! -f "$bashrc" ]; then
        warn "$bashrc not found"
        return 0
    fi

    if grep -q "NVM_DIR" "$bashrc"; then
        pass "~/.bashrc contains NVM_DIR"
    else
        warn "~/.bashrc does not contain NVM_DIR"
        warn "In a new terminal nvm may be unavailable"
    fi

    return 0
}

# ============================================================
# Check 10: Installed Node.js versions
# ============================================================
check_multiple_versions() {
    log_info "--- Check 10: Installed Node.js versions ---"

    local versions_dir="$NVM_DIR/versions/node"
    if [ ! -d "$versions_dir" ]; then
        warn "Versions directory not found: $versions_dir"
        return 0
    fi

    local count
    count=$(find "$versions_dir" -maxdepth 1 -mindepth 1 -type d 2>/dev/null | wc -l)

    if [ "$count" -eq 0 ]; then
        warn "No installed Node.js versions found"
        return 0
    fi

    local versions
    versions=$(find "$versions_dir" -maxdepth 1 -mindepth 1 -type d -printf '%f\n' 2>/dev/null | sort -V | tr '\n' ' ' | sed 's/ *$//')

    pass "Installed versions: $count ($versions)"
    return 0
}

# ============================================================
# Final report
# ============================================================
print_summary() {
    log_separator
    log_info "=== Verification summary ==="
    log_info "Passed:   $PASSED"
    if [ "$WARNED" -gt 0 ]; then
        log_warn "Warnings: $WARNED"
    fi
    if [ "$FAILED" -gt 0 ]; then
        log_error "Failed:  $FAILED"
    else
        log_info "Failed:  0"
    fi
    log_info "Log: $(get_log_file)"

    if [ "$FAILED" -gt 0 ]; then
        log_error "Verification FAILED"
        return 1
    fi

    if [ "$WARNED" -gt 0 ]; then
        log_warn "Verification passed with warnings"
        return 0
    fi

    log_success "All checks passed"
    return 0
}

# ============================================================
# Main
# ============================================================
main() {
    log_separator
    log_info "tests/verify.sh — NVM installation verification"
    log_info "Project: $PROJECT_DIR"
    log_separator

    activate_nvm_if_needed

    check_nvm_installed
    check_nvm_works
    check_node
    check_npm
    check_npmrc_no_prefix
    check_npm_config_prefix_absent
    check_path
    check_default_node
    check_bashrc
    check_multiple_versions

    print_summary
    local result=$?

    close_logger "$result"
    return "$result"
}

main "$@"
exit $?