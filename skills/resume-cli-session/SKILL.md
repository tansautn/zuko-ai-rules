---
name: resume-cli-session
version: 1.1.0
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

### Title records (precedence)

A session's display title can come from three record types. Resolve in this order:

| `type` | field | meaning |
|---|---|---|
| `custom-title` | `customTitle` | user set it via `/rename` (highest priority) |
| `summary` | `summary` | auto summary |
| `ai-title` | `aiTitle` | model-generated title |

If none exist, the extraction script derives a title from the first real user prompt, so
sessions should never show as `(untitled)`.

## Extraction script

A bundled script at `scripts/extract_session.py` (relative to this skill) handles parsing.
Run it via `python <skill-path>/scripts/extract_session.py`.

### Commands

```bash
# List recent sessions (all projects or filtered); --today limits to today's sessions
python scripts/extract_session.py --list --summary
python scripts/extract_session.py --list --today --summary
python scripts/extract_session.py --list --project-slug D--my-project --summary

# Search sessions by keyword
python scripts/extract_session.py --search "some keyword" --summary

# Extract full context from a specific session
python scripts/extract_session.py <uuid> --summary

# (Step 2.5 helpers — rename the CURRENT running session, see below)
python scripts/extract_session.py --find-live --exclude <resumed-uuid>
python scripts/extract_session.py --write-title --target <transcript.jsonl> --title "<text>"
```

## Workflow

### Step 1: Locate the session

If the user provides a UUID, go directly to extraction. If not, use these methods
**in priority order**:

#### 1a. Search via claude-mem (preferred — if available)

If `claude-mem` MCP tools are available (tools prefixed `mcp__plugin_claude-mem_`),
use them first — `observation_search`, `timeline`, `get_observations`. Observations often
contain session IDs, file paths, and decision context.

#### 1b. Search via extraction script

```bash
python scripts/extract_session.py --list --today --project-slug <slug> --summary
python scripts/extract_session.py --search "some keyword" --project-slug <slug> --summary
```

The project slug for the current working directory: take the absolute path, replace
all `/` and `\` with `--`, and drop the trailing separator.

#### 1c. Ask the user

If neither finds it, ask for the UUID or more context. Users can find UUIDs via
`claude --resume` or `~/.claude/projects/<slug>/`.

### Step 2: Extract and summarize

Run the script with `--summary`, then present:

1. **Session title and metadata** (when, where, which branch)
2. **Files changed** — created vs modified
3. **Conversation flow** — the user's requests and what the assistant accomplished
4. **Where it stopped** — the last meaningful exchange; check `last_prompt`

Interruption vs completion cues:
- Last messages are API errors / "again" / "continue" → interrupted
- Clear completion summary → done

### Step 2.5: Rename the current running session (auto)

The session that is running this skill is a *different* session from the one being resumed.
By default it is titled after this skill (`Resume CLI session`), so resuming several per day
makes them indistinguishable. Fix it automatically by writing a `custom-title` record (the
same record `/rename` writes) into the **current** session's transcript.

> Best-effort: this uses an undocumented record format. The host may ignore or overwrite it;
> if so, the end-of-message banner (below) is the fallback. Never block the resume on this.

```mermaid
flowchart LR
  A[resumed uuid known] --> B[find current transcript]
  B -->|env CLAUDE_TRANSCRIPT_PATH if set| C[target path]
  B -->|else --find-live --exclude resumed-uuid| C
  C --> D[build title:<br/>'[ RESUMED ] ' + session-title + ' · ' + uuid first8]
  D --> E[--write-title --target target --title title]
  E -->|ok| F[done]
  E -->|error| G[skip silently, rely on banner]
```

Steps:
1. Determine the current transcript path. Prefer an explicit path if the environment exposes
   one (e.g. `CLAUDE_TRANSCRIPT_PATH`). Otherwise:
   ```bash
   python scripts/extract_session.py --find-live --exclude <resumed-uuid>
   ```
2. Build the title: the resumed session's resolved title, prefixed `[ RESUMED ] ` and
   suffixed with ` · ` + the first 8 chars of the resumed uuid.
3. Write it:
   ```bash
   python scripts/extract_session.py --write-title --target "<path>" --title "[ RESUMED ] <title> · <uuid8>"
   ```
4. If it errors, continue silently — do not retry, do not surface the failure.

### Step 3: Verify current state

1. Check the session's files still exist / unchanged
2. Run relevant tests if any were created
3. Identify what's incomplete

### Step 4: Continue

Pick up exactly where the CLI session left off.

### Step 5: End-of-message banner (always)

At the **end** of the response (never at the top), append a one-line banner so the resumed
context is visible even if the sidebar rename didn't take:

```
──────────────────────────────────────────
[ RESUMED ] <session-title> · <uuid8> · <project-slug>
```

## Filtering rules

The script filters noise, but when presenting also skip:
- User messages that are just "again", "continue", "go", or single-word retries
- Assistant messages that are just error text or status updates
- Focus on the original request, key decisions, and final state
