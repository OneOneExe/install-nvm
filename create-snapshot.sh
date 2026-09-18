#!/bin/bash
# create-snapshot.sh
# Creates a temporary install-nvm manifest
# Reads the system only. Removes and modifies nothing.
#
# Usage:
#   ./create-snapshot.sh              # create manifest + snapshot
#   ./create-snapshot.sh --help       # help
#   ./create-snapshot.sh --dry-run    # show what would be written

set -o pipefail

# ============================================================
# Determine the script directory
# ============================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR

# ============================================================
# Argument parsing
# ============================================================
DRY_RUN=false

while [ $# -gt 0 ]; do
    case "$1" in
        --help|-h)
            cat <<EOF
create-snapshot.sh — create a temporary install-nvm manifest

Usage:
  ./create-snapshot.sh [options]

Options:
  --help, -h    Show this help
  --dry-run     Show what would be written, without creating files

What it does:
  1. Creates a snapshot of ~/.nvm in ~/install-nvm-snapshot/
  2. Creates a temporary manifest at ~/.nvm/.install-nvm-manifest
  3. Does NOT remove or modify anything in the system

Where it writes:
  ~/install-nvm-snapshot/         — system snapshot
  ~/.nvm/.install-nvm-manifest    — temporary manifest
EOF
            exit 0
            ;;
        --dry-run)
            DRY_RUN=true
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
# Constants
# ============================================================
readonly SNAPSHOT_DIR="$HOME/install-nvm-snapshot"
readonly NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
readonly MANIFEST_FILE="$NVM_DIR/.install-nvm-manifest"
readonly BASHRC="$HOME/.bashrc"
readonly NPMRC="$HOME/.npmrc"

# ============================================================
# Helper functions
# ============================================================
log() {
    echo "[INFO] $*"
}

log_warn() {
    echo "[WARN] $*" >&2
}

log_error() {
    echo "[ERROR] $*" >&2
}

log_success() {
    echo "[OK]   $*"
}

# ============================================================
# Checks
# ============================================================
check_nvm_installed() {
    if [ ! -d "$NVM_DIR" ]; then
        log_error "NVM not found: $NVM_DIR"
        log_error "Nothing to record. Run install-nvm.sh first."
        return 1
    fi

    if [ ! -s "$NVM_DIR/nvm.sh" ]; then
        log_error "nvm.sh not found: $NVM_DIR/nvm.sh"
        return 1
    fi

    log "NVM found: $NVM_DIR"
    return 0
}

# ============================================================
# Create system snapshot
# ============================================================
create_snapshot() {
    log "Creating system snapshot in $SNAPSHOT_DIR"

    if [ "$DRY_RUN" = true ]; then
        log "[dry-run] mkdir -p $SNAPSHOT_DIR"
        log "[dry-run] find $NVM_DIR ... > $SNAPSHOT_DIR/nvm-dirs.txt"
        log "[dry-run] ..."
        return 0
    fi

    if ! mkdir -p "$SNAPSHOT_DIR"; then
        log_error "Failed to create $SNAPSHOT_DIR"
        return 1
    fi

    # 1. Directories inside NVM
    find "$NVM_DIR" -maxdepth 3 -type d 2>/dev/null \
        | sort > "$SNAPSHOT_DIR/nvm-dirs.txt"

    # 2. Files inside NVM (top level only)
    find "$NVM_DIR" -maxdepth 1 -type f 2>/dev/null \
        | sort > "$SNAPSHOT_DIR/nvm-files.txt"

    # 3. Node.js versions
    if [ -d "$NVM_DIR/versions/node" ]; then
        find "$NVM_DIR/versions/node" -maxdepth 1 -mindepth 1 -type d -printf '%f\n' 2>/dev/null \
            | sort -V > "$SNAPSHOT_DIR/node-versions.txt"
    else
        echo "" > "$SNAPSHOT_DIR/node-versions.txt"
    fi

    # 4. NVM lines in ~/.bashrc
    if [ -f "$BASHRC" ]; then
        grep -n "NVM\|nvm\|install-nvm" "$BASHRC" 2>/dev/null \
            > "$SNAPSHOT_DIR/bashrc-nvm-lines.txt" || true
    fi

    # 5. ~/.npmrc
    if [ -f "$NPMRC" ]; then
        cat "$NPMRC" > "$SNAPSHOT_DIR/npmrc.txt" 2>/dev/null || true
    else
        echo "# file does not exist" > "$SNAPSHOT_DIR/npmrc.txt"
    fi

    # 6. PATH
    echo "$PATH" > "$SNAPSHOT_DIR/path.txt"

    # 7. Installed system packages (from REQUIRED_PACKAGES)
    if command -v dpkg &>/dev/null; then
        dpkg -l 2>/dev/null | grep -E "^ii  (curl|git) " \
            > "$SNAPSHOT_DIR/packages.txt" || true
    fi

    # 8. Snapshot date
    date '+%Y-%m-%d %H:%M:%S' > "$SNAPSHOT_DIR/snapshot-date.txt"

    log_success "Snapshot created: $SNAPSHOT_DIR"
    return 0
}

# ============================================================
# Create temporary manifest
# ============================================================
create_manifest() {
    log "Creating temporary manifest: $MANIFEST_FILE"

    if [ "$DRY_RUN" = true ]; then
        log "[dry-run] create $MANIFEST_FILE"
        return 0
    fi

    # Check whether the manifest already exists
    if [ -f "$MANIFEST_FILE" ]; then
        log_warn "Manifest already exists: $MANIFEST_FILE"
        local backup="${MANIFEST_FILE}.bak.$(date '+%Y%m%d_%H%M%S')"
        cp "$MANIFEST_FILE" "$backup"
        log_warn "Backup: $backup"
    fi

    local timestamp
    timestamp=$(date -u '+%Y-%m-%dT%H:%M:%SZ')

    # Build records in a temporary file
    local tmp_manifest
    tmp_manifest=$(mktemp)

    {
        echo "# install-nvm manifest (created manually via create-snapshot.sh)"
        echo "# Format: TYPE|PATH|TIMESTAMP"
        echo "# Created: $timestamp"
        echo "#"
    } > "$tmp_manifest"

    # --- 1. NVM_DIR ---
    echo "CREATED_DIR|${NVM_DIR}|${timestamp}" >> "$tmp_manifest"

    # --- 2. Files in the NVM root ---
    if [ -d "$NVM_DIR" ]; then
        while IFS= read -r file; do
            [ -z "$file" ] && continue
            echo "CREATED_FILE|${file}|${timestamp}" >> "$tmp_manifest"
        done < <(find "$NVM_DIR" -maxdepth 1 -type f 2>/dev/null)
    fi

    # --- 3. Node.js versions ---
    if [ -d "$NVM_DIR/versions/node" ]; then
        while IFS= read -r version_dir; do
            [ -z "$version_dir" ] && continue
            echo "CREATED_DIR|${version_dir}|${timestamp}" >> "$tmp_manifest"
        done < <(find "$NVM_DIR/versions/node" -maxdepth 1 -mindepth 1 -type d 2>/dev/null)
    fi

    # --- 4. ~/.bashrc ---
    if [ -f "$BASHRC" ]; then
        if grep -q "NVM_DIR\|install-nvm" "$BASHRC" 2>/dev/null; then
            echo "MODIFIED_FILE|${BASHRC}|${timestamp}" >> "$tmp_manifest"
            echo "ADDED_LINE|${BASHRC}|NVM_DIR block|${timestamp}" >> "$tmp_manifest"
        fi
    fi

    # --- 5. ~/.npmrc ---
    if [ -f "$NPMRC" ]; then
        if grep -qE '^[[:space:]]*prefix[[:space:]]*=' "$NPMRC" 2>/dev/null; then
            echo "MODIFIED_FILE|${NPMRC}|${timestamp}" >> "$tmp_manifest"
        fi
    fi

    # --- 6. System packages ---
    for pkg in curl git; do
        if command -v "$pkg" &>/dev/null; then
            echo "PACKAGE|${pkg}|${timestamp}" >> "$tmp_manifest"
        fi
    done

    # Copy to the manifest file
    if ! cp "$tmp_manifest" "$MANIFEST_FILE"; then
        log_error "Failed to write $MANIFEST_FILE"
        rm -f "$tmp_manifest"
        return 1
    fi

    rm -f "$tmp_manifest"

    log_success "Manifest created: $MANIFEST_FILE"

    # Show the contents
    log ""
    log "Manifest contents:"
    log "─────────────────────────────────────────"
    while IFS= read -r line; do
        log "  $line"
    done < "$MANIFEST_FILE"
    log "─────────────────────────────────────────"

    # Count statistics
    local total
    total=$(grep -vc '^#' "$MANIFEST_FILE" 2>/dev/null || echo 0)
    log "Total records: $total"

    return 0
}

# ============================================================
# Main
# ============================================================
main() {
    log "═══════════════════════════════════════════"
    log " create-snapshot.sh — temporary manifest"
    log "═══════════════════════════════════════════"
    log ""

    if [ "$DRY_RUN" = true ]; then
        log_warn "--dry-run mode: no files will be created"
    fi

    # 1. Verify NVM
    if ! check_nvm_installed; then
        exit 1
    fi

    # 2. Snapshot
    if ! create_snapshot; then
        exit 1
    fi

    # 3. Manifest
    if ! create_manifest; then
        exit 1
    fi

    log ""
    log_success "Done"
    log ""
    log "Next steps:"
    log "  1. Check the snapshot: ls -la $SNAPSHOT_DIR"
    log "  2. Check the manifest: cat $MANIFEST_FILE"
    log "  3. Continue working on uninstall-nvm.sh"
    log ""

    return 0
}

main "$@"
exit $?