#!/bin/bash
# tests/verify-uninstall.sh
# Post-uninstall verification for NVM
# Run AFTER uninstall-nvm.sh
#
# Depends on: config/nvm.conf, lib/logger.sh
#
# What it checks:
#   • ~/.nvm is removed
#   • nvm.sh is removed
#   • install-nvm block is removed from ~/.bashrc
#   • NVM_DIR is removed from ~/.bashrc
#   • NPM_CONFIG_PREFIX is removed from ~/.bashrc
#   • prefix is removed from ~/.npmrc
#   • nvm is not available in PATH
#   • node is not available in PATH
#   • Manifest is removed
#   • PATH is free of .nvm
#   • Backups exist
#
# Usage:
#   ./tests/verify-uninstall.sh
#   ./tests/verify-uninstall.sh --debug
#   ./tests/verify-uninstall.sh --keep-node    # if uninstall was run with --keep-node
#   ./tests/verify-uninstall.sh --keep-bashrc  # if uninstall was run with --keep-bashrc

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
EXPECT_KEEP_NODE=false
EXPECT_KEEP_BASHRC=false

while [ $# -gt 0 ]; do
    case "$1" in
        --help|-h)
            cat <<EOF
tests/verify-uninstall.sh — verify NVM uninstall

Usage:
  ./tests/verify-uninstall.sh [options]

Options:
  --help, -h        Show this help
  --debug           Enable debug output
  --keep-node       Verify with --keep-node (Node.js versions preserved)
  --keep-bashrc     Verify with --keep-bashrc (~/.bashrc not touched)

Checks:
  • ~/.nvm is removed (or empty with --keep-node)
  • nvm.sh is removed
  • Block # >>> install-nvm >>> is removed from ~/.bashrc
  • NVM_DIR is removed from ~/.bashrc
  • NPM_CONFIG_PREFIX is removed from ~/.bashrc
  • prefix is removed from ~/.npmrc
  • nvm is not available in PATH
  • node is not available in PATH
  • Manifest is removed
  • PATH is free of .nvm
  • Backups exist

Exit codes:
  0 — all checks passed
  1 — one or more checks failed
EOF
            exit 0
            ;;
        --debug)
            DEBUG=true
            shift
            ;;
        --keep-node)
            EXPECT_KEEP_NODE=true
            shift
            ;;
        --keep-bashrc)
            EXPECT_KEEP_BASHRC=true
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
# Check 1: ~/.nvm removed
# ============================================================
check_nvm_dir_removed() {
    log_info "--- Check 1: ~/.nvm removed ---"

    if [ ! -d "$NVM_DIR" ]; then
        pass "~/.nvm does not exist"
        return 0
    fi

    # With --keep-node, ~/.nvm may remain with versions
    if [ "$EXPECT_KEEP_NODE" = true ]; then
        if [ -d "$NVM_DIR/versions/node" ]; then
            local count
            count=$(find "$NVM_DIR/versions/node" -maxdepth 1 -mindepth 1 -type d 2>/dev/null | wc -l)
            warn "~/.nvm exists (--keep-node): $count versions preserved"
            return 0
        fi
    fi

    fail "~/.nvm still exists: $NVM_DIR"

    # Show what remains
    local content
    content=$(ls -A "$NVM_DIR" 2>/dev/null | head -10)
    if [ -n "$content" ]; then
        warn "Contents of ~/.nvm:"
        echo "$content" | while read -r line; do
            warn "  $line"
        done
    fi

    return 1
}

# ============================================================
# Check 2: nvm.sh removed
# ============================================================
check_nvm_sh_removed() {
    log_info "--- Check 2: nvm.sh removed ---"

    if [ ! -f "$NVM_DIR/nvm.sh" ]; then
        pass "~/.nvm/nvm.sh does not exist"
        return 0
    fi

    fail "~/.nvm/nvm.sh still exists"
    return 1
}

# ============================================================
# Check 3: install-nvm block in ~/.bashrc
# ============================================================
check_bashrc_block_removed() {
    log_info "--- Check 3: install-nvm block in ~/.bashrc ---"

    if [ "$EXPECT_KEEP_BASHRC" = true ]; then
        warn "Skipped (--keep-bashrc)"
        return 0
    fi

    local bashrc="$HOME/.bashrc"

    if [ ! -f "$bashrc" ]; then
        pass "~/.bashrc does not exist"
        return 0
    fi

    if grep -q ">>> install-nvm >>>" "$bashrc"; then
        fail "install-nvm block still in ~/.bashrc"
        return 1
    fi

    pass "install-nvm block removed from ~/.bashrc"
    return 0
}

# ============================================================
# Check 4: NVM_DIR in ~/.bashrc
# ============================================================
check_bashrc_nvm_dir_removed() {
    log_info "--- Check 4: NVM_DIR in ~/.bashrc ---"

    if [ "$EXPECT_KEEP_BASHRC" = true ]; then
        warn "Skipped (--keep-bashrc)"
        return 0
    fi

    local bashrc="$HOME/.bashrc"

    if [ ! -f "$bashrc" ]; then
        pass "~/.bashrc does not exist"
        return 0
    fi

    if grep -q "NVM_DIR" "$bashrc"; then
        fail "NVM_DIR still in ~/.bashrc"
        warn "Found lines:"
        grep -n "NVM_DIR" "$bashrc" | while read -r line; do
            warn "  $line"
        done
        return 1
    fi

    pass "NVM_DIR removed from ~/.bashrc"
    return 0
}

# ============================================================
# Check 5: NPM_CONFIG_PREFIX in ~/.bashrc
# ============================================================
check_bashrc_npm_prefix_removed() {
    log_info "--- Check 5: NPM_CONFIG_PREFIX in ~/.bashrc ---"

    if [ "$EXPECT_KEEP_BASHRC" = true ]; then
        warn "Skipped (--keep-bashrc)"
        return 0
    fi

    local bashrc="$HOME/.bashrc"

    if [ ! -f "$bashrc" ]; then
        pass "~/.bashrc does not exist"
        return 0
    fi

    if grep -q "NPM_CONFIG_PREFIX" "$bashrc"; then
        fail "NPM_CONFIG_PREFIX still in ~/.bashrc"
        return 1
    fi

    pass "NPM_CONFIG_PREFIX removed from ~/.bashrc"
    return 0
}

# ============================================================
# Check 6: prefix in ~/.npmrc
# ============================================================
check_npmrc_prefix_removed() {
    log_info "--- Check 6: prefix in ~/.npmrc ---"

    local npmrc="$HOME/.npmrc"

    if [ ! -f "$npmrc" ]; then
        pass "~/.npmrc does not exist"
        return 0
    fi

    if grep -qE '^[[:space:]]*prefix[[:space:]]*=' "$npmrc"; then
        fail "prefix still in ~/.npmrc"
        return 1
    fi

    pass "prefix removed from ~/.npmrc"
    return 0
}

# ============================================================
# Check 7: nvm not available in PATH
# ============================================================
check_nvm_not_in_path() {
    log_info "--- Check 7: nvm not available in PATH ---"

    # Check in a NEW bash session
    if bash -c 'command -v nvm' &>/dev/null; then
        fail "nvm is still available in a new session"
        warn "~/.bashrc may not have been reloaded"
        return 1
    fi

    pass "nvm is not available in a new session"
    return 0
}

# ============================================================
# Check 8: node not available in PATH
# ============================================================
check_node_not_in_path() {
    log_info "--- Check 8: node not available in PATH ---"

    if bash -c 'command -v node' &>/dev/null; then
        local node_path
        node_path=$(bash -c 'command -v node')
        fail "node is still available: $node_path"

        if [[ "$node_path" != *".nvm"* ]]; then
            warn "node is not from NVM — possibly a system Node.js"
        fi
        return 1
    fi

    pass "node is not available in a new session"
    return 0
}

# ============================================================
# Check 9: manifest removed
# ============================================================
check_manifest_removed() {
    log_info "--- Check 9: manifest removed ---"

    local manifest="$NVM_DIR/.install-nvm-manifest"

    if [ ! -f "$manifest" ]; then
        pass "Manifest does not exist"
        return 0
    fi

    if [ "$EXPECT_KEEP_NODE" = true ]; then
        warn "Manifest still exists (--keep-node)"
        return 0
    fi

    fail "Manifest still exists: $manifest"
    return 1
}

# ============================================================
# Check 10: PATH free of NVM_DIR
# ============================================================
check_path_clean() {
    log_info "--- Check 10: PATH free of NVM_DIR ---"

    local new_path
    new_path=$(bash -c 'echo $PATH')

    if [[ "$new_path" == *".nvm"* ]]; then
        warn "PATH in a new session contains .nvm"
        warn "You may need to restart the terminal"
        return 0
    fi

    pass "PATH in a new session is free of .nvm"
    return 0
}

# ============================================================
# Check 11: Backups exist
# ============================================================
check_backups_exist() {
    log_info "--- Check 11: backups ---"

    local backup_count
    backup_count=$(find "$HOME" -maxdepth 1 -name ".bashrc.bak.uninstall.*" 2>/dev/null | wc -l)

    if [ "$backup_count" -gt 0 ]; then
        pass "Found ~/.bashrc backups: $backup_count"
        find "$HOME" -maxdepth 1 -name ".bashrc.bak.uninstall.*" 2>/dev/null | while read -r line; do
            log_info "  $line"
        done
    else
        warn "No ~/.bashrc backups found"
    fi

    local npmrc_backup_count
    npmrc_backup_count=$(find "$HOME" -maxdepth 1 -name ".npmrc.bak.uninstall.*" 2>/dev/null | wc -l)

    if [ "$npmrc_backup_count" -gt 0 ]; then
        pass "Found ~/.npmrc backups: $npmrc_backup_count"
    fi

    return 0
}

# ============================================================
# Final report
# ============================================================
print_summary() {
    log_separator
    log_info "=== Uninstall verification summary ==="
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
        log_info "Possible causes:"
        log_info "  • Terminal was not restarted"
        log_info "  • Artifacts remain in ~/.nvm"
        log_info "  • Lines remain in ~/.bashrc"
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
    log_info "tests/verify-uninstall.sh — NVM uninstall verification"
    log_info "Project: $PROJECT_DIR"

    if [ "$EXPECT_KEEP_NODE" = true ]; then
        log_info "Mode: --keep-node (Node.js versions preserved)"
    fi
    if [ "$EXPECT_KEEP_BASHRC" = true ]; then
        log_info "Mode: --keep-bashrc (~/.bashrc not touched)"
    fi

    log_separator

    check_nvm_dir_removed
    check_nvm_sh_removed
    check_bashrc_block_removed
    check_bashrc_nvm_dir_removed
    check_bashrc_npm_prefix_removed
    check_npmrc_prefix_removed
    check_nvm_not_in_path
    check_node_not_in_path
    check_manifest_removed
    check_path_clean
    check_backups_exist

    print_summary
    local result=$?

    close_logger "$result"
    return "$result"
}

main "$@"
exit $?