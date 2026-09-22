#!/bin/bash
# lib/manifest.sh
# Manifest handling for install-nvm
# Depends on: lib/logger.sh, config/nvm.conf
#
# The manifest is a file where install-nvm records everything
# it created or modified. uninstall-nvm reads it and removes
# only what is recorded.
#
# Format: TYPE|PATH|EXTRA|TIMESTAMP
# Example:
#   CREATED_DIR|/home/user/.nvm|2026-09-13T10:27:52Z
#   CREATED_FILE|/home/user/.nvm/nvm.sh|2026-09-13T10:27:52Z
#   MODIFIED_FILE|/home/user/.bashrc|2026-09-13T10:27:52Z
#   ADDED_LINE|/home/user/.bashrc|NVM_DIR block|2026-09-13T10:27:52Z
#   PACKAGE|curl|2026-09-13T10:27:52Z

# Guard against re-sourcing
if [ -n "${_MANIFEST_SH_LOADED:-}" ]; then
    return 0
fi
readonly _MANIFEST_SH_LOADED=1

# ============================================================
# Path to the manifest
# ============================================================
MANIFEST_FILE="${MANIFEST_FILE:-${NVM_DIR}/.install-nvm-manifest}"

# ============================================================
# manifest_init
# Creates the manifest with a header.
# If the manifest already exists, a backup is created.
# Returns:
#   0 — success
#   1 — error
# ============================================================
manifest_init() {
    local manifest="$MANIFEST_FILE"

    log_info "Initializing manifest: $manifest"

    # Create the directory if it does not exist
    local manifest_dir
    manifest_dir=$(dirname "$manifest")
    if [ ! -d "$manifest_dir" ]; then
        if ! mkdir -p "$manifest_dir"; then
            log_error "Failed to create directory: $manifest_dir"
            return 1
        fi
    fi

    # If the manifest already exists, back it up
    if [ -f "$manifest" ]; then
        local backup="${manifest}.bak.$(date '+%Y%m%d_%H%M%S')"
        if ! cp "$manifest" "$backup"; then
            log_warn "Failed to create backup: $backup"
        else
            log_warn "Existing manifest saved: $backup"
        fi
    fi

    # Create a new manifest with a header
    local timestamp
    timestamp=$(date -u '+%Y-%m-%dT%H:%M:%SZ')

    {
        echo "# install-nvm manifest"
        echo "# Format: TYPE|PATH|EXTRA|TIMESTAMP"
        echo "# Created: ${timestamp}"
        echo "# Host: $(hostname)"
        echo "# User: $(whoami)"
        echo "#"
    } > "$manifest" || {
        log_error "Failed to create manifest: $manifest"
        return 1
    }

    log_success "Manifest created: $manifest"
    return 0
}

# ============================================================
# manifest_add
# Adds a record to the manifest.
# Arguments:
#   $1 — type (CREATED_DIR, CREATED_FILE, MODIFIED_FILE,
#              ADDED_LINE, BACKUP, PACKAGE, NODE_VERSION,
#              NPM_PACKAGE)
#   $2 — path or name
#   $3 — additional info (optional)
# Returns:
#   0 — success
#   1 — error
# ============================================================
manifest_add() {
    local type="$1"
    local path="$2"
    local extra="${3:-}"
    local timestamp
    timestamp=$(date -u '+%Y-%m-%dT%H:%M:%SZ')

    # Check that the type is not empty
    if [ -z "$type" ] || [ -z "$path" ]; then
        log_warn "manifest_add: empty type or path"
        return 1
    fi

    # Check that the manifest exists
    if [ ! -f "$MANIFEST_FILE" ]; then
        log_error "Manifest not found: $MANIFEST_FILE"
        log_error "Call manifest_init() before manifest_add()"
        return 1
    fi

    # Build the line
    local line
    if [ -n "$extra" ]; then
        line="${type}|${path}|${extra}|${timestamp}"
    else
        line="${type}|${path}|${timestamp}"
    fi

    # Write the line
    if ! echo "$line" >> "$MANIFEST_FILE"; then
        log_error "Failed to write to manifest: $line"
        return 1
    fi

    log_debug "manifest: $line"
    return 0
}

# ============================================================
# manifest_exists
# Checks whether the manifest exists.
# Returns:
#   0 — exists
#   1 — does not exist
# ============================================================
manifest_exists() {
    [ -f "$MANIFEST_FILE" ]
}

# ============================================================
# manifest_read
# Reads the manifest without comments and empty lines.
# Returns:
#   0 — success
#   1 — error
# ============================================================
manifest_read() {
    if [ ! -f "$MANIFEST_FILE" ]; then
        log_error "Manifest not found: $MANIFEST_FILE"
        return 1
    fi

    grep -v '^#' "$MANIFEST_FILE" | grep -v '^$'
    return 0
}

# ============================================================
# manifest_count
# Counts the number of records in the manifest.
# Returns:
#   0 — success
#   1 — error
# ============================================================
manifest_count() {
    if [ ! -f "$MANIFEST_FILE" ]; then
        echo "0"
        return 1
    fi

    local count
    count=$(grep -vc '^#' "$MANIFEST_FILE" 2>/dev/null || echo 0)
    echo "$count"
    return 0
}

# ============================================================
# manifest_count_by_type
# Counts records of a specific type.
# Arguments:
#   $1 — type (CREATED_DIR, CREATED_FILE, ...)
# Returns:
#   0 — success
# ============================================================
manifest_count_by_type() {
    local type="$1"

    if [ ! -f "$MANIFEST_FILE" ]; then
        echo "0"
        return 0
    fi

    local count
    count=$(grep -c "^${type}|" "$MANIFEST_FILE" 2>/dev/null) || true
    echo "${count:-0}"
    return 0
}

# ============================================================
# manifest_list_by_type
# Returns a list of paths of a specific type.
# Arguments:
#   $1 — type
# Returns:
#   0 — success, list on stdout (one per line)
# ============================================================
manifest_list_by_type() {
    local type="$1"

    if [ ! -f "$MANIFEST_FILE" ]; then
        return 0
    fi

    grep "^${type}|" "$MANIFEST_FILE" 2>/dev/null | while IFS='|' read -r _ path _ _; do
        echo "$path"
    done

    return 0
}

# ============================================================
# manifest_get_field
# Extracts a field from a manifest record.
# Arguments:
#   $1 — manifest line
#   $2 — field number (1-based)
# Returns:
#   0 — success, value on stdout
# ============================================================
manifest_get_field() {
    local line="$1"
    local field_num="$2"

    echo "$line" | awk -F'|' -v n="$field_num" '{print $n}'
    return 0
}

# ============================================================
# manifest_summary
# Shows a summary of the manifest.
# Returns:
#   0 — success
# ============================================================
manifest_summary() {
    if ! manifest_exists; then
        log_warn "Manifest not found: $MANIFEST_FILE"
        return 1
    fi

    log_info "=== Manifest summary ==="
    log_info "File: $MANIFEST_FILE"

    local total
    total=$(manifest_count)
    log_info "Total records: $total"

    local types=(
        "CREATED_DIR"
        "CREATED_FILE"
        "MODIFIED_FILE"
        "ADDED_LINE"
        "BACKUP"
        "PACKAGE"
        "NODE_VERSION"
        "NPM_PACKAGE"
    )

    local type
    for type in "${types[@]}"; do
        local count
        count=$(manifest_count_by_type "$type")
        if [ "$count" -gt 0 ]; then
            log_info "  ${type}: ${count}"
        fi
    done

    return 0
}

# ============================================================
# manifest_show
# Shows the manifest contents in a readable form.
# Returns:
#   0 — success
# ============================================================
manifest_show() {
    if ! manifest_exists; then
        log_warn "Manifest not found: $MANIFEST_FILE"
        return 1
    fi

    log_info "=== Manifest contents ==="

    while IFS='|' read -r type path extra timestamp; do
        case "$type" in
            CREATED_DIR)
                log_info "  [DIR]  $path"
                ;;
            CREATED_FILE)
                log_info "  [FILE] $path"
                ;;
            MODIFIED_FILE)
                log_info "  [MOD]  $path"
                ;;
            ADDED_LINE)
                log_info "  [LINE] $path  ($extra)"
                ;;
            BACKUP)
                log_info "  [BAK]  $path"
                ;;
            PACKAGE)
                log_info "  [PKG]  $path"
                ;;
            NODE_VERSION)
                log_info "  [NODE] $path"
                ;;
            NPM_PACKAGE)
                log_info "  [NPM]  $path"
                ;;
            *)
                log_info "  [$type] $path"
                ;;
        esac
    done < <(manifest_read)

    return 0
}

# ============================================================
# manifest_remove
# Removes the manifest.
# Returns:
#   0 — success
#   1 — error
# ============================================================
manifest_remove() {
    if ! manifest_exists; then
        log_debug "Manifest does not exist: $MANIFEST_FILE"
        return 0
    fi

    if ! rm -f "$MANIFEST_FILE"; then
        log_error "Failed to remove manifest: $MANIFEST_FILE"
        return 1
    fi

    log_success "Manifest removed: $MANIFEST_FILE"
    return 0
}
