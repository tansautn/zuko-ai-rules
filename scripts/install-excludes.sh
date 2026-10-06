#!/bin/bash
# Install claudeMdExcludes into parent project's .claude/settings.local.json
#
# Prevents this repo's CLAUDE.md from conflicting with parent project instructions
# when added as a git submodule.
#
# Usage:
#   Run from the PARENT project root (not from inside the submodule):
#     .agents/zuko-ai-rules/scripts/install-excludes.sh
#     # or with explicit path:
#     .agents/zuko-ai-rules/scripts/install-excludes.sh --submodule-path .agents/zuko-ai-rules
#
# Requirements: jq

set -euo pipefail

SUBMODULE_PATH=""

# Parse args
while [[ $# -gt 0 ]]; do
  case "$1" in
    --submodule-path) SUBMODULE_PATH="$2"; shift 2 ;;
    -h|--help)
      echo "Usage: $0 [--submodule-path <path>]"
      echo ""
      echo "Install claudeMdExcludes into .claude/settings.local.json"
      echo "Run from the PARENT project root."
      echo ""
      echo "Options:"
      echo "  --submodule-path  Path to this submodule (auto-detected from .gitmodules)"
      exit 0
      ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

# Auto-detect submodule path from .gitmodules
if [[ -z "$SUBMODULE_PATH" ]]; then
  if [[ -f .gitmodules ]]; then
    # Find submodule paths pointing to this repo
    candidates=$(git config -f .gitmodules --get-regexp 'submodule\..*\.url' \
      | grep -i 'zuko-ai-rules' \
      | sed 's/submodule\.\(.*\)\.url .*/\1/' || true)

    if [[ -n "$candidates" ]]; then
      count=$(echo "$candidates" | wc -l)
      if [[ "$count" -eq 1 ]]; then
        SUBMODULE_PATH=$(git config -f .gitmodules "submodule.${candidates}.path")
        echo "Auto-detected submodule path: $SUBMODULE_PATH"
      else
        echo "Multiple candidates found in .gitmodules:"
        echo "$candidates"
        echo ""
        read -rp "Enter submodule path: " SUBMODULE_PATH
      fi
    fi
  fi
fi

if [[ -z "$SUBMODULE_PATH" ]]; then
  read -rp "Could not auto-detect. Enter submodule path (e.g. .agents/zuko-ai-rules): " SUBMODULE_PATH
fi

# Strip trailing slash
SUBMODULE_PATH="${SUBMODULE_PATH%/}"

if [[ ! -d "$SUBMODULE_PATH" ]]; then
  echo "Error: Directory '$SUBMODULE_PATH' not found."
  exit 1
fi

# Ensure .claude dir exists
mkdir -p .claude

SETTINGS_FILE=".claude/settings.local.json"
EXCLUDE_PATTERN="**/${SUBMODULE_PATH}/CLAUDE.md"

# Create settings file if not exists
if [[ ! -f "$SETTINGS_FILE" ]]; then
  echo '{}' > "$SETTINGS_FILE"
fi

# Check if pattern already exists
if jq -e --arg p "$EXCLUDE_PATTERN" '.claudeMdExcludes // [] | index($p) != null' "$SETTINGS_FILE" > /dev/null 2>&1; then
  echo "Already configured: $EXCLUDE_PATTERN"
  echo "No changes needed."
  exit 0
fi

# Add exclude pattern
jq --arg p "$EXCLUDE_PATTERN" '.claudeMdExcludes = (.claudeMdExcludes // [] | . + [$p])' \
  "$SETTINGS_FILE" > "${SETTINGS_FILE}.tmp" && mv "${SETTINGS_FILE}.tmp" "$SETTINGS_FILE"

echo "Added to $SETTINGS_FILE:"
echo "  claudeMdExcludes += [\"$EXCLUDE_PATTERN\"]"
echo ""
echo "Done. Claude Code will no longer load CLAUDE.md from $SUBMODULE_PATH."
