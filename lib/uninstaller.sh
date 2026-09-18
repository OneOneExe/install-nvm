#!/bin/bash
# lib/uninstaller.sh
# Removes NVM and install-nvm traces using the manifest
# Depends on: lib/logger.sh, lib/manifest.sh, config/nvm.conf
#
# Principle: remove ONLY what is recorded in the manifest.
# If the manifest is missing — fall back to removing ~/.nvm entirely.
#
# Changes:
#   - remove_created_files() checks manifest_exists
#   - remove_created_dirs() checks manifest_exists + fallback
#   - remove_manifest() is safe when the manifest is absent

# Guard against re-sourcing
if [ -n "${_UNINSTALLER_SH_LOADED:-}" ]; then
    return 0
fi
readonly _UNINSTALLER_SH_LOADED=1

# ============================================================
# Uninstall flags (set in uninstall-nvm.sh)
# ============================================================
KEEP_NODE="${KEEP_NODE:-false}"
KEEP_BASHRC="${KEEP_BASHRC:-false}"
PURGE="${PURGE:-false}"
UNINSTALL_YES="${UNINSTALL_YES:-false}"

# ============================================================
# check_manifest_exists
# Checks whether the manifest exists.
# Returns:
#   0 — exists
#   1 — does not exist
# ============================================================
check_manifest_exists() {
    log_info "Checking manifest: $MANIFEST_FILE"

    if manifest_exists; then
        local count
        count=$(manifest_count)
        log_success "Manifest found ($count records)"
        return 0
    fi

    log_warn "Manifest not found: $MANIFEST_FILE"
    return 1
}

# ============================================================
# check_nvm_running
# Checks whether Node.js is currently in use.
# Returns:
#   0 — not in use
#   1 — in use
# ============================================================
check_nvm_running() {
    log_info "Checking for running Node.js processes"

    if pgrep -x "node" &>/dev/null; then
        log_warn "Found running node processes:"
        pgrep -ax "node" | while read -r line; do
            log_warn "  $line"
        done
        return 1
    fi

    log_info "No running node processes found"
    return 0
}

# ============================================================
# show_uninstall_plan
# Shows what will be removed.
# Returns:
#   0 — success
# ============================================================
show_uninstall_plan() {
    log_separator
    log_info "=== Uninstall plan ==="

    if ! manifest_exists; then
        log_warn "Manifest not found — plan unavailable"
        log_info "Fallback mode will be used: remove ~/.nvm entirely"
        return 0
    fi

    # --- What will be removed ---
    log_info ""
    log_info "Will be removed:"

    local dirs_count
    dirs_count=$(manifest_count_by_type "CREATED_DIR")
    local files_count
    files_count=$(manifest_count_by_type "CREATED_FILE")
    local node_count
    node_count=$(manifest_count_by_type "NODE_VERSION")

    if [ "$dirs_count" -gt 0 ]; then
        log_info "  • Directories: $dirs_count"
    fi
    if [ "$files_count" -gt 0 ]; then
        log_info "  • Files: $files_count"
    fi
    if [ "$node_count" -gt 0 ] && [ "$KEEP_NODE" != true ]; then
        log_info "  • Node.js versions: $node_count"
    fi

    # --- What will be modified ---
    log_info ""
    log_info "Will be modified:"

    local mod_count
    mod_count=$(manifest_count_by_type "MODIFIED_FILE")
    if [ "$mod_count" -gt 0 ] && [ "$KEEP_BASHRC" != true ]; then
        log_info "  • Files: $mod_count"
    fi

    # --- What will NOT be removed ---
    log_info ""
    log_info "Will NOT be removed:"
    log_info "  • System packages (curl, git) — needed by others"
    log_info "  • ~/.npmrc (only prefix is cleaned)"
    log_info "  • Project logs (unless --purge)"

    if [ "$KEEP_NODE" = true ]; then
        log_info "  • Node.js versions (--keep-node)"
    fi

    if [ "$KEEP_BASHRC" = true ]; then
        log_info "  • ~/.bashrc (--keep-bashrc)"
    fi

    log_separator
    return 0
}

# ============================================================
# remove_npm_packages
# Information about global npm packages.
# Returns:
#   0 — success
# ============================================================
remove_npm_packages() {
    log_info "Removing global npm packages"

    if ! command -v nvm &>/dev/null; then
        log_debug "NVM is not active — skipping package removal"
        return 0
    fi

    local packages
    packages=$(npm list -g --depth=0 2>/dev/null | grep -E "^\S" | awk '{print $2}' | cut -d@ -f1) || true

    if [ -z "$packages" ]; then
        log_info "No global packages found"
        return 0
    fi

    log_warn "Found global packages:"
    echo "$packages" | while read -r pkg; do
        log_warn "  • $pkg"
    done

    log_info "Packages will be removed along with ~/.nvm"
    return 0
}

# ============================================================
# remove_created_files
# Removes files recorded in the manifest as CREATED_FILE.
#
# If the manifest is unavailable — skips (fallback in remove_created_dirs).
#
# Returns:
#   0 — success
# ============================================================
remove_created_files() {
    log_info "Removing created files"

    # If the manifest is unavailable — skip
    if ! manifest_exists; then
        log_warn "Manifest not found — skipping file removal"
        return 0
    fi

    local removed=0
    local skipped=0

    while IFS='|' read -r type path extra timestamp; do
        [ "$type" != "CREATED_FILE" ] && continue
        [ -z "$path" ] && continue

        if [ ! -e "$path" ]; then
            log_debug "Already removed: $path"
            continue
        fi

        if [ "$KEEP_NODE" = true ] && [[ "$path" == *".nvm/versions"* ]]; then
            log_debug "Skipped (--keep-node): $path"
            skipped=$((skipped + 1))
            continue
        fi

        if rm -f "$path" 2>/dev/null; then
            removed=$((removed + 1))
            log_debug "Removed file: $path"
        else
            log_warn "Failed to remove: $path"
        fi
    done < <(manifest_read)

    log_info "Files removed: $removed (skipped: $skipped)"
    return 0
}

# ============================================================
# remove_created_dirs
# Removes directories recorded in the manifest as CREATED_DIR.
#
# If the manifest is unavailable — removes ~/.nvm entirely (fallback).
# With --keep-node — keeps versions.
#
# Returns:
#   0 — success
# ============================================================
remove_created_dirs() {
    log_info "Removing created directories"

    # --- Fallback: no manifest ---
    if ! manifest_exists; then
        log_warn "Manifest not found — removing ~/.nvm entirely"

        if [ ! -d "$NVM_DIR" ]; then
            log_info "~/.nvm does not exist — nothing to remove"
            return 0
        fi

        if [ "$KEEP_NODE" = true ] && [ -d "$NVM_DIR/versions" ]; then
            # Keep versions, remove the rest
            find "$NVM_DIR" -mindepth 1 -maxdepth 1 ! -name versions -exec rm -rf {} \; 2>/dev/null || true
            log_success "~/.nvm cleaned (versions preserved)"
        else
            if rm -rf "$NVM_DIR" 2>/dev/null; then
                log_success "~/.nvm removed"
            else
                log_error "Failed to remove ~/.nvm"
                return 1
            fi
        fi
        return 0
    fi

    # --- Main mode: removal by manifest ---
    local removed=0
    local skipped=0

    # Collect all CREATED_DIR entries
    local dirs=()
    while IFS='|' read -r type path extra timestamp; do
        [ "$type" != "CREATED_DIR" ] && continue
        [ -z "$path" ] && continue
        dirs+=("$path")
    done < <(manifest_read)

    # Sort by path length (longest first — nested ones)
    if [ ${#dirs[@]} -gt 0 ]; then
        local sorted_dirs
        sorted_dirs=$(printf '%s\n' "${dirs[@]}" | awk '{ print length, $0 }' | sort -rn | cut -d' ' -f2-)

        while IFS= read -r dir; do
            [ -z "$dir" ] && continue

            if [ ! -d "$dir" ]; then
                log_debug "Already removed: $dir"
                continue
            fi

            if [ "$KEEP_NODE" = true ] && [[ "$dir" == *".nvm/versions"* ]]; then
                log_debug "Skipped (--keep-node): $dir"
                skipped=$((skipped + 1))
                continue
            fi

            if rmdir "$dir" 2>/dev/null; then
                removed=$((removed + 1))
                log_debug "Removed directory (empty): $dir"
            elif rm -rf "$dir" 2>/dev/null; then
                removed=$((removed + 1))
                log_debug "Removed directory: $dir"
            else
                log_warn "Failed to remove: $dir"
            fi
        done <<< "$sorted_dirs"
    fi

    log_info "Directories removed: $removed (skipped: $skipped)"

    # --- Final check: if ~/.nvm remains — remove it ---
    if [ -d "$NVM_DIR" ]; then
        local remaining
        remaining=$(ls -A "$NVM_DIR" 2>/dev/null | wc -l)
        if [ "$remaining" -gt 0 ]; then
            log_warn "~/.nvm contains $remaining items — removing entirely"
            if [ "$KEEP_NODE" = true ] && [ -d "$NVM_DIR/versions" ]; then
                find "$NVM_DIR" -mindepth 1 -maxdepth 1 ! -name versions -exec rm -rf {} \; 2>/dev/null || true
                log_success "~/.nvm cleaned (versions preserved)"
            else
                rm -rf "$NVM_DIR" 2>/dev/null || true
                log_success "~/.nvm removed"
            fi
        else
            rmdir "$NVM_DIR" 2>/dev/null || true
            log_info "~/.nvm is empty — removed"
        fi
    fi

    return 0
}

# ============================================================
# clean_bashrc_block
# Removes the install-nvm block from ~/.bashrc using markers.
# Returns:
#   0 — success
# ============================================================
clean_bashrc_block() {
    if [ "$KEEP_BASHRC" = true ]; then
        log_info "Skipping ~/.bashrc (--keep-bashrc)"
        return 0
    fi

    log_info "Cleaning ~/.bashrc"

    local bashrc="$HOME/.bashrc"

    if [ ! -f "$bashrc" ]; then
        log_warn "$bashrc not found"
        return 0
    fi

    # Check for markers
    if grep -q ">>> install-nvm >>>" "$bashrc"; then
        local backup="${bashrc}.bak.uninstall.$(date '+%Y%m%d_%H%M%S')"
        cp "$bashrc" "$backup"
        log_info "Backup: $backup"

        if sed -i '/# >>> install-nvm >>>/,/# <<< install-nvm <<</d' "$bashrc"; then
            log_success "install-nvm block removed from ~/.bashrc"
        else
            log_error "Failed to remove block from ~/.bashrc"
            return 1
        fi

        # Remove trailing empty lines
        sed -i -e :a -e '/^\n*$/{$d;N;ba' -e '}' "$bashrc" 2>/dev/null || true

        return 0
    fi

    # Fallback: old format without markers
    if grep -q "NVM_DIR" "$bashrc"; then
        log_warn "install-nvm block not found, but NVM_DIR is present — cleaning line by line"

        local backup="${bashrc}.bak.uninstall.$(date '+%Y%m%d_%H%M%S')"
        cp "$bashrc" "$backup"
        log_info "Backup: $backup"

        sed -i '/NVM_DIR/d' "$bashrc" 2>/dev/null || true
        log_success "NVM_DIR lines removed from ~/.bashrc"
        return 0
    fi

    log_info "No install-nvm traces in ~/.bashrc"
    return 0
}

# ============================================================
# clean_npmrc_prefix
# Removes the prefix setting from ~/.npmrc, if present.
# Returns:
#   0 — success
# ============================================================
clean_npmrc_prefix() {
    log_info "Cleaning ~/.npmrc"

    local npmrc="$HOME/.npmrc"

    if [ ! -f "$npmrc" ]; then
        log_debug "~/.npmrc not found"
        return 0
    fi

    if ! grep -qE '^[[:space:]]*prefix[[:space:]]*=' "$npmrc"; then
        log_debug "No prefix in ~/.npmrc"
        return 0
    fi

    local backup="${npmrc}.bak.uninstall.$(date '+%Y%m%d_%H%M%S')"
    cp "$npmrc" "$backup"
    log_info "Backup: $backup"

    sed -i -E '/^[[:space:]]*prefix[[:space:]]*=/d' "$npmrc" || {
        log_error "Failed to remove prefix from ~/.npmrc"
        return 1
    }

    log_success "prefix setting removed from ~/.npmrc"
    return 0
}

# ============================================================
# clean_npm_config_prefix
# Removes NPM_CONFIG_PREFIX from ~/.bashrc, if present.
# Returns:
#   0 — success
# ============================================================
clean_npm_config_prefix() {
    if [ "$KEEP_BASHRC" = true ]; then
        return 0
    fi

    local bashrc="$HOME/.bashrc"

    if [ ! -f "$bashrc" ]; then
        return 0
    fi

    if ! grep -q "NPM_CONFIG_PREFIX" "$bashrc"; then
        return 0
    fi

    log_warn "Found NPM_CONFIG_PREFIX in ~/.bashrc — removing"

    sed -i -E '/^[[:space:]]*# Added by install-nvm: NPM global prefix/d' "$bashrc" 2>/dev/null || true
    sed -i -E '/^[[:space:]]*export NPM_CONFIG_PREFIX=/d' "$bashrc" 2>/dev/null || true
    sed -i -E '/^[[:space:]]*export PATH=".*\.npm-global\/bin.*/d' "$bashrc" 2>/dev/null || true

    log_success "NPM_CONFIG_PREFIX removed from ~/.bashrc"
    return 0
}

# ============================================================
# remove_npm_global
# Removes ~/.npm-global if it was created by install-nvm.
# Only with --purge.
# Returns:
#   0 — success
# ============================================================
remove_npm_global() {
    if [ "$PURGE" != true ]; then
        log_debug "~/.npm-global is not removed (--purge required)"
        return 0
    fi

    local npm_global="$HOME/.npm-global"

    if [ ! -d "$npm_global" ]; then
        log_debug "~/.npm-global not found"
        return 0
    fi

    log_warn "Removing ~/.npm-global (--purge)"

    if rm -rf "$npm_global"; then
        log_success "~/.npm-global removed"
    else
        log_error "Failed to remove ~/.npm-global"
        return 1
    fi

    return 0
}

# ============================================================
# remove_manifest
# Removes the manifest.
# Returns:
#   0 — success
# ============================================================
remove_manifest() {
    log_info "Removing manifest"

    if ! manifest_exists; then
        log_debug "Manifest already removed"
        return 0
    fi

    if manifest_remove; then
        log_success "Manifest removed"
    else
        log_warn "Failed to remove manifest"
    fi

    return 0
}

# ============================================================
# remove_logs
# Removes project logs (only with --purge).
# Returns:
#   0 — success
# ============================================================
remove_logs() {
    if [ "$PURGE" != true ]; then
        log_debug "Logs are not removed (--purge required)"
        return 0
    fi

    local project_dir
    project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
    local logs_dir="${project_dir}/logs"

    if [ ! -d "$logs_dir" ]; then
        log_debug "Logs not found: $logs_dir"
        return 0
    fi

    log_warn "Removing project logs (--purge)"

    if rm -rf "$logs_dir"; then
        log_success "Logs removed: $logs_dir"
    else
        log_warn "Failed to remove logs"
    fi

    return 0
}

# ============================================================
# verify_uninstall
# Verifies that everything was removed.
# Returns:
#   0 — success
#   1 — something remains
# ============================================================
verify_uninstall() {
    log_separator
    log_info "=== Uninstall verification ==="

    local failed=0

    # 1. ~/.nvm
    if [ -d "$NVM_DIR" ]; then
        log_warn "~/.nvm still exists: $NVM_DIR"
        log_info "Contents:"
        ls -la "$NVM_DIR" 2>/dev/null | head -20 | while read -r line; do
            log_info "  $line"
        done
        failed=$((failed + 1))
    else
        log_success "~/.nvm removed"
    fi

    # 2. ~/.bashrc
    if [ "$KEEP_BASHRC" != true ] && [ -f "$HOME/.bashrc" ]; then
        if grep -q ">>> install-nvm >>>" "$HOME/.bashrc"; then
            log_warn "install-nvm block still in ~/.bashrc"
            failed=$((failed + 1))
        else
            log_success "~/.bashrc cleaned"
        fi
    fi

    # 3. ~/.npmrc
    if [ -f "$HOME/.npmrc" ]; then
        if grep -qE '^[[:space:]]*prefix[[:space:]]*=' "$HOME/.npmrc"; then
            log_warn "prefix still in ~/.npmrc"
            failed=$((failed + 1))
        else
            log_success "~/.npmrc cleaned"
        fi
    fi

    # 4. NVM_DIR in PATH
    if [[ ":$PATH:" == *":${NVM_DIR}:"* ]]; then
        log_warn "NVM_DIR still in PATH (restart the terminal)"
    else
        log_success "NVM_DIR not in PATH"
    fi

    log_separator

    if [ "$failed" -gt 0 ]; then
        log_warn "Remaining artifacts: $failed"
        log_info "You may need to restart the terminal"
        return 1
    fi

    log_success "All artifacts removed"
    return 0
}

# ============================================================
# show_uninstall_next_steps
# Shows what to do after uninstall.
# ============================================================
show_uninstall_next_steps() {
    log_info ""
    log_info "Next steps:"
    log_info "  1. Open a new terminal (or run: source ~/.bashrc)"
    log_info "  2. Verify that nvm is not available:"
    log_info "     nvm --version"
    log_info "  3. Verify that node is not available:"
    log_info "     node -v"
    log_info ""
    log_info "If nvm or node are still available — restart the terminal."
    log_info ""
    log_info "Backups of ~/.bashrc and ~/.npmrc are preserved."
    log_info "If something broke — restore from *.bak.*"
}

# ============================================================
# run_uninstallation
# Main function: performs the uninstall step by step.
# Returns:
#   0 — success
#   1 — error
# ============================================================
run_uninstallation() {
    log_separator
    log_info "=== Removing NVM ==="

    # 1. Check manifest
    if ! check_manifest_exists; then
        log_warn "Manifest not found — running in fallback mode"
    fi

    # 2. Check running processes
    if ! check_nvm_running; then
        if [ "$UNINSTALL_YES" != true ]; then
            if ! ask_user_confirmation "Node.js is in use. Continue with uninstall?"; then
                log_warn "User declined"
                return 1
            fi
        fi
    fi

    # 3. Show plan
    show_uninstall_plan

    # 4. Confirm
    if [ "$UNINSTALL_YES" != true ]; then
        if ! ask_user_confirmation "Continue with uninstall?"; then
            log_warn "User declined"
            return 1
        fi
    fi

    # 5. Remove global npm packages (informational)
    remove_npm_packages

    # 6. Clean ~/.bashrc (before removing ~/.nvm)
    clean_bashrc_block
    clean_npm_config_prefix

    # 7. Clean ~/.npmrc
    clean_npmrc_prefix

    # 8. Remove created files
    remove_created_files

    # 9. Remove created directories (with fallback)
    remove_created_dirs

    # 10. Remove ~/.npm-global (only with --purge)
    remove_npm_global

    # 11. Remove manifest
    remove_manifest

    # 12. Remove logs (only with --purge)
    remove_logs

    # 13. Verify
    verify_uninstall

    log_separator
    log_success "NVM uninstall complete"

    show_uninstall_next_steps

    return 0
}