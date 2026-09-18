#!/bin/bash
# lib/installer.sh
# Installs NVM and Node.js
# Depends on: lib/logger.sh, lib/manifest.sh, config/nvm.conf
#
# Changes:
#   - record_nvm_created() EXCLUDES the manifest from CREATED_FILE
#   - add_bashrc_block() wraps an existing NVM_DIR in markers
#   - configure_npm_prefix() REMOVED
#   - manifest_init() is called at the start of run_installation

# Guard against re-sourcing
if [ -n "${_INSTALLER_SH_LOADED:-}" ]; then
    return 0
fi
readonly _INSTALLER_SH_LOADED=1

# ============================================================
# install_dependencies
# Installs missing packages (curl, git) via apt.
# Returns:
#   0 — success
#   1 — error
# ============================================================
install_dependencies() {
    log_info "Installing dependencies"

    if [ "${INSTALL_DEPS_NEEDED:-false}" != true ]; then
        log_info "Dependencies already present — skipping"
        return 0
    fi

    if ! command -v apt &>/dev/null; then
        log_error "apt not found. This script targets Ubuntu/Debian."
        return 1
    fi

    log_info "Updating package list"
    if ! sudo apt update; then
        log_error "Failed to run apt update"
        return 1
    fi

    log_info "Installing: ${REQUIRED_PACKAGES[*]}"
    if ! sudo apt install -y "${REQUIRED_PACKAGES[@]}"; then
        log_error "Failed to install packages"
        return 1
    fi

    local pkg
    for pkg in "${REQUIRED_PACKAGES[@]}"; do
        manifest_add "PACKAGE" "$pkg"
    done

    log_success "Dependencies installed"
    return 0
}

# ============================================================
# download_nvm_installer
# Downloads the official NVM installer to a temporary file.
# Returns:
#   0 — success, path on stdout
#   1 — error
# ============================================================
download_nvm_installer() {
    local output="${1:-}"

    if [ -z "$output" ]; then
        output=$(mktemp /tmp/install-nvm-XXXXXX.sh)
    fi

    log_info "Downloading NVM installer ${NVM_VERSION}"
    log_debug "URL: $NVM_INSTALL_URL"
    log_debug "Destination: $output"

    if ! curl -fsSL "$NVM_INSTALL_URL" -o "$output"; then
        log_error "Failed to download NVM installer"
        rm -f "$output"
        return 1
    fi

    if [ ! -s "$output" ]; then
        log_error "Downloaded file is empty"
        rm -f "$output"
        return 1
    fi

    if ! head -n 1 "$output" | grep -q "bash"; then
        log_warn "First line does not look like a bash shebang"
    fi

    log_success "Installer downloaded: $output"
    echo "$output"
    return 0
}

# ============================================================
# run_nvm_installer
# Runs the downloaded NVM installer.
# Returns:
#   0 — success
#   1 — error
# ============================================================
run_nvm_installer() {
    local installer_path="$1"

    if [ ! -f "$installer_path" ]; then
        log_error "Installer not found: $installer_path"
        return 1
    fi

    log_info "Running NVM installer"
    log_debug "Script: $installer_path"

    if ! bash "$installer_path"; then
        log_error "NVM installer exited with an error"
        return 1
    fi

    log_success "NVM installer completed"
    return 0
}

# ============================================================
# record_nvm_created
# Records EVERYTHING created by the NVM installer into the manifest.
# Uses find for recursive traversal.
#
# IMPORTANT: the manifest is EXCLUDED from CREATED_FILE —
#            otherwise it would be removed along with the files
#            and the fallback would trigger for no reason.
#
# Returns:
#   0 — success
#   1 — error
# ============================================================
record_nvm_created() {
    log_info "Recording NVM-created files into the manifest"

    if [ ! -d "$NVM_DIR" ]; then
        log_warn "NVM directory not found: $NVM_DIR"
        return 1
    fi

    # 1. NVM root directory
    manifest_add "CREATED_DIR" "$NVM_DIR"

    # 2. ALL files recursively (except the manifest)
    local file_count=0
    local skipped_count=0
    while IFS= read -r file; do
        [ -z "$file" ] && continue

        # Exclude the manifest from the list
        if [ "$file" = "$MANIFEST_FILE" ]; then
            log_debug "Skipped manifest: $file"
            skipped_count=$((skipped_count + 1))
            continue
        fi

        manifest_add "CREATED_FILE" "$file"
        file_count=$((file_count + 1))
    done < <(find "$NVM_DIR" -type f 2>/dev/null)

    # 3. ALL directories recursively (except root — already recorded)
    local dir_count=0
    while IFS= read -r dir; do
        [ -z "$dir" ] && continue
        [ "$dir" = "$NVM_DIR" ] && continue
        manifest_add "CREATED_DIR" "$dir"
        dir_count=$((dir_count + 1))
    done < <(find "$NVM_DIR" -mindepth 1 -type d 2>/dev/null)

    log_info "Recorded: files — $file_count, directories — $dir_count (skipped: $skipped_count)"
    log_success "NVM entries added to the manifest"
    return 0
}

# ============================================================
# activate_nvm
# Activates NVM in the current session.
# nvm.sh is incompatible with pipefail and NPM_CONFIG_PREFIX.
# Returns:
#   0 — success
#   1 — error
# ============================================================
activate_nvm() {
    log_info "Activating NVM in the current session"

    export NVM_DIR

    if [ ! -s "$NVM_DIR/nvm.sh" ]; then
        log_error "Not found: $NVM_DIR/nvm.sh"
        return 1
    fi

    # nvm.sh is incompatible with pipefail — temporarily disable it
    local old_pipefail
    old_pipefail=$(set -o | grep pipefail | awk '{print $2}')
    set +o pipefail

    # nvm.sh is incompatible with NPM_CONFIG_PREFIX — temporarily remove it
    local old_npm_prefix="${NPM_CONFIG_PREFIX:-}"
    if [ -n "$old_npm_prefix" ]; then
        log_warn "NPM_CONFIG_PREFIX is set — temporarily removing it for nvm.sh"
        unset NPM_CONFIG_PREFIX
    fi

    # shellcheck disable=SC1091
    if ! \. "$NVM_DIR/nvm.sh"; then
        log_error "Failed to source nvm.sh"
        [ "$old_pipefail" = "on" ] && set -o pipefail
        [ -n "$old_npm_prefix" ] && export NPM_CONFIG_PREFIX="$old_npm_prefix"
        return 1
    fi

    # Restore pipefail
    [ "$old_pipefail" = "on" ] && set -o pipefail

    # Do not restore NPM_CONFIG_PREFIX — incompatible with NVM
    if [ -n "$old_npm_prefix" ]; then
        log_warn "NPM_CONFIG_PREFIX was not restored — incompatible with NVM"
    fi

    # Tab completion
    if [ -s "$NVM_DIR/bash_completion" ]; then
        # shellcheck disable=SC1091
        \. "$NVM_DIR/bash_completion" 2>/dev/null || true
    fi

    if ! command -v nvm &>/dev/null; then
        log_error "nvm command not found after activation"
        return 1
    fi

    log_success "NVM activated: $(nvm --version)"
    return 0
}

# ============================================================
# verify_nvm_installation
# Verifies that NVM works after installation.
# Returns:
#   0 — success
#   1 — error
# ============================================================
verify_nvm_installation() {
    log_info "Verifying NVM installation"

    if ! command -v nvm &>/dev/null; then
        log_error "nvm not found in PATH"
        return 1
    fi

    local version
    version=$(nvm --version 2>/dev/null) || {
        log_error "nvm does not respond to --version"
        return 1
    }

    log_success "NVM installed: v${version}"
    return 0
}

# ============================================================
# install_node_default
# Installs the default Node.js LTS.
# Returns:
#   0 — success
#   1 — error
# ============================================================
install_node_default() {
    if [ "$INSTALL_NODE_DEFAULT" != true ]; then
        log_info "Node.js installation disabled in config"
        return 0
    fi

    log_info "Installing Node.js: ${NODE_DEFAULT_VERSION}"

    if ! nvm install "$NODE_DEFAULT_VERSION"; then
        log_error "Failed to install Node.js ${NODE_DEFAULT_VERSION}"
        return 1
    fi

    if ! nvm alias default "$NODE_DEFAULT_VERSION"; then
        log_warn "Failed to set default alias"
    fi

    if ! nvm use default; then
        log_warn "Failed to switch to default"
    fi

    local node_version
    node_version=$(node -v 2>/dev/null || echo "unknown")
    local npm_version
    npm_version=$(npm -v 2>/dev/null || echo "unknown")

    if [ "$node_version" != "unknown" ]; then
        manifest_add "NODE_VERSION" "$node_version"
    fi

    local version_dir="$NVM_DIR/versions/node/${node_version}"
    if [ -d "$version_dir" ]; then
        manifest_add "CREATED_DIR" "$version_dir"
    fi

    log_success "Node.js installed: ${node_version} (npm ${npm_version})"
    return 0
}

# ============================================================
# add_bashrc_block
# Adds the NVM block to ~/.bashrc with markers.
#
# Logic:
#   1. Markers # >>> install-nvm >>> present? → skip
#   2. NVM_DIR present without markers? → wrap in markers
#   3. Nothing present? → add block with markers
#
# Returns:
#   0 — success
#   1 — error
# ============================================================
add_bashrc_block() {
    log_info "Configuring ~/.bashrc"

    local bashrc="$HOME/.bashrc"

    if [ ! -f "$bashrc" ]; then
        log_warn "$bashrc not found — skipping"
        return 0
    fi

    # --- Case 1: markers already present ---
    if grep -q ">>> install-nvm >>>" "$bashrc"; then
        log_info "Block with markers already present in ~/.bashrc — skipping"
        return 0
    fi

    # --- Case 2: NVM_DIR present without markers — wrap it ---
    if grep -q "NVM_DIR" "$bashrc"; then
        log_warn "Found NVM_DIR without markers — wrapping in markers"

        local backup="${bashrc}.bak.$(date '+%Y%m%d_%H%M%S')"
        if ! cp "$bashrc" "$backup"; then
            log_error "Failed to create backup: $backup"
            return 1
        fi
        manifest_add "BACKUP" "$backup"

        local tmp_file
        tmp_file=$(mktemp)

        awk '
            BEGIN { in_block = 0; block_done = 0 }
            /NVM_DIR/ {
                if (!in_block && !block_done) {
                    print "# >>> install-nvm >>>"
                    in_block = 1
                }
                print
                next
            }
            {
                if (in_block && !block_done) {
                    if ($0 !~ /nvm\.sh/ && $0 !~ /bash_completion/) {
                        print "# <<< install-nvm <<<"
                        block_done = 1
                        in_block = 0
                    }
                }
                print
            }
            END {
                if (in_block && !block_done) {
                    print "# <<< install-nvm <<<"
                }
            }
        ' "$bashrc" > "$tmp_file"

        if ! mv "$tmp_file" "$bashrc"; then
            log_error "Failed to update $bashrc"
            rm -f "$tmp_file"
            return 1
        fi

        manifest_add "MODIFIED_FILE" "$bashrc"
        manifest_add "ADDED_LINE" "$bashrc" "NVM_DIR block (wrapped)"

        log_success "Existing NVM_DIR wrapped in markers"
        log_info "Backup: $backup"
        return 0
    fi

    # --- Case 3: nothing present — add the block ---
    log_info "Adding install-nvm block to ~/.bashrc"

    local backup="${bashrc}.bak.$(date '+%Y%m%d_%H%M%S')"
    if ! cp "$bashrc" "$backup"; then
        log_error "Failed to create backup: $backup"
        return 1
    fi
    manifest_add "BACKUP" "$backup"

    {
        echo ""
        echo "# >>> install-nvm >>>"
        echo 'export NVM_DIR="$HOME/.nvm"'
        echo '[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"'
        echo '[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"'
        echo "# <<< install-nvm <<<"
    } >> "$bashrc" || {
        log_error "Failed to write to $bashrc"
        return 1
    }

    manifest_add "MODIFIED_FILE" "$bashrc"
    manifest_add "ADDED_LINE" "$bashrc" "NVM_DIR block"

    log_success "install-nvm block added to ~/.bashrc"
    log_info "Backup: $backup"
    return 0
}

# ============================================================
# cleanup_npmrc_prefix
# Removes the prefix setting from ~/.npmrc (conflict with NVM).
# Returns:
#   0 — success (or nothing to clean)
#   1 — error
# ============================================================
cleanup_npmrc_prefix() {
    local npmrc="$HOME/.npmrc"

    if [ ! -f "$npmrc" ]; then
        log_debug "~/.npmrc not found — nothing to clean"
        return 0
    fi

    if ! grep -qE '^[[:space:]]*prefix[[:space:]]*=' "$npmrc"; then
        log_debug "No prefix setting in ~/.npmrc — nothing to clean"
        return 0
    fi

    log_warn "Found prefix in ~/.npmrc — removing (conflict with NVM)"

    local backup="${npmrc}.bak.$(date '+%Y%m%d_%H%M%S')"
    cp "$npmrc" "$backup"
    manifest_add "BACKUP" "$backup"

    if ! sed -i -E '/^[[:space:]]*prefix[[:space:]]*=/d' "$npmrc"; then
        log_error "Failed to remove prefix from ~/.npmrc"
        return 1
    fi

    manifest_add "MODIFIED_FILE" "$npmrc"

    log_success "prefix setting removed from ~/.npmrc"
    return 0
}

# ============================================================
# cleanup_npm_config_prefix
# Removes NPM_CONFIG_PREFIX from ~/.bashrc (conflict with NVM).
# Returns:
#   0 — success (or nothing to clean)
#   1 — error
# ============================================================
cleanup_npm_config_prefix() {
    local bashrc="$HOME/.bashrc"

    if [ ! -f "$bashrc" ]; then
        log_debug "~/.bashrc not found — nothing to clean"
        return 0
    fi

    if ! grep -q "NPM_CONFIG_PREFIX" "$bashrc"; then
        log_debug "No NPM_CONFIG_PREFIX in ~/.bashrc — nothing to clean"
        return 0
    fi

    log_warn "Found NPM_CONFIG_PREFIX in ~/.bashrc — removing (conflict with NVM)"

    local backup="${bashrc}.bak.$(date '+%Y%m%d_%H%M%S')"
    cp "$bashrc" "$backup"
    manifest_add "BACKUP" "$backup"

    sed -i -E '/^[[:space:]]*# Added by install-nvm: NPM global prefix/d' "$bashrc" 2>/dev/null || true
    sed -i -E '/^[[:space:]]*export NPM_CONFIG_PREFIX=/d' "$bashrc" 2>/dev/null || true
    sed -i -E '/^[[:space:]]*export PATH=".*\.npm-global\/bin.*/d' "$bashrc" 2>/dev/null || true

    manifest_add "MODIFIED_FILE" "$bashrc"

    log_success "NPM_CONFIG_PREFIX removed from ~/.bashrc"
    return 0
}

# ============================================================
# cleanup_installer
# Removes the temporary installer file.
# ============================================================
cleanup_installer() {
    local path="$1"
    if [ -n "$path" ] && [ -f "$path" ]; then
        rm -f "$path"
        log_debug "Removed temporary file: $path"
    fi
}

# ============================================================
# show_next_steps
# Shows the user what to do after installation.
# ============================================================
show_next_steps() {
    log_info ""
    log_info "Next steps:"
    log_info "  1. Open a new terminal or run:"
    log_info "     source ~/.bashrc"
    log_info "  2. Verify:"
    log_info "     nvm --version"
    log_info "     node -v && npm -v"
    log_info ""
    log_info "Global NPM packages are managed by NVM:"
    log_info "  npm install -g <package>"
    log_info ""
    log_info "Installation manifest:"
    log_info "  $MANIFEST_FILE"
    log_info ""
    log_info "Additional checks:"
    log_info "  ./tests/verify.sh"
}

# ============================================================
# run_installation
# Main function: performs the entire installation step by step.
# Returns:
#   0 — success
#   1 — error
# ============================================================
run_installation() {
    log_separator
    log_info "=== Installing NVM ==="

    local installer_path=""

    # 0. Initialize the manifest
    if ! manifest_init; then
        log_error "Failed to initialize manifest"
        return 1
    fi

    # 1. Clean conflicting settings
    cleanup_npmrc_prefix
    cleanup_npm_config_prefix

    # 2. Dependencies
    if ! install_dependencies; then
        return 1
    fi

    # 3. Download the installer
    installer_path=$(download_nvm_installer) || {
        log_error "Step 'download installer' failed"
        return 1
    }

    # 4. Run the installer
    if ! run_nvm_installer "$installer_path"; then
        cleanup_installer "$installer_path"
        return 1
    fi

    # 5. Clean up the temporary file
    cleanup_installer "$installer_path"

    # 6. Record NVM-created files in the manifest (manifest is excluded)
    if ! record_nvm_created; then
        log_warn "Failed to record NVM-created files in the manifest"
    fi

    # 7. Activate in the current session
    if ! activate_nvm; then
        return 1
    fi

    # 8. Verify
    if ! verify_nvm_installation; then
        return 1
    fi

    # 9. Default Node.js
    if ! install_node_default; then
        return 1
    fi

    # 10. Configure ~/.bashrc
    if ! add_bashrc_block; then
        log_warn "Failed to configure ~/.bashrc"
    fi

    log_success "NVM installation complete"
    log_separator

    # Manifest summary
    manifest_summary

    return 0
}