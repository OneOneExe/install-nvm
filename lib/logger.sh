#!/bin/bash
# lib/logger.sh
# Logging functions for the install-nvm project
# Writes to the console (with color) and to a file (without color)
#
# Changes:
#   - added strip_ansi() to remove ANSI codes
#   - the cleaned message is written to the file

# ============================================================
# Colors for console output
# ============================================================
readonly COLOR_RESET='\033[0m'
readonly COLOR_RED='\033[0;31m'
readonly COLOR_GREEN='\033[0;32m'
readonly COLOR_YELLOW='\033[0;33m'
readonly COLOR_BLUE='\033[0;34m'
readonly COLOR_CYAN='\033[0;36m'

# ============================================================
# Logger variables (initialized in init_logger)
# ============================================================
LOG_FILE=""
LOG_LEVEL="INFO"       # DEBUG, INFO, WARN, ERROR
LOG_TO_FILE=true
LOG_TO_CONSOLE=true

# ============================================================
# strip_ansi
# Removes ANSI codes from a string.
# Used for writing to the file — colors are not needed there.
# Arguments:
#   $1 — string
# Returns:
#   cleaned string on stdout
# ============================================================
strip_ansi() {
    # If sed is not available — return the string as is
    if ! command -v sed &>/dev/null; then
        echo "$1"
        return 0
    fi

    # Remove ESC sequences of the form \033[...m
    # Supports both \033 and \x1B
    printf '%s' "$1" | sed -E 's/\x1B\[[0-9;]*[A-Za-z]//g'
}

# ============================================================
# init_logger
# Initializes the log file. Creates the directory if it does not exist.
# Arguments:
#   $1 — log directory (default: ./logs)
#   $2 — log level (default: INFO)
# ============================================================
init_logger() {
    local log_dir="${1:-./logs}"
    local level="${2:-INFO}"

    LOG_LEVEL="$level"

    # Create the log directory
    if [ ! -d "$log_dir" ]; then
        mkdir -p "$log_dir" || {
            echo "ERROR: failed to create directory $log_dir" >&2
            return 1
        }
    fi

    # Build the file name with date and time
    local timestamp
    timestamp=$(date '+%Y-%m-%d_%H-%M-%S')
    LOG_FILE="${log_dir}/install-${timestamp}.log"

    # Create the file and write the header
    : > "$LOG_FILE" || {
        echo "ERROR: failed to create file $LOG_FILE" >&2
        return 1
    }

    {
        echo "============================================================"
        echo " install-nvm — installation log"
        echo " Start: $(date '+%Y-%m-%d %H:%M:%S')"
        echo " User: $(whoami)"
        echo " Host: $(hostname)"
        echo " OS: $(uname -srm)"
        echo "============================================================"
        echo ""
    } >> "$LOG_FILE"

    return 0
}

# ============================================================
# _log
# Internal function. Formats and writes a message.
# Arguments:
#   $1 — level (DEBUG, INFO, WARN, ERROR, SUCCESS)
#   $2 — message
# ============================================================
_log() {
    local level="$1"
    local message="$2"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    # Level check: write only if the message level >= LOG_LEVEL
    local level_num=0
    local log_level_num=0
    case "$level" in
        DEBUG)   level_num=0 ;;
        INFO)    level_num=1 ;;
        SUCCESS) level_num=1 ;;
        WARN)    level_num=2 ;;
        ERROR)   level_num=3 ;;
    esac
    case "$LOG_LEVEL" in
        DEBUG)   log_level_num=0 ;;
        INFO)    log_level_num=1 ;;
        WARN)    log_level_num=2 ;;
        ERROR)   log_level_num=3 ;;
    esac
    [ "$level_num" -lt "$log_level_num" ] && return 0

    # Build the line for the file (without color)
    # strip_ansi removes any ANSI codes from the message
    local clean_message
    clean_message=$(strip_ansi "$message")
    local file_line="[${level}] ${timestamp} ${clean_message}"

    # Build the line for the console (with color)
    local color=""
    local prefix=""
    case "$level" in
        DEBUG)   color="$COLOR_CYAN";   prefix="[DEBUG]" ;;
        INFO)    color="$COLOR_BLUE";   prefix="[INFO]" ;;
        SUCCESS) color="$COLOR_GREEN";  prefix="[SUCCESS]" ;;
        WARN)    color="$COLOR_YELLOW"; prefix="[WARN]" ;;
        ERROR)   color="$COLOR_RED";    prefix="[ERROR]" ;;
    esac

    # Console output
    if [ "$LOG_TO_CONSOLE" = true ]; then
        if [ -t 2 ]; then
            # Terminal — with color
            echo -e "${color}${prefix}${COLOR_RESET} ${message}" >&2
        else
            # Not a terminal (pipe, redirect) — without color
            echo "${prefix} ${message}" >&2
        fi
    fi

    # File output
    if [ "$LOG_TO_FILE" = true ] && [ -n "$LOG_FILE" ]; then
        echo "$file_line" >> "$LOG_FILE"
    fi

    return 0
}

# ============================================================
# Public logging functions
# ============================================================
log_debug()   { _log "DEBUG"   "$1"; }
log_info()    { _log "INFO"    "$1"; }
log_success() { _log "SUCCESS" "$1"; }
log_warn()    { _log "WARN"    "$1"; }
log_error()   { _log "ERROR"   "$1"; }

# ============================================================
# log_separator
# Writes a separator to the log (useful for sections)
# ============================================================
log_separator() {
    local line="------------------------------------------------------------"
    if [ "$LOG_TO_CONSOLE" = true ]; then
        echo "$line" >&2
    fi
    if [ "$LOG_TO_FILE" = true ] && [ -n "$LOG_FILE" ]; then
        echo "$line" >> "$LOG_FILE"
    fi
}

# ============================================================
# close_logger
# Closes the logger: writes the final line
# Arguments:
#   $1 — exit code (0 = success)
# ============================================================
close_logger() {
    local exit_code="${1:-0}"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    {
        echo ""
        echo "============================================================"
        echo " End: ${timestamp}"
        echo " Exit code: ${exit_code}"
        echo "============================================================"
    } >> "$LOG_FILE"

    return 0
}

# ============================================================
# get_log_file
# Returns the path to the current log file
# ============================================================
get_log_file() {
    echo "$LOG_FILE"
}