#!/bin/bash
# lib/checks.sh
# Pre-install checks for NVM
# Depends on: lib/logger.sh, config/nvm.conf
#
# Changes:
#   - check_nvm_installed() respects the FORCE flag
#   - with FORCE=true, skips the stop when NVM is already installed

# Guard against re-sourcing
if [ -n "${_CHECKS_SH_LOADED:-}" ]; then
    return 0
fi
readonly _CHECKS_SH_LOADED=1

# ============================================================
# check_nvm_installed
# Checks whether NVM is already installed.
#
# Behavior:
#   - NVM not found → 0 (continue)
#   - NVM found + FORCE=true → 0 (continue, reinstall)
#   - NVM found + FORCE=false → 1 (stop)
#
# Returns:
#   0 — may continue
#   1 — must stop
# ============================================================
check_nvm_installed() {
    log_info "Checking for existing NVM installation"

    local force="${FORCE:-false}"

    if [ -d "$NVM_DIR" ]; then
        log_warn "NVM is already installed at $NVM_DIR"

        if [ -f "$NVM_DIR/nvm.sh" ]; then
            log_info "Found nvm.sh — installation appears functional"
        fi

        if [ "$force" = true ]; then
            log_warn "--force flag: continuing with reinstall"
            log_warn "Existing Node.js versions in $NVM_DIR/versions/node/ will be preserved"
            return 0
        fi

        log_warn "Reinstall not required. Use --force to reinstall."
        return 1
    fi

    # Check whether nvm is in PATH (e.g. from another location)
    if command -v nvm &>/dev/null; then
        local nvm_path
        nvm_path=$(command -v nvm)
        log_warn "nvm command found in PATH: $nvm_path"
        log_warn "But $NVM_DIR does not exist. Possible conflict."

        if [ "$force" = true ]; then
            log_warn "--force flag: continuing despite the conflict"
            return 0
        fi

        return 1
    fi

    log_info "NVM is not installed — may continue"
    return 0
}

# ============================================================
# check_node_conflicts
# Checks whether Node.js is installed from apt or snap.
# This may conflict with NVM.
# Returns:
#   0 — no conflicts
#   1 — conflict found
# ============================================================
check_node_conflicts() {
    log_info "Checking for conflicts with Node.js from apt/snap"

    local conflicts=()

    # Node.js from apt
    if dpkg -l 2>/dev/null | grep -q "^ii  nodejs "; then
        local node_apt_version
        node_apt_version=$(dpkg -l 2>/dev/null | grep "^ii  nodejs " | awk '{print $3}')
        conflicts+=("apt: nodejs ${node_apt_version}")
    fi

    # npm from apt
    if dpkg -l 2>/dev/null | grep -q "^ii  npm "; then
        local npm_apt_version
        npm_apt_version=$(dpkg -l 2>/dev/null | grep "^ii  npm " | awk '{print $3}')
        conflicts+=("apt: npm ${npm_apt_version}")
    fi

    # Node.js from snap
    if snap list 2>/dev/null | grep -q "^node "; then
        local node_snap_version
        node_snap_version=$(snap list 2>/dev/null | grep "^node " | awk '{print $2}')
        conflicts+=("snap: node ${node_snap_version}")
    fi

    # Check where node comes from in PATH
    if command -v node &>/dev/null; then
        local node_path
        node_path=$(command -v node)
        if [[ "$node_path" != *".nvm"* ]]; then
            conflicts+=("PATH: node → $node_path")
        fi
    fi

    if command -v npm &>/dev/null; then
        local npm_path
        npm_path=$(command -v npm)
        if [[ "$npm_path" != *".nvm"* ]]; then
            conflicts+=("PATH: npm → $npm_path")
        fi
    fi

    if [ ${#conflicts[@]} -eq 0 ]; then
        log_info "No conflicts found"
        return 0
    fi

    log_warn "Potential conflicts found:"
    local c
    for c in "${conflicts[@]}"; do
        log_warn "  • $c"
    done

    return 1
}

# ============================================================
# check_dependencies
# Checks for required packages (curl, git).
# Returns:
#   0 — everything present
#   1 — something is missing
# ============================================================
check_dependencies() {
    log_info "Checking dependencies"

    local missing=()
    local pkg

    for pkg in "${REQUIRED_PACKAGES[@]}"; do
        if command -v "$pkg" &>/dev/null; then
            log_debug "Found: $pkg"
        else
            missing+=("$pkg")
            log_warn "Not found: $pkg"
        fi
    done

    if [ ${#missing[@]} -eq 0 ]; then
        log_info "All dependencies present"
        return 0
    fi

    log_warn "Missing: ${missing[*]}"
    return 1
}

# ============================================================
# check_disk_space
# Checks free disk space.
# Arguments:
#   $1 — minimum required space in MB (default: MIN_DISK_SPACE_MB)
# Returns:
#   0 — enough space
#   1 — not enough space
# ============================================================
check_disk_space() {
    local required_mb="${1:-$MIN_DISK_SPACE_MB}"
    log_info "Checking free disk space (minimum ${required_mb} MB required)"

    local target_dir="$HOME"
    [ -d "$NVM_DIR" ] && target_dir="$NVM_DIR"

    local available_mb
    available_mb=$(df -Pm "$target_dir" 2>/dev/null | awk 'NR==2 {print $4}')

    if [ -z "$available_mb" ]; then
        log_warn "Could not determine free disk space"
        return 0  # do not block, just warn
    fi

    log_debug "Available: ${available_mb} MB in $target_dir"

    if [ "$available_mb" -lt "$required_mb" ]; then
        log_error "Not enough space: ${available_mb} MB < ${required_mb} MB"
        return 1
    fi

    log_info "Enough space (${available_mb} MB)"
    return 0
}

# ============================================================
# check_internet
# Checks access to GitHub (where NVM is downloaded from).
# Returns:
#   0 — access available
#   1 — no access
# ============================================================
check_internet() {
    log_info "Checking access to github.com"

    if curl -sI --max-time 10 https://github.com &>/dev/null; then
        log_info "GitHub is reachable"
        return 0
    fi

    log_error "GitHub is unreachable. Check your internet connection."
    return 1
}

# ============================================================
# ask_user_confirmation
# Asks the user for confirmation.
# Arguments:
#   $1 — question text
# Returns:
#   0 — user agreed (y/Y)
#   1 — user declined
# ============================================================
ask_user_confirmation() {
    local question="${1:-Continue?}"

    if [ "$ASK_CONFIRMATION" != true ]; then
        return 0
    fi

    # If not a terminal — do not ask
    if [ ! -t 0 ]; then
        log_debug "Not a terminal — skipping confirmation"
        return 0
    fi

    local answer
    read -rp "${question} [y/N]: " answer
    case "$answer" in
        [yY]|[yY][eE][sS]) return 0 ;;
        *) return 1 ;;
    esac
}

# ============================================================
# run_all_checks
# Runs all checks in order.
# Returns:
#   0 — everything passed
#   1 — something failed
# ============================================================
run_all_checks() {
    log_separator
    log_info "=== Running checks ==="

    # 1. Is NVM already installed?
    #    With FORCE=true — skip the stop
    if ! check_nvm_installed; then
        if [ "${FORCE:-false}" = true ]; then
            log_warn "NVM check failed, but --force is enabled — continuing"
        else
            log_info "To reinstall, run with --force"
            return 1
        fi
    fi

    # 2. Conflicts with Node.js
    if [ "$CHECK_CONFLICTS" = true ]; then
        if ! check_node_conflicts; then
            if ! ask_user_confirmation "Continue despite conflicts?"; then
                log_warn "User declined to continue"
                return 1
            fi
        fi
    fi

    # 3. Dependencies
    if ! check_dependencies; then
        if ! ask_user_confirmation "Install missing packages?"; then
            log_warn "User declined to install dependencies"
            return 1
        fi
        # Flag for installer.sh: dependencies need to be installed
        export INSTALL_DEPS_NEEDED=true
    fi

    # 4. Disk space
    if ! check_disk_space; then
        return 1
    fi

    # 5. Internet
    if ! check_internet; then
        return 1
    fi

    log_success "All checks passed"
    log_separator
    return 0
}