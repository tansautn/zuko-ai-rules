#!/usr/bin/env python3
"""One-off: extend rules/001-tasks-workflow.mdc (v1) into v2 by anchored patches.
Everything not listed here stays byte-identical to the original."""
import sys
from pathlib import Path

src, dst = Path(sys.argv[1]), Path(sys.argv[2])
s = src.read_text(encoding="utf-8")


def patch(old: str, new: str) -> None:
    global s
    assert s.count(old) == 1, f"anchor not unique/found:\n{old[:120]}"
    s = s.replace(old, new, 1)


# ---- frontmatter ----------------------------------------------------------
patch(
    "description: Task Workflow System for project implementation across multiple task files within the docs/tasks/ directory.",
    "description: Task Workflow System for project implementation across multiple task files within the docs/tasks/ directory. Integrated with the agent runtime's Task tools (Claude Code / Claude Desktop) via scripts/tasks/taskctl.py.",
)

# ---- intro ------------------------------------------------------------------
patch(
    "- **Implementation:** Tasks are distributed across `docs/tasks/tasks-N.md` files, indexed by `docs/tasks/tasks-index.md`.\n",
    "- **Implementation:** Tasks are distributed across `docs/tasks/tasks-N.md` files, indexed by `docs/tasks/tasks-index.md`.\n"
    "- **Tooling:** `scripts/tasks/taskctl.py` (in the rules repo) reads/updates these files. Two modes — see [Tooling](#tooling-taskctlpy):\n"
    "  - **Active** — the agent runs the CLI and reads its output.\n"
    "  - **Passive** — the agent runtime invokes it as a hook when the agent uses its native Task tools; the agent only reads the `[taskctl] ...` line that appears in context.\n",
)

# ---- index summary block ---------------------------------------------------
patch(
    "    - **Total Tasks**: {Total for project}\n    - **Pending**: {Pending for project}\n    - **Complete**: {Complete for project}\n",
    "    - **Total Tasks**: {Total for project}\n    - **Pending**: {Pending for project}\n    - **In Progress**: {In progress for project}\n    - **Complete**: {Complete for project}\n",
)
patch(
    "  - Contains the **Task File Index**, mapping Task ID ranges to specific `docs/tasks/tasks-N.md` files.\n",
    "  - Contains the **Task File Index**, mapping Task ID ranges to specific `docs/tasks/tasks-N.md` files.\n"
    "  - All counts and the file index are **computed** by `taskctl.py sync-index`. DO NOT edit them by hand when the CLI is available.\n",
)

# ---- local summary block ---------------------------------------------------
patch(
    "    - **Tasks in this file**: {Count for this file}\n    - **Task IDs**: {start_id_N} - {end_id_N} // e.g., 001 - 030\n",
    "    - **Tasks in this file**: {Count for this file}\n    - **Task IDs**: {start_id_N} - {end_id_N} // e.g., 001 - 030\n"
    "    - **Pending**: {Pending in this file}\n    - **In Progress**: {In progress in this file}\n    - **Complete**: {Complete in this file}\n",
)

# ---- task structure: fix broken fence + status legend ----------------------
patch(
    "    ```markdown\n    DETAILED PROMPT INCLUDING TARGET FILE PATH AND CONTEXT\n    ```\n    ````\n\n    ```\n\n    ```\n\n",
    "    ```markdown\n    DETAILED PROMPT INCLUDING TARGET FILE PATH AND CONTEXT\n    ```\n    ````\n\n"
    "  - `Complete` checkbox is the task status: `[ ]` pending, `[~]` in progress, `[x]` complete.\n"
    "  - `- **Started**: <ISO8601>` / `- **Finished**: <ISO8601>` lines are added below `Complete` by `taskctl.py`; do not write them by hand.\n"
    "  - Task ID in the file (`042`, `002-1`) is the **Task Ref** — the key that links a file task to a runtime task (`[T042]` prefix in the runtime task subject).\n\n",
)

# ---- new section: Tooling (inserted before Task Management Workflow) -------
patch(
    "## Task Management Workflow\n\n### 1. Locating a Task\n",
    """## Tooling: `taskctl.py`

`python <rules>/scripts/tasks/taskctl.py <cmd>` — run from the project root (or pass `--root`). Full reference: `scripts/tasks/README.md`.

### Active (agent calls, waits for output)

| Command | Use it when |
|---|---|
| `next --json` | user asks for "next task" — returns the first `[~]`, else the first `[ ]`, with `cc_subject` and full `prompt` |
| `show <ID> --json` | user names a Task ID |
| `list [--status pending\\|in_progress\\|completed]` | reporting progress |
| `start <ID>` / `finish <ID>` / `reopen <ID>` | changing status **yourself** (no hook, or no runtime Task tools) — also recomputes all summaries |
| `sync-index` | after adding/removing tasks by hand |
| `validate` | before working on a task file, and whenever another command refuses — lists what the CLI/hook cannot read (bad headers, fences, duplicate IDs) with file:line |

### Passive (runtime invokes the hook — nothing for the agent to call)

- The hook fires after `TaskCreate` / `TaskUpdate` / `TodoWrite`. It links the runtime task to the file task via the `[T{ID}]` subject prefix (or `metadata.task_ref`) and applies the status change to the file.
- You will see `[taskctl] T042 -> completed (docs/tasks/tasks-2.md)` in context. That line is the confirmation.
- No `[taskctl]` line after a status change → hook not installed → fall back to the **Active** commands.

## Task Management Workflow

### 1. Locating a Task
""",
)

# ---- 1. Locating a Task ------------------------------------------------------
patch(
    "- **When user requests \"next task\":**\n  1. Open and consult `docs/tasks/tasks-index.md`",
    "- **Preferred:** `taskctl.py next --json` (next task) or `taskctl.py show {ID} --json` (specific task). Run `taskctl.py validate` first when opening a task file for the first time in a session. The manual procedure below is the fallback when the CLI is unavailable.\n"
    "- **When user requests \"next task\":**\n  1. Open and consult `docs/tasks/tasks-index.md`",
)
patch(
    "  3. Within each `docs/tasks/tasks-N.md` file, find the first task where `Complete: [ ]`. This is the next task.\n",
    "  3. Within each `docs/tasks/tasks-N.md` file, find the first task where `Complete: [~]` (unfinished work takes priority); if none, the first task where `Complete: [ ]`. This is the next task.\n",
)

# ---- 2. Task Implementation ----------------------------------------------------
patch(
    "### 2. Task Implementation\n\n- **Always review overall project context as needed:**",
    "### 2. Task Implementation\n\n"
    "- **Mirror the task to the runtime task list before coding** (gives the user a live progress UI; the file keeps the full context):\n"
    "  - `TaskCreate(subject=\"[T{ID}] {Title}\", description=<full Prompt block>, activeForm=..., metadata={\"task_ref\": \"{ID}\", \"file\": \"{File}\", \"tasks_file\": \"docs/tasks/tasks-N.md\"})`\n"
    "  - `TaskUpdate(taskId=<returned id>, status=\"in_progress\")` → hook marks the file `[~]` + `Started`.\n"
    "  - Runtime has no `TaskCreate`/`TaskUpdate`, or no `[taskctl]` line appears → run `taskctl.py start {ID}` instead.\n"
    "- **Always review overall project context as needed:**",
)

# ---- 3. Updating Task Status --------------------------------------------------
patch(
    """- After successfully implementing a task:
  1. **Locate the task** within its specific `docs/tasks/tasks-N.md` file (as identified in Step 1).
  2. **Change its status:** Modify `Complete: [ ]` to `Complete: [x]` in that specific `docs/tasks/tasks-N.md` file.
  3. **Update the local summary within that `docs/tasks/tasks-N.md` file (Optional but Recommended):**
     - If feasible, decrement "Pending" and increment "Complete" counts for _that file's specific summary_. This is secondary to updating the main index.
  4. **Update the Overall Project Task Summary in `docs/tasks/tasks-index.md`:**
     - Decrement "Pending" by 1.
     - Increment "Complete" by 1.
  5. **Save changes** to both the modified `docs/tasks/tasks-N.md` file and `docs/tasks/tasks-index.md`.
  ```javascript
  // ✅ DO: Update "Complete: [ ]" to "Complete: [x]" in the correct `docs/tasks/tasks-N.md` file.
  // ✅ DO: Update "Pending" and "Complete" counts in `docs/tasks/tasks-index.md`.
  // ❌ DON'T: Modify task IDs, titles, or prompts unless explicitly instructed for a correction.
  ```
""",
    """- After successfully implementing a task, one of (in order of preference):
  1. **Passive:** `TaskUpdate(taskId=<id>, status="completed")` → hook sets `Complete: [x]`, adds `Finished`, recomputes every summary. Confirm by the `[taskctl] T{ID} -> completed` line.
  2. **Active:** `taskctl.py finish {ID}` — same result, run it yourself.
  3. **Manual fallback (no CLI):**
     1. **Locate the task** within its specific `docs/tasks/tasks-N.md` file (as identified in Step 1).
     2. **Change its status:** Modify `Complete: [ ]` (or `[~]`) to `Complete: [x]` in that specific `docs/tasks/tasks-N.md` file.
     3. **Update the local summary within that `docs/tasks/tasks-N.md` file:** decrement "Pending"/"In Progress", increment "Complete".
     4. **Update the Overall Project Task Summary in `docs/tasks/tasks-index.md`:** decrement "Pending"/"In Progress" by 1, increment "Complete" by 1.
     5. **Save changes** to both the modified `docs/tasks/tasks-N.md` file and `docs/tasks/tasks-index.md`.
  ```javascript
  // ✅ DO: Let the hook or `taskctl.py finish` update "Complete" and all counts.
  // ✅ DO: Confirm the sync via the `[taskctl] ...` line; if it is missing, run the CLI.
  // ❌ DON'T: Edit counts by hand while the CLI is available.
  // ❌ DON'T: Modify task IDs, titles, or prompts unless explicitly instructed for a correction.
  ```
""",
)

# ---- 4. Notification -------------------------------------------------------------
patch(
    "- State the Task ID and Title of the completed task and which `docs/tasks/tasks-N.md` file it was in.\n",
    "- State the Task ID and Title of the completed task and which `docs/tasks/tasks-N.md` file it was in.\n"
    "- Quote the sync confirmation (`[taskctl] T{ID} -> completed ...`) or state that the status was updated manually.\n",
)

# ---- Task Creation: summaries via sync-index --------------------------------------
patch(
    """  4. **Update Summaries:**
     - Update the local summary in the modified `docs/tasks/tasks-N.md` file (increment "Tasks in this file", adjust ID range if necessary).
     - Update the "Total Tasks" and "Pending" counts in `docs/tasks/tasks-index.md`.
     - If a new `docs/tasks/tasks-N+1.md` file was notionally created, update the Task File Index in `docs/tasks/tasks-index.md`.
""",
    """  4. **Update Summaries:** run `taskctl.py sync-index` — it rewrites every local summary, the Overall Project Task Summary and the Task File Index (new `tasks-N+1.md` files included).
     - Manual fallback (no CLI): update the local summary in the modified `docs/tasks/tasks-N.md` file (increment "Tasks in this file", adjust ID range if necessary), update the "Total Tasks" and "Pending" counts in `docs/tasks/tasks-index.md`, and add any new `docs/tasks/tasks-N+1.md` file to the Task File Index.
""",
)

# ---- Fence nesting rule (after Task Template) --------------------------------------
patch(
    """  **Acceptance Criteria (for this task):**
  ...
  ```
  ````

## Navigation and File Management within `docs/tasks/` Directory
""",
    """  **Acceptance Criteria (for this task):**
  ...
  ```
  ````

- **Nested code fences (REQUIRED):** an outer fence MUST be longer than any fence inside it.
  - Prompt body contains ` ``` ` → wrap the Prompt with ` ```` ` (4). Contains ` ```` ` → use 5, or switch the outer fence to `~~~`.
  - A 3-inside-3 fence closes the outer block early and the rest of the task renders as plain text (and `taskctl.py` reads a truncated prompt).
  - Status lines (`[~]`, `Started`, `Finished`) are outside the Prompt fence; never put them inside it.

## Navigation and File Management within `docs/tasks/` Directory
""",
)

# ---- Navigation: status update ----------------------------------------------------
patch(
    """- **When updating task status:**
  1. Identify the correct `docs/tasks/tasks-N.md` file for the task being updated.
  2. In that specific file, modify `Complete: [ ]` to `Complete: [x]`.
  3. **Critically, open `docs/tasks/tasks-index.md` and update the "Overall Project Task Summary" (Pending and Complete counts).**
  4. Ensure both modified files (the `docs/tasks/tasks-N.md` and `docs/tasks/tasks-index.md`) are saved.
""",
    """- **When updating task status:** `taskctl.py start|finish|reopen {ID}` (or the hook via `TaskUpdate`) does all of the following. Manual fallback:
  1. Identify the correct `docs/tasks/tasks-N.md` file for the task being updated.
  2. In that specific file, modify `Complete: [ ]` → `[~]` (started) or → `[x]` (done).
  3. **Critically, open `docs/tasks/tasks-index.md` and update the "Overall Project Task Summary" (Pending, In Progress and Complete counts).**
  4. Ensure both modified files (the `docs/tasks/tasks-N.md` and `docs/tasks/tasks-index.md`) are saved.
""",
)

# ---- Important Considerations ---------------------------------------------------------
patch(
    "- Always update `docs/tasks/tasks-index.md`'s summary when a task in any `docs/tasks/tasks-N.md` file is marked complete.\n",
    "- Always update `docs/tasks/tasks-index.md`'s summary when a task in any `docs/tasks/tasks-N.md` file is marked complete (the hook / `taskctl.py` does this; verify, don't redo).\n"
    "- `docs/tasks/.cc-task-map.json` is a hook-owned cache (runtime task id ⇄ Task Ref). Never edit it by hand; it lives with `docs/tasks/` and follows that directory's git status.\n"
    "- The files are the source of truth. If the runtime task list and the files disagree, the files win — re-create the runtime task from `taskctl.py show {ID} --json`.\n",
)

# ---- small consistency edits -------------------------------------------------------
patch(
    "  - Contains the **Overall Project Task Summary** (Total Tasks, Pending, Complete for the _entire_ project).\n",
    "  - Contains the **Overall Project Task Summary** (Total Tasks, Pending, In Progress, Complete for the _entire_ project).\n",
)
patch(
    "  3. Scan for the first task with `Complete: [ ]`. If found, this is the target task and its file.\n",
    "  3. Scan for the first task with `Complete: [~]`, else the first with `Complete: [ ]`. If found, this is the target task and its file.\n",
)

dst.write_text(s, encoding="utf-8")
print(f"wrote {dst} ({len(s.splitlines())} lines)")
