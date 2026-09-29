#!/bin/bash
# Mirror Sync Script
# Syncs files from external repositories based on mirror-sources.json
#
# Usage:
#   ./scripts/mirror-sync.sh [--dry-run] [--source-id ID]
#
# Source types:
#   git           - Fetch raw files from a git branch (default)
#   release       - Fetch files from a release source archive
#   release_asset - Fetch & optionally extract release asset files
#
# Requirements:
#   - jq
#   - git
#   - curl
#   - tar / unzip (bundled with Git for Windows)
#
# Optional env vars:
#   GITHUB_TOKEN  - GitHub personal access token (avoids 60 req/h rate limit)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CONFIG_FILE="$SCRIPT_DIR/mirror-sources.json"
REPO_CONFIG="$REPO_ROOT/config.json"
DRY_RUN=false
SOURCE_FILTER=""
RESOLVED_VERSION=""  # Set by sync functions; read by dispatcher to update config.json

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

log_info()    { echo -e "${BLUE}[INFO]${NC} $1" >&2; }
log_success() { echo -e "${GREEN}[OK]${NC} $1" >&2; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC} $1" >&2; }
log_error()   { echo -e "${RED}[ERROR]${NC} $1" >&2; }
log_step()    { echo -e "${CYAN}[STEP]${NC} $1" >&2; }

# ─── Platform helpers ────────────────────────────────────────────────────────

is_windows() {
    [[ "$OSTYPE" == "msys" || "$OSTYPE" == "cygwin" || "$OSTYPE" == "win32" ]] || [[ -n "${WINDIR:-}" ]]
}

# On Windows, read fresh PATH from registry since subprocess inherits stale PATH
refresh_path_windows() {
    if is_windows; then
        local user_path
        user_path=$(powershell.exe -NoProfile -Command '[Environment]::GetEnvironmentVariable("Path", "User")' 2>/dev/null | tr -d '\r')

        local machine_path
        machine_path=$(powershell.exe -NoProfile -Command '[Environment]::GetEnvironmentVariable("Path", "Machine")' 2>/dev/null | tr -d '\r')

        if [[ -n "$machine_path" || -n "$user_path" ]]; then
            local new_path=""
            [[ -n "$machine_path" ]] && new_path="$machine_path"
            [[ -n "$user_path" ]] && new_path="${new_path:+$new_path;}$user_path"

            new_path=$(echo "$new_path" | sed 's/;/:/g' | sed 's/\\/\//g')
            export PATH="$new_path"
        fi
    fi
}

find_jq_windows() {
    local locations=(
        "$LOCALAPPDATA/Microsoft/WinGet/Links/jq.exe"
        "$LOCALAPPDATA/Microsoft/WinGet/Packages/jqlang.jq_Microsoft.Winget.Source_8wekyb3d8bbwe/jq.exe"
        "/c/ProgramData/chocolatey/bin/jq.exe"
        "$HOME/scoop/shims/jq.exe"
    )

    for loc in "${locations[@]}"; do
        local expanded
        expanded=$(eval echo "$loc" 2>/dev/null)
        if [[ -f "$expanded" ]]; then
            echo "$expanded"
            return 0
        fi
    done

    local ps_path
    ps_path=$(powershell.exe -NoProfile -Command "(Get-Command jq -ErrorAction SilentlyContinue).Source" 2>/dev/null | tr -d '\r')
    if [[ -n "$ps_path" && -f "$ps_path" ]]; then
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

        if command -v jq &> /dev/null; then
            log_success "jq installed and available"
            return 0
        fi

        log_info "Searching for jq binary..."
        local jq_path
        if jq_path=$(find_jq_windows); then
            log_success "Found jq at: $jq_path"
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

# ─── Dependencies ─────────────────────────────────────────────────────────────

check_dependencies() {
    local missing=()

    if ! command -v jq &> /dev/null; then
        if is_windows; then
            refresh_path_windows

            if ! command -v jq &> /dev/null; then
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
    if ! command -v tar &> /dev/null; then
        missing+=("tar")
    fi

    if [[ ${#missing[@]} -gt 0 ]]; then
        log_error "Missing dependencies: ${missing[*]}"
        echo "Install with:"
        echo "  - jq:   https://jqlang.github.io/jq/download/"
        echo "  - git:  comes with Git for Windows"
        echo "  - curl: comes with Git for Windows"
        echo "  - tar:  comes with Git for Windows"
        exit 1
    fi
}

# ─── Argument parsing ─────────────────────────────────────────────────────────

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
                echo ""
                echo "Source types in mirror-sources.json:"
                echo "  git            Fetch raw files from a git branch (default)"
                echo "  release        Fetch files from a release source archive"
                echo "  release_asset  Fetch & optionally extract release asset files"
                echo ""
                echo "Environment variables:"
                echo "  GITHUB_TOKEN   GitHub PAT for authenticated API calls (avoids 60 req/h limit)"
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                exit 1
                ;;
        esac
    done
}

# ─── GitHub API helpers ───────────────────────────────────────────────────────

# Build curl auth header args based on GITHUB_TOKEN env var
github_auth_args() {
    if [[ -n "${GITHUB_TOKEN:-}" ]]; then
        echo "-H" "Authorization: Bearer ${GITHUB_TOKEN}"
    fi
}

# Extract "owner/repo" from a GitHub URL
# e.g. https://github.com/foo/bar -> foo/bar
repo_slug_from_url() {
    local url="$1"
    echo "$url" | sed 's|.*github\.com/||' | sed 's|\.git$||' | sed 's|/$||'
}

# Resolve a tag — if tag == "latest", call GitHub API to get the actual tag name.
# Prints the resolved tag string.
resolve_release_tag() {
    local repo_url="$1"
    local tag="$2"

    if [[ "$tag" != "latest" ]]; then
        echo "$tag"
        return 0
    fi

    local slug
    slug=$(repo_slug_from_url "$repo_url")
    local api_url="https://api.github.com/repos/${slug}/releases/latest"

    log_step "Resolving latest release tag for ${slug}..."

    local response
    # shellcheck disable=SC2046
    response=$(curl -sf $(github_auth_args) \
        -H "Accept: application/vnd.github+json" \
        "$api_url" 2>/dev/null) || {
        log_error "Failed to fetch release info from $api_url"
        return 1
    }

    local resolved_tag
    resolved_tag=$(echo "$response" | jq -r '.tag_name')

    if [[ -z "$resolved_tag" || "$resolved_tag" == "null" ]]; then
        log_error "Could not resolve latest tag for $slug"
        return 1
    fi

    log_info "Resolved latest tag: $resolved_tag"
    echo "$resolved_tag"
}

# Fetch release JSON (assets list) for a specific tag.
# Prints raw JSON of the release object.
get_release_json() {
    local repo_url="$1"
    local tag="$2"

    local slug
    slug=$(repo_slug_from_url "$repo_url")

    local api_url
    if [[ "$tag" == "latest" ]]; then
        api_url="https://api.github.com/repos/${slug}/releases/latest"
    else
        api_url="https://api.github.com/repos/${slug}/releases/tags/${tag}"
    fi

    # shellcheck disable=SC2046
    curl -sf $(github_auth_args) \
        -H "Accept: application/vnd.github+json" \
        "$api_url" 2>/dev/null || {
        log_error "Failed to fetch release JSON from $api_url"
        return 1
    }
}

# Match a wildcard pattern against asset names in release JSON.
# Prints the browser_download_url of the first matching asset.
# Uses a single jq call + full drain to avoid SIGPIPE on Windows.
match_asset_pattern() {
    local release_json="$1"
    local pattern="$2"
    local matched_url=""

    # Extract all assets as tab-separated "name\turl" in one jq pass,
    # then drain the entire output (no early pipe break → no SIGPIPE).
    while IFS=$'\t' read -r asset_name asset_url; do
        # Skip processing once we already found a match, but keep draining
        [[ -n "$matched_url" ]] && continue

        case "$asset_name" in
            $pattern)
                matched_url="$asset_url"
                ;;
        esac
    done < <(echo "$release_json" | jq -r '.assets[] | [.name, .browser_download_url] | @tsv')

    if [[ -n "$matched_url" ]]; then
        echo "$matched_url"
        return 0
    fi
    return 1
}

# ─── Archive extraction ───────────────────────────────────────────────────────

# Extract an archive file into dest_dir.
# Supports: .tar.gz, .tgz, .tar.xz, .tar.bz2, .zip
extract_archive() {
    local archive_file="$1"
    local dest_dir="$2"

    mkdir -p "$dest_dir"

    case "$archive_file" in
        *.tar.gz|*.tgz)
            tar -xzf "$archive_file" -C "$dest_dir"
            ;;
        *.tar.xz)
            tar -xJf "$archive_file" -C "$dest_dir"
            ;;
        *.tar.bz2)
            tar -xjf "$archive_file" -C "$dest_dir"
            ;;
        *.tar)
            tar -xf "$archive_file" -C "$dest_dir"
            ;;
        *.zip)
            unzip -q "$archive_file" -d "$dest_dir"
            ;;
        *)
            log_error "Unknown archive format: $archive_file"
            return 1
            ;;
    esac
}

# ─── Curl download helper ────────────────────────────────────────────────────

# Download a URL to a file. Returns non-zero on HTTP error.
download_file() {
    local url="$1"
    local dest_file="$2"

    local dest_dir
    dest_dir=$(dirname "$dest_file")
    mkdir -p "$dest_dir"

    local http_code
    # shellcheck disable=SC2046
    http_code=$(curl -sL $(github_auth_args) -w "%{http_code}" -o "$dest_file" "$url")

    if [[ "$http_code" != "200" ]]; then
        log_error "Failed to download $url (HTTP $http_code)"
        rm -f "$dest_file"
        return 1
    fi
}

# ─── Source type: git ─────────────────────────────────────────────────────────

fetch_raw_file() {
    local repo_url="$1"
    local branch="$2"
    local file_path="$3"
    local dest_path="$4"

    # Convert GitHub URL to raw content URL
    local raw_url
    raw_url=$(echo "$repo_url" | sed 's|github.com|raw.githubusercontent.com|')
    raw_url="${raw_url}/${branch}/${file_path}"

    log_info "Fetching: $raw_url"

    if $DRY_RUN; then
        log_warn "[DRY-RUN] Would fetch $file_path -> $dest_path"
        return 0
    fi

    local dest_dir
    dest_dir=$(dirname "$dest_path")
    mkdir -p "$dest_dir"

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

sync_source_git() {
    local source_json="$1"

    local id name repo branch
    id=$(echo "$source_json"   | jq -r '.id')
    name=$(echo "$source_json" | jq -r '.name')
    repo=$(echo "$source_json" | jq -r '.repo')
    branch=$(echo "$source_json" | jq -r '.branch')

    log_info "Type: git | Repo: $repo @ $branch"

    local success_count=0
    local fail_count=0

    while IFS= read -r mapping; do
        local src dest
        src=$(echo "$mapping"  | jq -r '.source')
        dest=$(echo "$mapping" | jq -r '.dest')

        local full_dest="$REPO_ROOT/$dest"

        if fetch_raw_file "$repo" "$branch" "$src" "$full_dest"; then
            success_count=$(( success_count + 1 ))
        else
            fail_count=$(( fail_count + 1 ))
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

# ─── Source type: release ─────────────────────────────────────────────────────

sync_source_release() {
    local source_json="$1"

    local id name repo tag
    id=$(echo "$source_json"   | jq -r '.id')
    name=$(echo "$source_json" | jq -r '.name')
    repo=$(echo "$source_json" | jq -r '.repo')
    tag=$(echo "$source_json"  | jq -r '.tag')

    # Resolve "latest" -> actual tag name
    local resolved_tag
    resolved_tag=$(resolve_release_tag "$repo" "$tag") || return 1

    # Expose resolved version for config.json update
    RESOLVED_VERSION="$resolved_tag"

    log_info "Type: release | Repo: $repo @ $resolved_tag"

    local slug
    slug=$(repo_slug_from_url "$repo")

    # GitHub source archive URL
    local archive_url="https://github.com/${slug}/archive/refs/tags/${resolved_tag}.tar.gz"

    local success_count=0
    local fail_count=0

    if $DRY_RUN; then
        log_warn "[DRY-RUN] Would download source archive: $archive_url"
        while IFS= read -r mapping; do
            local src dest
            src=$(echo "$mapping"  | jq -r '.source')
            dest=$(echo "$mapping" | jq -r '.dest')
            log_warn "[DRY-RUN] Would copy $src -> $REPO_ROOT/$dest"
            success_count=$(( success_count + 1 ))
        done < <(echo "$source_json" | jq -c '.mappings[]')
        log_success "Source '$name': $success_count files would be synced (dry-run)"
        return 0
    fi

    # Download archive to temp dir
    local tmp_dir
    tmp_dir=$(mktemp -d)
    trap "rm -rf '$tmp_dir'" RETURN

    local archive_file="$tmp_dir/source.tar.gz"
    log_step "Downloading source archive: $archive_url"
    download_file "$archive_url" "$archive_file" || return 1

    # Extract
    local extract_dir="$tmp_dir/extracted"
    log_step "Extracting archive..."
    extract_archive "$archive_file" "$extract_dir" || return 1

    # GitHub archives contain a top-level dir like "repo-tag/"
    # Find that dir automatically
    local archive_root
    archive_root=$(find "$extract_dir" -mindepth 1 -maxdepth 1 -type d | head -n1)

    if [[ -z "$archive_root" ]]; then
        log_error "Could not find extracted root directory in archive"
        return 1
    fi

    log_info "Archive root: $(basename "$archive_root")"

    while IFS= read -r mapping; do
        local src dest
        src=$(echo "$mapping"  | jq -r '.source')
        dest=$(echo "$mapping" | jq -r '.dest')

        local src_path="$archive_root/$src"
        local full_dest="$REPO_ROOT/$dest"

        if [[ ! -e "$src_path" ]]; then
            log_error "Path not found in archive: $src"
            fail_count=$(( fail_count + 1 ))
            continue
        fi

        local full_dest_dir
        full_dest_dir=$(dirname "$full_dest")
        mkdir -p "$full_dest_dir"

        if cp -r "$src_path" "$full_dest"; then
            log_success "Synced: $src -> $dest"
            success_count=$(( success_count + 1 ))
        else
            log_error "Failed to copy $src -> $dest"
            fail_count=$(( fail_count + 1 ))
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

# ─── Source type: release_asset ───────────────────────────────────────────────

sync_source_release_asset() {
    local source_json="$1"

    local id name repo tag
    id=$(echo "$source_json"   | jq -r '.id')
    name=$(echo "$source_json" | jq -r '.name')
    repo=$(echo "$source_json" | jq -r '.repo')
    tag=$(echo "$source_json"  | jq -r '.tag')

    # Resolve "latest" -> actual tag name
    local resolved_tag
    resolved_tag=$(resolve_release_tag "$repo" "$tag") || return 1

    # Version extraction config
    local version_from version_regex
    version_from=$(echo "$source_json"  | jq -r '.version_from // "tag"')
    version_regex=$(echo "$source_json" | jq -r '.version_regex // ""')

    # If version_from=tag, we can resolve immediately
    if [[ "$version_from" == "tag" ]]; then
        RESOLVED_VERSION="$resolved_tag"
    fi

    log_info "Type: release_asset | Repo: $repo @ $resolved_tag"

    local success_count=0
    local fail_count=0

    if $DRY_RUN; then
        log_warn "[DRY-RUN] Would fetch release asset list for tag $resolved_tag"
        while IFS= read -r mapping; do
            local pattern dest
            pattern=$(echo "$mapping" | jq -r '.asset_pattern')
            dest=$(echo "$mapping"    | jq -r '.dest')
            log_warn "[DRY-RUN] Would match asset pattern '$pattern' -> $dest"
            success_count=$(( success_count + 1 ))
        done < <(echo "$source_json" | jq -c '.mappings[]')
        log_success "Source '$name': $success_count assets would be synced (dry-run)"
        return 0
    fi

    # Fetch release JSON (contains asset list)
    log_step "Fetching release asset list..."
    local release_json
    release_json=$(get_release_json "$repo" "$resolved_tag") || return 1

    local asset_count
    asset_count=$(echo "$release_json" | jq '.assets | length')
    log_info "Found $asset_count assets in release"

    while IFS= read -r mapping; do
        local pattern dest unzip_asset pick
        pattern=$(echo "$mapping"     | jq -r '.asset_pattern')
        dest=$(echo "$mapping"        | jq -r '.dest')
        unzip_asset=$(echo "$mapping" | jq -r '.unzip // false')
        pick=$(echo "$mapping"        | jq -r '.pick // ""')

        log_step "Processing asset pattern: '$pattern'"

        # Match pattern against assets
        local asset_url
        if ! asset_url=$(match_asset_pattern "$release_json" "$pattern"); then
            log_error "No asset matched pattern '$pattern' in release $resolved_tag"
            fail_count=$(( fail_count + 1 ))
            continue
        fi

        local asset_name
        asset_name=$(basename "$asset_url")
        log_info "Matched asset: $asset_name"
        log_info "URL: $asset_url"

        # Extract version from asset name if requested (only capture on first match)
        if [[ "$version_from" == "asset_name" && -n "$version_regex" && -z "$RESOLVED_VERSION" ]]; then
            if [[ "$asset_name" =~ $version_regex ]]; then
                RESOLVED_VERSION="${BASH_REMATCH[1]}"
                log_info "Extracted version: $RESOLVED_VERSION"
            else
                log_warn "version_regex '$version_regex' did not match asset name '$asset_name'"
            fi
        fi

        # Download to temp dir
        local tmp_dir
        tmp_dir=$(mktemp -d)
        # Cleanup on subshell exit — use explicit cleanup at end of loop body
        local downloaded_file="$tmp_dir/$asset_name"

        if ! download_file "$asset_url" "$downloaded_file"; then
            rm -rf "$tmp_dir"
            fail_count=$(( fail_count + 1 ))
            continue
        fi

        local full_dest="$REPO_ROOT/$dest"

        if [[ "$unzip_asset" == "true" ]]; then
            # Extract archive
            local extract_dir="$tmp_dir/extracted"
            log_step "Extracting: $asset_name"

            if ! extract_archive "$downloaded_file" "$extract_dir"; then
                rm -rf "$tmp_dir"
                fail_count=$(( fail_count + 1 ))
                continue
            fi

            if [[ -n "$pick" ]]; then
                # Pick a specific file/dir from the extracted content
                local pick_path="$extract_dir/$pick"

                if [[ ! -e "$pick_path" ]]; then
                    log_error "Pick path '$pick' not found inside extracted archive"
                    rm -rf "$tmp_dir"
                    fail_count=$(( fail_count + 1 ))
                    continue
                fi

                local full_dest_dir
                full_dest_dir=$(dirname "$full_dest")
                mkdir -p "$full_dest_dir"

                if cp -r "$pick_path" "$full_dest"; then
                    log_success "Synced: $asset_name/$pick -> $dest"
                    success_count=$(( success_count + 1 ))
                else
                    log_error "Failed to copy $pick -> $dest"
                    fail_count=$(( fail_count + 1 ))
                fi
            else
                # No pick — copy entire extracted content into dest dir
                mkdir -p "$full_dest"

                if cp -r "$extract_dir/." "$full_dest/"; then
                    log_success "Synced: $asset_name (all contents) -> $dest/"
                    success_count=$(( success_count + 1 ))
                else
                    log_error "Failed to copy extracted content -> $dest"
                    fail_count=$(( fail_count + 1 ))
                fi
            fi
        else
            # No unzip — copy asset file directly
            local full_dest_dir
            full_dest_dir=$(dirname "$full_dest")
            mkdir -p "$full_dest_dir"

            if cp "$downloaded_file" "$full_dest"; then
                log_success "Synced: $asset_name -> $dest"
                success_count=$(( success_count + 1 ))
            else
                log_error "Failed to copy $asset_name -> $dest"
                fail_count=$(( fail_count + 1 ))
            fi
        fi

        rm -rf "$tmp_dir"

    done < <(echo "$source_json" | jq -c '.mappings[]')

    echo ""
    if [[ $fail_count -eq 0 ]]; then
        log_success "Source '$name': $success_count assets synced successfully"
    else
        log_warn "Source '$name': $success_count succeeded, $fail_count failed"
    fi

    return $fail_count
}

# ─── Config version update ────────────────────────────────────────────────────

# Update version field in repo config.json for all metadata entries
# whose syncId matches the given source id.
update_config_version() {
    local source_id="$1"
    local version="$2"

    if [[ ! -f "$REPO_CONFIG" ]]; then
        return 0
    fi

    # Count matching entries
    local count
    count=$(jq --arg sid "$source_id" \
        '[.metadata | to_entries[] | select(.value.syncId == $sid)] | length' \
        "$REPO_CONFIG")

    if [[ "$count" -eq 0 ]]; then
        return 0
    fi

    log_step "Updating config.json: $count entry(ies) with syncId=$source_id -> version=$version"

    if $DRY_RUN; then
        log_warn "[DRY-RUN] Would update config.json version to $version for syncId=$source_id"
        return 0
    fi

    local updated
    updated=$(jq --arg sid "$source_id" --arg ver "$version" \
        '.metadata |= with_entries(
            if .value.syncId == $sid then .value.version = $ver
            else . end
        )' "$REPO_CONFIG")

    echo "$updated" > "$REPO_CONFIG"
    log_success "config.json updated: version set to $version"
}

# ─── Dispatcher ───────────────────────────────────────────────────────────────

sync_source() {
    local source_json="$1"

    local id name description type
    id=$(echo "$source_json"          | jq -r '.id')
    name=$(echo "$source_json"        | jq -r '.name')
    description=$(echo "$source_json" | jq -r '.description // ""')
    type=$(echo "$source_json"        | jq -r '.type // "git"')

    # Check if we should filter this source
    if [[ -n "$SOURCE_FILTER" && "$id" != "$SOURCE_FILTER" ]]; then
        return 0
    fi

    echo ""
    log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log_info "Syncing: $name (ID: $id)"
    [[ -n "$description" ]] && log_info "Desc: $description"
    log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    # Reset version before each source
    RESOLVED_VERSION=""

    local sync_result=0
    case "$type" in
        git)
            sync_source_git "$source_json" || sync_result=$?
            ;;
        release)
            sync_source_release "$source_json" || sync_result=$?
            ;;
        release_asset)
            sync_source_release_asset "$source_json" || sync_result=$?
            ;;
        *)
            log_error "Unknown source type '$type' for source '$name'"
            return 1
            ;;
    esac

    # After successful sync, update config.json version if resolved
    if [[ $sync_result -eq 0 && -n "$RESOLVED_VERSION" ]]; then
        update_config_version "$id" "$RESOLVED_VERSION"
    fi

    return $sync_result
}

# ─── Main ─────────────────────────────────────────────────────────────────────

main() {
    ORIGINAL_ARGS=("$@")

    parse_args "$@"
    check_dependencies "${ORIGINAL_ARGS[@]}"

    if [[ -n "${GITHUB_TOKEN:-}" ]]; then
        log_info "GITHUB_TOKEN detected — using authenticated API calls"
    else
        log_warn "GITHUB_TOKEN not set — using unauthenticated API (60 req/h limit)"
    fi

    if [[ ! -f "$CONFIG_FILE" ]]; then
        log_error "Config file not found: $CONFIG_FILE"
        exit 1
    fi

    if ! jq empty "$CONFIG_FILE" 2>/dev/null; then
        log_error "Invalid JSON in $CONFIG_FILE"
        exit 1
    fi

    log_info "Mirror Sync starting..."
    if $DRY_RUN; then
        log_warn "Running in DRY-RUN mode - no changes will be made"
    fi

    local source_count
    source_count=$(jq '.sources | length' "$CONFIG_FILE")

    if [[ "$source_count" -eq 0 ]]; then
        log_warn "No sources configured in $CONFIG_FILE"
        exit 0
    fi

    log_info "Found $source_count source(s) to sync"

    local total_failures=0

    while IFS= read -r source_json; do
        if ! sync_source "$source_json"; then
            total_failures=$(( total_failures + 1 ))
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
