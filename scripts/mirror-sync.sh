#!/bin/bash
# Mirror Sync Script
# Syncs files from external repositories based on mirror-sources.json
#
# Usage:
#   ./scripts/mirror-sync.sh [--dry-run] [--source-id ID]
#
# Requirements:
#   - jq
#   - git
#   - curl

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CONFIG_FILE="$REPO_ROOT/mirror-sources.json"
DRY_RUN=false
SOURCE_FILTER=""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

is_windows() {
    [[ "$OSTYPE" == "msys" || "$OSTYPE" == "cygwin" || "$OSTYPE" == "win32" ]] || [[ -n "${WINDIR:-}" ]]
}

# On Windows, read fresh PATH from registry since subprocess inherits stale PATH
refresh_path_windows() {
    if is_windows; then
        # Read User PATH from registry
        local user_path
        user_path=$(powershell.exe -NoProfile -Command '[Environment]::GetEnvironmentVariable("Path", "User")' 2>/dev/null | tr -d '\r')

        # Read Machine PATH from registry
        local machine_path
        machine_path=$(powershell.exe -NoProfile -Command '[Environment]::GetEnvironmentVariable("Path", "Machine")' 2>/dev/null | tr -d '\r')

        # Combine and export (Machine;User order like Windows does)
        if [[ -n "$machine_path" || -n "$user_path" ]]; then
            # Convert Windows paths to Unix-style for Git Bash
            local new_path=""
            [[ -n "$machine_path" ]] && new_path="$machine_path"
            [[ -n "$user_path" ]] && new_path="${new_path:+$new_path;}$user_path"

            # Convert semicolons to colons and backslashes to forward slashes for bash
            new_path=$(echo "$new_path" | sed 's/;/:/g' | sed 's/\\/\//g')
            export PATH="$new_path"
        fi
    fi
}

# Find jq binary - check common Windows install locations
find_jq_windows() {
    local locations=(
        "$LOCALAPPDATA/Microsoft/WinGet/Links/jq.exe"
        "$LOCALAPPDATA/Microsoft/WinGet/Packages/jqlang.jq_Microsoft.Winget.Source_8wekyb3d8bbwe/jq.exe"
        "/c/ProgramData/chocolatey/bin/jq.exe"
        "$HOME/scoop/shims/jq.exe"
    )

    for loc in "${locations[@]}"; do
        # Expand variables and convert to unix path
        local expanded
        expanded=$(eval echo "$loc" 2>/dev/null)
        if [[ -f "$expanded" ]]; then
            echo "$expanded"
            return 0
        fi
    done

    # Try to find via PowerShell Get-Command
    local ps_path
    ps_path=$(powershell.exe -NoProfile -Command "(Get-Command jq -ErrorAction SilentlyContinue).Source" 2>/dev/null | tr -d '\r')
    if [[ -n "$ps_path" && -f "$ps_path" ]]; then
        # Convert Windows path to Unix path for Git Bash
        echo "$ps_path" | sed 's/\\/\//g' | sed 's/^\([A-Za-z]\):/\/\L\1/'
        return 0
    fi

    return 1
}

install_jq_windows() {
    if command -v winget &> /dev/null; then
        log_info "Installing jq via winget..."
        winget install jqlang.jq --accept-source-agreements --accept-package-agreements

        log_info "Refreshing PATH from registry..."
        refresh_path_windows

        # Check if jq is now available
        if command -v jq &> /dev/null; then
            log_success "jq installed and available"
            return 0
        fi

        # Try to find jq directly
        log_info "Searching for jq binary..."
        local jq_path
        if jq_path=$(find_jq_windows); then
            log_success "Found jq at: $jq_path"
            # Add to PATH for this session
            export PATH="$(dirname "$jq_path"):$PATH"
            return 0
        fi

        log_error "jq installed but not found in PATH. Please restart your terminal."
        exit 1
    else
        log_error "winget not available. Please install jq manually:"
        echo "  - Download from: https://jqlang.github.io/jq/download/"
        echo "  - Or: winget install jqlang.jq"
        exit 1
    fi
}

check_dependencies() {
    local missing=()

    if ! command -v jq &> /dev/null; then
        if is_windows; then
            # First try refreshing PATH - maybe jq is installed but PATH is stale
            refresh_path_windows

            if ! command -v jq &> /dev/null; then
                # Try finding jq directly
                local jq_path
                if jq_path=$(find_jq_windows); then
                    log_info "Found jq at: $jq_path"
                    export PATH="$(dirname "$jq_path"):$PATH"
                else
                    log_warn "jq not found. Attempting auto-install..."
                    install_jq_windows
                fi
            fi
        else
            missing+=("jq")
        fi
    fi

    if ! command -v git &> /dev/null; then
        missing+=("git")
    fi
    if ! command -v curl &> /dev/null; then
        missing+=("curl")
    fi

    if [[ ${#missing[@]} -gt 0 ]]; then
        log_error "Missing dependencies: ${missing[*]}"
        echo "Install with:"
        echo "  - jq: https://jqlang.github.io/jq/download/"
        echo "  - git: comes with Git for Windows"
        echo "  - curl: comes with Git for Windows"
        exit 1
    fi
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --source-id)
                SOURCE_FILTER="$2"
                shift 2
                ;;
            -h|--help)
                echo "Usage: $0 [--dry-run] [--source-id ID]"
                echo ""
                echo "Options:"
                echo "  --dry-run      Show what would be done without making changes"
                echo "  --source-id    Only sync specific source by ID"
                echo "  -h, --help     Show this help"
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                exit 1
                ;;
        esac
    done
}

fetch_raw_file() {
    local repo_url="$1"
    local branch="$2"
    local file_path="$3"
    local dest_path="$4"

    # Convert GitHub URL to raw content URL
    # https://github.com/user/repo -> https://raw.githubusercontent.com/user/repo/branch/path
    local raw_url
    raw_url=$(echo "$repo_url" | sed 's|github.com|raw.githubusercontent.com|')
    raw_url="${raw_url}/${branch}/${file_path}"

    log_info "Fetching: $raw_url"

    if $DRY_RUN; then
        log_warn "[DRY-RUN] Would fetch $file_path -> $dest_path"
        return 0
    fi

    # Create destination directory if needed
    local dest_dir
    dest_dir=$(dirname "$dest_path")
    mkdir -p "$dest_dir"

    # Fetch file
    local http_code
    http_code=$(curl -sL -w "%{http_code}" -o "$dest_path" "$raw_url")

    if [[ "$http_code" != "200" ]]; then
        log_error "Failed to fetch $file_path (HTTP $http_code)"
        rm -f "$dest_path"
        return 1
    fi

    log_success "Synced: $file_path -> $dest_path"
    return 0
}

sync_source() {
    local source_json="$1"

    local id name description repo branch
    id=$(echo "$source_json" | jq -r '.id')
    name=$(echo "$source_json" | jq -r '.name')
    description=$(echo "$source_json" | jq -r '.description')
    repo=$(echo "$source_json" | jq -r '.repo')
    branch=$(echo "$source_json" | jq -r '.branch')

    # Check if we should filter this source
    if [[ -n "$SOURCE_FILTER" && "$id" != "$SOURCE_FILTER" ]]; then
        return 0
    fi

    echo ""
    log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log_info "Syncing: $name (ID: $id)"
    log_info "Repo: $repo @ $branch"
    log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    local success_count=0
    local fail_count=0

    # Iterate over mappings
    while IFS= read -r mapping; do
        local src dest
        src=$(echo "$mapping" | jq -r '.source')
        dest=$(echo "$mapping" | jq -r '.dest')

        local full_dest="$REPO_ROOT/$dest"

        if fetch_raw_file "$repo" "$branch" "$src" "$full_dest"; then
            ((success_count++))
        else
            ((fail_count++))
        fi
    done < <(echo "$source_json" | jq -c '.mappings[]')

    echo ""
    if [[ $fail_count -eq 0 ]]; then
        log_success "Source '$name': $success_count files synced successfully"
    else
        log_warn "Source '$name': $success_count succeeded, $fail_count failed"
    fi

    return $fail_count
}

main() {
    # Store original args for potential restart
    ORIGINAL_ARGS=("$@")

    parse_args "$@"
    check_dependencies "${ORIGINAL_ARGS[@]}"

    if [[ ! -f "$CONFIG_FILE" ]]; then
        log_error "Config file not found: $CONFIG_FILE"
        exit 1
    fi

    # Validate JSON
    if ! jq empty "$CONFIG_FILE" 2>/dev/null; then
        log_error "Invalid JSON in $CONFIG_FILE"
        exit 1
    fi

    log_info "Mirror Sync starting..."
    if $DRY_RUN; then
        log_warn "Running in DRY-RUN mode - no changes will be made"
    fi

    # Get number of sources
    local source_count
    source_count=$(jq '.sources | length' "$CONFIG_FILE")

    if [[ "$source_count" -eq 0 ]]; then
        log_warn "No sources configured in $CONFIG_FILE"
        exit 0
    fi

    log_info "Found $source_count source(s) to sync"

    local total_failures=0

    # Iterate over sources
    while IFS= read -r source_json; do
        if ! sync_source "$source_json"; then
            ((total_failures++))
        fi
    done < <(jq -c '.sources[]' "$CONFIG_FILE")

    echo ""
    log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    if [[ $total_failures -eq 0 ]]; then
        log_success "Mirror sync completed successfully!"
    else
        log_error "Mirror sync completed with $total_failures source(s) having failures"
        exit 1
    fi
}

main "$@"
