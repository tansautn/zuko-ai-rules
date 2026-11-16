#!/bin/bash
# Install claudeMdExcludes into parent project's .claude/settings.local.json
#
# Prevents this repo's CLAUDE.md from conflicting with parent project instructions
# when added as a git submodule.
#
# Optionally (step 2) installs the tasks-workflow hooks so Claude Code's native
# Task tools stay in sync with docs/tasks/ (see scripts/tasks/README.md).
#
# Usage:
#   Run from the PARENT project root (not from inside the submodule):
#     .agents/zuko-ai-rules/scripts/install-excludes.sh
#     # or with explicit path:
#     .agents/zuko-ai-rules/scripts/install-excludes.sh --submodule-path .agents/zuko-ai-rules
#     # non-interactive, with tasks hooks at project scope:
#     .agents/zuko-ai-rules/scripts/install-excludes.sh --tasks-hooks yes --hooks-scope project
#
# Requirements: jq (python3 only for the tasks hooks step)

set -euo pipefail

SUBMODULE_PATH=""
TASKS_HOOKS=""      # yes | no | "" (ask)
HOOKS_SCOPE=""      # project | local | user | "" (ask)
PYTHON_BIN=""       # override interpreter used in the hook command

# Parse args
while [[ $# -gt 0 ]]; do
  case "$1" in
    --submodule-path) SUBMODULE_PATH="$2"; shift 2 ;;
    --tasks-hooks)    TASKS_HOOKS="$2"; shift 2 ;;
    --hooks-scope)    HOOKS_SCOPE="$2"; shift 2 ;;
    --python)         PYTHON_BIN="$2"; shift 2 ;;
    -h|--help)
      echo "Usage: $0 [--submodule-path <path>] [--tasks-hooks yes|no] [--hooks-scope project|local|user] [--python <bin>]"
      echo ""
      echo "Step 1: Install claudeMdExcludes into .claude/settings.local.json"
      echo "Step 2: (optional) install tasks-workflow hooks (docs/tasks <-> Claude Code Task tools)"
      echo "Run from the PARENT project root."
      echo ""
      echo "Options:"
      echo "  --submodule-path  Path to this submodule (auto-detected from .gitmodules)"
      echo "  --tasks-hooks     yes|no — skip the question (default: ask; 'no' when not a TTY)"
      echo "  --hooks-scope     project (.claude/settings.json) | local (.claude/settings.local.json) | user (~/.claude/settings.json)"
      echo "  --python          Interpreter for the hook command (default: first working python3/python)"
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

# ---------------------------------------------------------------------------
# Step 1: claudeMdExcludes
# ---------------------------------------------------------------------------
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
else
  # Add exclude pattern
  jq --arg p "$EXCLUDE_PATTERN" '.claudeMdExcludes = (.claudeMdExcludes // [] | . + [$p])' \
    "$SETTINGS_FILE" > "${SETTINGS_FILE}.tmp" && mv "${SETTINGS_FILE}.tmp" "$SETTINGS_FILE"

  echo "Added to $SETTINGS_FILE:"
  echo "  claudeMdExcludes += [\"$EXCLUDE_PATTERN\"]"
  echo ""
  echo "Done. Claude Code will no longer load CLAUDE.md from $SUBMODULE_PATH."
fi

# ---------------------------------------------------------------------------
# Step 2 (optional): tasks-workflow hooks — docs/tasks/ <-> Claude Code Task tools
# ---------------------------------------------------------------------------
echo ""
if [[ -z "$TASKS_HOOKS" ]]; then
  if [[ -t 0 ]]; then
    read -rp "Install tasks-workflow hooks (sync docs/tasks/ with Claude Code Tasks via scripts/tasks/taskctl.py)? [y/N] " ans
    case "$ans" in y|Y|yes|YES) TASKS_HOOKS="yes" ;; *) TASKS_HOOKS="no" ;; esac
  else
    TASKS_HOOKS="no"
  fi
fi

if [[ "$TASKS_HOOKS" != "yes" ]]; then
  echo "Skipped tasks-workflow hooks. (re-run with --tasks-hooks yes to install later)"
  exit 0
fi

if [[ -z "$HOOKS_SCOPE" ]]; then
  echo "Where should the hooks go?"
  echo "  1) project  .claude/settings.json        (committed — everyone in this project)"
  echo "  2) local    .claude/settings.local.json  (this machine, this project only)"
  echo "  3) user     ~/.claude/settings.json      (you, in every project; hook is a no-op where docs/tasks/ is absent)"
  read -rp "Scope [1/2/3] (default 2): " sc
  case "$sc" in 1) HOOKS_SCOPE="project" ;; 3) HOOKS_SCOPE="user" ;; *) HOOKS_SCOPE="local" ;; esac
fi

case "$HOOKS_SCOPE" in
  project) HOOKS_FILE=".claude/settings.json"; TASKCTL="\$CLAUDE_PROJECT_DIR/${SUBMODULE_PATH}/scripts/tasks/taskctl.py" ;;
  local)   HOOKS_FILE=".claude/settings.local.json"; TASKCTL="\$CLAUDE_PROJECT_DIR/${SUBMODULE_PATH}/scripts/tasks/taskctl.py" ;;
  user)    HOOKS_FILE="$HOME/.claude/settings.json"; TASKCTL="$(cd "$SUBMODULE_PATH/scripts/tasks" && pwd)/taskctl.py" ;;
  *) echo "Error: --hooks-scope must be project|local|user"; exit 1 ;;
esac

# Pick a working interpreter (Windows: the Store 'python3' alias stub must be skipped)
if [[ -z "$PYTHON_BIN" ]]; then
  for cand in python3 python py; do
    if command -v "$cand" > /dev/null 2>&1 && "$cand" -c 'import sys; sys.exit(0 if sys.version_info >= (3, 10) else 1)' > /dev/null 2>&1; then
      PYTHON_BIN="$cand"; break
    fi
  done
fi
if [[ -z "$PYTHON_BIN" ]]; then
  echo "Error: no working python (>=3.10) found for the hook command. Use --python <bin>."
  exit 1
fi

HOOK_CMD="${PYTHON_BIN} \"${TASKCTL}\" hook"
START_CMD="${PYTHON_BIN} \"${TASKCTL}\" session-start"

mkdir -p "$(dirname "$HOOKS_FILE")"
[[ -f "$HOOKS_FILE" ]] || echo '{}' > "$HOOKS_FILE"

if jq -e '[.hooks // {} | .[]? | .[]? | .hooks[]? | .command // "" | test("taskctl\\.py")] | any' "$HOOKS_FILE" > /dev/null 2>&1; then
  echo "tasks-workflow hooks already present in $HOOKS_FILE. No changes."
else
  jq --arg hook "$HOOK_CMD" --arg start "$START_CMD" '
    .hooks = (.hooks // {})
    | .hooks.PostToolUse  = ((.hooks.PostToolUse  // []) + [{"matcher":"TaskCreate|TaskUpdate|TodoWrite","hooks":[{"type":"command","command":$hook,"timeout":15}]}])
    | .hooks.SessionStart = ((.hooks.SessionStart // []) + [{"matcher":"startup|resume","hooks":[{"type":"command","command":$start,"timeout":15}]}])
    | .env = ((.env // {}) + {"CLAUDE_CODE_ENABLE_TODO_TOOLS":"1"})
  ' "$HOOKS_FILE" > "${HOOKS_FILE}.tmp" && mv "${HOOKS_FILE}.tmp" "$HOOKS_FILE"
  echo "Added to $HOOKS_FILE:"
  echo "  hooks.PostToolUse  += [TaskCreate|TaskUpdate|TodoWrite -> $HOOK_CMD]"
  echo "  hooks.SessionStart += [startup|resume -> $START_CMD]"
  echo "  env.CLAUDE_CODE_ENABLE_TODO_TOOLS = \"1\"   (Task tools are off by default on newer models)"
fi

echo ""
echo "Done. Restart Claude Code in this project to load the hooks."
