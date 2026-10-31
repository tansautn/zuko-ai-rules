#!/bin/bash
# Mirror Source Manager
# Quick add/remove/list mirror sources in mirror-sources.json
#
# Usage:
#   ./scripts/mirror-source.sh list
#   ./scripts/mirror-source.sh show <id>
#   ./scripts/mirror-source.sh add git   --repo <url> --branch <branch> --name <name> --map <src>:<dest> [--map ...]
#   ./scripts/mirror-source.sh add release --repo <url> --tag <tag> --name <name> --map <src>:<dest> [--map ...]
#   ./scripts/mirror-source.sh add release_asset --repo <url> --tag <tag> --name <name> --asset <pattern>:<dest> [--unzip] [--pick <path>]
#   ./scripts/mirror-source.sh remove <id> [--yes]
#
# Requires: jq

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

if [[ -f "$PWD/mirror-sources.json" ]]; then
    CONFIG_FILE="$PWD/mirror-sources.json"
else
    CONFIG_FILE="$SCRIPT_DIR/mirror-sources.json"
fi

# Fallback: check repo root
if [[ ! -f "$CONFIG_FILE" && -f "$REPO_ROOT/mirror-sources.json" ]]; then
    CONFIG_FILE="$REPO_ROOT/mirror-sources.json"
fi

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

die()  { echo -e "${RED}[ERROR]${NC} $1" >&2; exit 1; }
info() { echo -e "${BLUE}[INFO]${NC} $1" >&2; }
ok()   { echo -e "${GREEN}[OK]${NC} $1" >&2; }

# ─── Dependencies ────────────────────────────────────────────────────────────

ensure_jq() {
    command -v jq &>/dev/null && return 0

    local bin_dir="$HOME/.local/.bin"
    if [[ -x "$bin_dir/jq" ]]; then
        export PATH="$bin_dir:$PATH"
        return 0
    fi

    die "jq not found. Install: https://jqlang.github.io/jq/download/"
}

ensure_config() {
    if [[ ! -f "$CONFIG_FILE" ]]; then
        die "Config not found: $CONFIG_FILE\nRun from repo root or set mirror-sources.json in CWD."
    fi
}

# ─── Generate short hex ID ──────────────────────────────────────────────────

gen_id() {
    if command -v openssl &>/dev/null; then
        openssl rand -hex 3
    elif [[ -r /dev/urandom ]]; then
        head -c3 /dev/urandom | od -An -tx1 | tr -d ' \n'
    else
        printf '%06x' $((RANDOM * RANDOM % 16777216))
    fi
}

# ─── List ────────────────────────────────────────────────────────────────────

cmd_list() {
    ensure_config
    local count
    count=$(jq '.sources | length' "$CONFIG_FILE")

    if [[ "$count" -eq 0 ]]; then
        info "No sources configured."
        return 0
    fi

    printf "${BOLD}%-8s %-16s %-12s %-40s %s${NC}\n" "ID" "TYPE" "TAG/BRANCH" "REPO" "NAME"
    printf '%.0s─' {1..100}; echo

    jq -r '.sources[] | [
        .id,
        (.type // "git"),
        (.branch // .tag // "-"),
        .repo,
        .name
    ] | @tsv' "$CONFIG_FILE" | while IFS=$'\t' read -r id type ref repo name; do
        printf "%-8s ${CYAN}%-16s${NC} %-12s %-40s ${GREEN}%s${NC}\n" \
            "$id" "$type" "$ref" "$repo" "$name"
    done

    echo ""
    info "$count source(s) in $CONFIG_FILE"
}

# ─── Show ────────────────────────────────────────────────────────────────────

cmd_show() {
    local id="${1:?Usage: mirror-source.sh show <id>}"
    ensure_config

    local source
    source=$(jq -e --arg id "$id" '.sources[] | select(.id == $id)' "$CONFIG_FILE" 2>/dev/null) \
        || die "Source '$id' not found."

    echo "$source" | jq '.'
}

# ─── Remove ──────────────────────────────────────────────────────────────────

cmd_remove() {
    local id="${1:?Usage: mirror-source.sh remove <id> [--yes]}"
    local auto_yes=false
    [[ "${2:-}" == "--yes" || "${2:-}" == "-y" ]] && auto_yes=true

    ensure_config

    # Verify exists
    jq -e --arg id "$id" '.sources[] | select(.id == $id)' "$CONFIG_FILE" >/dev/null 2>&1 \
        || die "Source '$id' not found."

    local name
    name=$(jq -r --arg id "$id" '.sources[] | select(.id == $id) | .name' "$CONFIG_FILE")

    if ! $auto_yes; then
        echo -e "${YELLOW}Remove source:${NC} $name (${id})?"
        read -r -p "Confirm [y/N]: " confirm
        [[ "$confirm" =~ ^[yY] ]] || { info "Cancelled."; return 0; }
    fi

    local tmp="${CONFIG_FILE}.tmp"
    jq --arg id "$id" '.sources |= map(select(.id != $id))' "$CONFIG_FILE" > "$tmp"
    mv "$tmp" "$CONFIG_FILE"

    ok "Removed source '$name' ($id)"
}

# ─── Add: git ────────────────────────────────────────────────────────────────

add_git() {
    local repo="" branch="" name="" desc=""
    local -a mappings=()

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --repo)    repo="$2"; shift 2 ;;
            --branch)  branch="$2"; shift 2 ;;
            --name)    name="$2"; shift 2 ;;
            --desc)    desc="$2"; shift 2 ;;
            --map)     mappings+=("$2"); shift 2 ;;
            *) die "Unknown flag: $1" ;;
        esac
    done

    [[ -n "$repo" ]]   || die "--repo required"
    [[ -n "$branch" ]] || die "--branch required"
    [[ -n "$name" ]]   || die "--name required"
    [[ ${#mappings[@]} -gt 0 ]] || die "At least one --map <source>:<dest> required"

    local id
    id=$(gen_id)

    local maps_json="[]"
    for m in "${mappings[@]}"; do
        local src="${m%%:*}"
        local dst="${m#*:}"
        [[ "$src" != "$dst" || "$m" == *":"* ]] || die "Invalid mapping format: $m (use source:dest)"
        maps_json=$(echo "$maps_json" | jq --arg s "$src" --arg d "$dst" '. + [{"source": $s, "dest": $d}]')
    done

    local entry
    entry=$(jq -n \
        --arg id "$id" \
        --arg name "$name" \
        --arg desc "$desc" \
        --arg repo "$repo" \
        --arg branch "$branch" \
        --argjson mappings "$maps_json" \
        '{id: $id, type: "git", name: $name, repo: $repo, branch: $branch, mappings: $mappings}
         | if $desc != "" then .description = $desc else . end')

    local tmp="${CONFIG_FILE}.tmp"
    jq --argjson entry "$entry" '.sources += [$entry]' "$CONFIG_FILE" > "$tmp"
    mv "$tmp" "$CONFIG_FILE"

    ok "Added git source '$name' (id: $id)"
    echo "$entry" | jq '.'
}

# ─── Add: release ────────────────────────────────────────────────────────────

add_release() {
    local repo="" tag="" name="" desc=""
    local -a mappings=()

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --repo)    repo="$2"; shift 2 ;;
            --tag)     tag="$2"; shift 2 ;;
            --name)    name="$2"; shift 2 ;;
            --desc)    desc="$2"; shift 2 ;;
            --map)     mappings+=("$2"); shift 2 ;;
            *) die "Unknown flag: $1" ;;
        esac
    done

    [[ -n "$repo" ]] || die "--repo required"
    [[ -n "$tag" ]]  || die "--tag required"
    [[ -n "$name" ]] || die "--name required"
    [[ ${#mappings[@]} -gt 0 ]] || die "At least one --map <source>:<dest> required"

    local id
    id=$(gen_id)

    local maps_json="[]"
    for m in "${mappings[@]}"; do
        local src="${m%%:*}"
        local dst="${m#*:}"
        maps_json=$(echo "$maps_json" | jq --arg s "$src" --arg d "$dst" '. + [{"source": $s, "dest": $d}]')
    done

    local entry
    entry=$(jq -n \
        --arg id "$id" \
        --arg name "$name" \
        --arg desc "$desc" \
        --arg repo "$repo" \
        --arg tag "$tag" \
        --argjson mappings "$maps_json" \
        '{id: $id, type: "release", name: $name, repo: $repo, tag: $tag, mappings: $mappings}
         | if $desc != "" then .description = $desc else . end')

    local tmp="${CONFIG_FILE}.tmp"
    jq --argjson entry "$entry" '.sources += [$entry]' "$CONFIG_FILE" > "$tmp"
    mv "$tmp" "$CONFIG_FILE"

    ok "Added release source '$name' (id: $id)"
    echo "$entry" | jq '.'
}

# ─── Add: release_asset ─────────────────────────────────────────────────────

add_release_asset() {
    local repo="" tag="" name="" desc=""
    local asset_pattern="" dest="" unzip="false" pick=""
    local version_from="" version_regex=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --repo)           repo="$2"; shift 2 ;;
            --tag)            tag="$2"; shift 2 ;;
            --name)           name="$2"; shift 2 ;;
            --desc)           desc="$2"; shift 2 ;;
            --asset)
                local val="$2"
                asset_pattern="${val%%:*}"
                dest="${val#*:}"
                shift 2 ;;
            --unzip)          unzip="true"; shift ;;
            --pick)           pick="$2"; shift 2 ;;
            --version-from)   version_from="$2"; shift 2 ;;
            --version-regex)  version_regex="$2"; shift 2 ;;
            *) die "Unknown flag: $1" ;;
        esac
    done

    [[ -n "$repo" ]]          || die "--repo required"
    [[ -n "$tag" ]]           || die "--tag required"
    [[ -n "$name" ]]          || die "--name required"
    [[ -n "$asset_pattern" ]] || die "--asset <pattern>:<dest> required"
    [[ -n "$dest" ]]          || die "--asset format: <pattern>:<dest>"

    local id
    id=$(gen_id)

    local mapping
    mapping=$(jq -n \
        --arg p "$asset_pattern" \
        --arg d "$dest" \
        --arg u "$unzip" \
        --arg pk "$pick" \
        '{asset_pattern: $p, dest: $d}
         | if $u == "true" then .unzip = true else . end
         | if $pk != "" then .pick = $pk else . end')

    local entry
    entry=$(jq -n \
        --arg id "$id" \
        --arg name "$name" \
        --arg desc "$desc" \
        --arg repo "$repo" \
        --arg tag "$tag" \
        --arg vf "$version_from" \
        --arg vr "$version_regex" \
        --argjson mapping "$mapping" \
        '{id: $id, type: "release_asset", name: $name, repo: $repo, tag: $tag, mappings: [$mapping]}
         | if $desc != "" then .description = $desc else . end
         | if $vf != "" then .version_from = $vf else . end
         | if $vr != "" then .version_regex = $vr else . end')

    local tmp="${CONFIG_FILE}.tmp"
    jq --argjson entry "$entry" '.sources += [$entry]' "$CONFIG_FILE" > "$tmp"
    mv "$tmp" "$CONFIG_FILE"

    ok "Added release_asset source '$name' (id: $id)"
    echo "$entry" | jq '.'
}

# ─── Add dispatcher ─────────────────────────────────────────────────────────

cmd_add() {
    local type="${1:?Usage: mirror-source.sh add <git|release|release_asset> [flags]}"
    shift
    ensure_config

    case "$type" in
        git)            add_git "$@" ;;
        release)        add_release "$@" ;;
        release_asset)  add_release_asset "$@" ;;
        *) die "Unknown type: $type. Use: git, release, release_asset" ;;
    esac
}

# ─── Main ────────────────────────────────────────────────────────────────────

main() {
    ensure_jq

    local cmd="${1:-help}"
    shift || true

    case "$cmd" in
        list|ls)     cmd_list "$@" ;;
        show)        cmd_show "$@" ;;
        add)         cmd_add "$@" ;;
        remove|rm)   cmd_remove "$@" ;;
        -h|--help|help)
            echo "Usage: mirror-source.sh <command> [args]"
            echo ""
            echo "Commands:"
            echo "  list                    List all mirror sources"
            echo "  show <id>               Show source details"
            echo "  add <type> [flags]      Add a new source"
            echo "  remove <id> [--yes]     Remove a source by ID"
            echo ""
            echo "Add types:"
            echo "  git            --repo <url> --branch <b> --name <n> --map <src>:<dest>"
            echo "  release        --repo <url> --tag <t> --name <n> --map <src>:<dest>"
            echo "  release_asset  --repo <url> --tag <t> --name <n> --asset <pattern>:<dest>"
            echo "                 [--unzip] [--pick <path>] [--version-from tag|asset_name]"
            echo "                 [--version-regex <regex>]"
            echo ""
            echo "Common flags:"
            echo "  --desc <text>           Optional description"
            echo ""
            echo "Examples:"
            echo "  # Add a git source"
            echo "  mirror-source.sh add git --repo https://github.com/foo/bar \\"
            echo "    --branch main --name 'My Rule' --map skills/x/SKILL.md:skills/x/SKILL.md"
            echo ""
            echo "  # Add a release asset source"
            echo "  mirror-source.sh add release_asset --repo https://github.com/foo/bar \\"
            echo "    --tag latest --name 'My Binary' --asset 'foo-v*-linux.tar.gz:bin/foo' \\"
            echo "    --unzip --pick 'foo-*/foo'"
            echo ""
            echo "  # Remove a source"
            echo "  mirror-source.sh remove a7f3c9"
            ;;
        *) die "Unknown command: $cmd. Run with --help" ;;
    esac
}

main "$@"
