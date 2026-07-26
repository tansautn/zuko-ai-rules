---
name: resume-cli-session
version: 1.0.0
description: >
  Resume work from a previous Claude Code CLI terminal session by extracting its conversation
  context and file changes. Use this skill whenever the user wants to continue, resume, or
  pick up from a CLI session — they'll provide a session UUID or ask to find one. Also use
  when the user mentions a session ID, wants to see what a past CLI session did, or asks to
  list/search their CLI sessions. This handles CLI sessions specifically (the .jsonl files
  under ~/.claude/projects/), not CCD desktop sessions.
---

## How it works

Claude Code CLI sessions are stored as JSONL files at:
```
~/.claude/projects/<project-slug>/<uuid>.jsonl
```

The project slug is the working directory path with separators replaced by `--`
(e.g., `D:\my\project` → `D--my-project`).

Related data lives in:
- `~/.claude/file-history/<uuid>/` — versioned backups of files the agent created or modified
- `~/.claude/session-env/<uuid>/` — session environment (often empty)

## Extraction script

A bundled script at `scripts/extract_session.py` (relative to this skill) handles parsing.
Run it via `python <skill-path>/scripts/extract_session.py`.

### Commands

```bash
# List recent sessions (all projects or filtered)
python scripts/extract_session.py --list --summary
python scripts/extract_session.py --list --project-slug D--my-project --summary

# Search sessions by keyword
python scripts/extract_session.py --search "some keyword" --summary

# Extract full context from a specific session
python scripts/extract_session.py <uuid> --summary

# JSON output (for programmatic use)
python scripts/extract_session.py <uuid>
```

## Workflow

### Step 1: Locate the session

If the user provides a UUID, go directly to extraction. If not, use these methods
**in priority order**:

#### 1a. Search via claude-mem (preferred — if available)

If `claude-mem` MCP tools are available (tools prefixed `mcp__plugin_claude-mem_`),
use them first — they index session observations with rich context:

```
# Search by topic/keyword
observation_search(query="SharedMap refactor")

# Browse timeline for recent work
timeline(range="today")  or  timeline(range="this week")

# Get specific observation details
get_observations([id1, id2, ...])
```

Observations often contain session IDs, file paths, and decision context that
make it easy to identify the right CLI session without parsing JSONL files.

#### 1b. Search via extraction script

Fall back to the bundled script if claude-mem is unavailable or didn't find results:

```bash
# List recent sessions for current project
python scripts/extract_session.py --list --project-slug <slug> --summary

# Search by keyword across all sessions
python scripts/extract_session.py --search "some keyword" --summary
```

The project slug for the current working directory: take the absolute path, replace
all `/` and `\` with `--`, and drop the trailing separator.

#### 1c. Ask the user

If neither method finds the session, ask the user for the UUID or more context about
what they were working on. They can find session UUIDs via:
- `claude --resume` in CLI (lists recent sessions)
- File explorer: `~/.claude/projects/<slug>/` contains `<uuid>.jsonl` files

### Step 2: Extract and summarize

Run the script with `--summary` to get a human-readable overview, then present to the user:

1. **Session title and metadata** (when, where, which branch)
2. **Files changed** — what was created vs modified
3. **Conversation flow** — the user's requests and what the assistant accomplished
4. **Where it stopped** — the last meaningful exchange, whether it completed or was interrupted

Pay attention to the end of the session:
- If the last messages are API errors / "again" / "continue" → the session was interrupted
- If there's a clear completion summary → the work was done
- Check the `last_prompt` field for what the user was last asking about

### Step 3: Verify current state

Before continuing the work:

1. Check if the files from the session still exist and are unchanged
2. Run any relevant tests if the session created them
3. Identify what was left incomplete

### Step 4: Continue

Pick up exactly where the CLI session left off. Use the extracted conversation
to understand the user's original intent and what remains to be done.

## Filtering rules

The script already filters noise, but when presenting results also skip:
- User messages that are just "again", "continue", or single-word retries
- Assistant messages that are just error text or status updates
- Focus on the substantive conversation: the original request, key decisions, and final state
