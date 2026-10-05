#!/usr/bin/env bash
# update-changelog.sh
# Usage: update-changelog.sh <version> <is_release>
#   version    : e.g. "dev-abc1234" or "v1.2.0"
#   is_release : "true" | "false"
#
# Requires: git (with full history, fetch-depth: 0)
# CHANGELOG.md must exist or will be created.

set -euo pipefail

VER="${1:?version required}"
IS_RELEASE="${2:?is_release required}"
TODAY=$(date +%Y-%m-%d)
CHANGELOG="CHANGELOG.md"

# ---------------------------------------------------------------------------
# shouldIncludeInLog <subject>
# Returns 0 (include) or 1 (skip)
# ---------------------------------------------------------------------------
shouldIncludeInLog() {
  local subj="$1"
  # Skip merge commits
  [[ "$subj" == Merge\ remote-tracking* ]] && return 1
  # Skip changelog bot commits (subject starts with "chore(changelog)")
  [[ "$subj" == chore\(changelog\)* ]] && return 1
  return 0
}

# ---------------------------------------------------------------------------
# Build git log lines from <base_ref>..HEAD
# Falls back to all history when base_ref is empty / not found in git.
# ---------------------------------------------------------------------------
build_log_lines() {
  local base_ref="$1"
  local raw_line subject hash

  local sep=$'\x01'   # ASCII SOH — never appears in commit messages
  if [[ -n "$base_ref" ]] && git cat-file -e "$base_ref" 2>/dev/null; then
    git log "${base_ref}..HEAD" --pretty=format:"%s${sep}%h"
  else
    git log --pretty=format:"%s${sep}%h"
  fi | while IFS="$sep" read -r subject hash; do
    shouldIncludeInLog "$subject" || continue
    echo "- ${subject} (${hash})"
  done
}

# ---------------------------------------------------------------------------
# Determine commit range base
#   - If is_release: range starts right after the PREVIOUS release tag
#   - If dev: range starts right after the last release tag
#     (dev section always accumulates changes since last release)
# ---------------------------------------------------------------------------
get_base_ref() {
  # Last actual release tag (excludes dev- tags)
  local last_tag
  last_tag=$(git tag --list --sort=-version:refname | grep -v "^dev-" | head -n1 || true)
  echo "$last_tag"
}

# ---------------------------------------------------------------------------
# Ensure CHANGELOG.md exists with header
# ---------------------------------------------------------------------------
ensure_changelog() {
  if [[ ! -f "$CHANGELOG" ]]; then
    printf '# Changelog\n' > "$CHANGELOG"
  fi
}

# ---------------------------------------------------------------------------
# Remove the DEV marker block (lines between markers inclusive)
# ---------------------------------------------------------------------------
strip_dev_block() {
  sed -i '/<!-- DEV_CHANGELOG_START -->/,/<!-- DEV_CHANGELOG_END -->/d' "$CHANGELOG"
  # Remove any double-blank lines left behind
  sed -i '/^$/N;/^\n$/d' "$CHANGELOG"
}

# ---------------------------------------------------------------------------
# Insert a block right after "# Changelog" header line
# $1 = block text (multi-line string)
# ---------------------------------------------------------------------------
insert_after_header() {
  local block="$1"
  local tmp
  tmp=$(mktemp)
  awk -v block="$block" '
    /^# Changelog/ { print; print ""; print block; print ""; found=1; next }
    found && /^$/ { found=0; next }   # skip the blank line that was after header
    { print }
  ' "$CHANGELOG" > "$tmp"
  mv "$tmp" "$CHANGELOG"
}

# ---------------------------------------------------------------------------
# Extract current log lines from the DEV block in CHANGELOG (strip header/markers)
# Returns empty string if no dev block exists.
# ---------------------------------------------------------------------------
current_log_lines() {
  sed -n '/<!-- DEV_CHANGELOG_START -->/,/<!-- DEV_CHANGELOG_END -->/p' "$CHANGELOG" \
    | grep '^- '
}

# ===========================================================================
# MAIN
# ===========================================================================
ensure_changelog

BASE_REF=$(get_base_ref)
LOG_LINES=$(build_log_lines "$BASE_REF")

if [[ -z "$LOG_LINES" ]]; then
  LOG_LINES="- No notable changes"
fi

if [[ "$IS_RELEASE" == "true" ]]; then
  # 1. Remove dev marker block (its content becomes permanent history)
  strip_dev_block

  # 2. Insert release section at top
  BLOCK="## [${VER}] - ${TODAY}

${LOG_LINES}"
  insert_after_header "$BLOCK"

else
  # DEV BUILD
  # Guard: skip rewrite if log lines are identical to what's already in file.
  # Version header (dev-<hash>) changes every push but content may not.
  EXISTING=$(current_log_lines)
  if [[ "$EXISTING" == "$LOG_LINES" ]]; then
    echo "update-changelog: log lines unchanged, nothing to do." >&2
    exit 2  # signal to caller: no-op, skip commit
  fi

  # 1. Replace dev block entirely (idempotent — always one dev section)
  strip_dev_block

  # 2. Insert fresh dev block at top
  BLOCK="<!-- DEV_CHANGELOG_START -->
## [${VER}] - ${TODAY}

${LOG_LINES}

<!-- DEV_CHANGELOG_END -->"
  insert_after_header "$BLOCK"
fi
