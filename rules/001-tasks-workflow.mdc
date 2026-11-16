---
description: Task Workflow System for project implementation across multiple task files within the docs/tasks/ directory. Integrated with the agent runtime's Task tools (Claude Code / Claude Desktop) via scripts/tasks/taskctl.py.
globs: **/*
alwaysApply: true
---

# Task Workflow System (Multi-File in `docs/tasks/` Directory)

- **Purpose:** Standardize task implementation with proper tracking and status updates across a distributed task list.
- **Implementation:** Tasks are distributed across `docs/tasks/tasks-N.md` files, indexed by `docs/tasks/tasks-index.md`.
- **Tooling:** `scripts/tasks/taskctl.py` (in the rules repo) reads/updates these files. Two modes — see [Tooling](#tooling-taskctlpy):
  - **Active** — the agent runs the CLI and reads its output.
  - **Passive** — the agent runtime invokes it as a hook when the agent uses its native Task tools; the agent only reads the `[taskctl] ...` line that appears in context.

## Overall Task Management Structure

- **Index File (`docs/tasks/tasks-index.md`):**

  - Contains the **Overall Project Task Summary** (Total Tasks, Pending, In Progress, Complete for the _entire_ project).
  - Contains the **Task File Index**, mapping Task ID ranges to specific `docs/tasks/tasks-N.md` files.
  - All counts and the file index are **computed** by `taskctl.py sync-index`. DO NOT edit them by hand when the CLI is available.

    ```markdown
    ## Overall Project Task Summary

    - **Total Tasks**: {Total for project}
    - **Pending**: {Pending for project}
    - **In Progress**: {In progress for project}
    - **Complete**: {Complete for project}

    ## Task File Index

    - `docs/tasks/tasks-1.md`: Contains Tasks {start_id_1} - {end_id_1} ({task_count_1} tasks)
    - `docs/tasks/tasks-2.md`: Contains Tasks {start_id_2} - {end_id_2} ({task_count_2} tasks)
    - ...
    ```

- **Task Files (`docs/tasks/tasks-N.md`):**

  - Each file starts with its own local summary:

    ```markdown
    ## Summary (tasks-N.md) // Clarify which task file this summary is for

    - **Tasks in this file**: {Count for this file}
    - **Task IDs**: {start_id_N} - {end_id_N} // e.g., 001 - 030
    - **Pending**: {Pending in this file}
    - **In Progress**: {In progress in this file}
    - **Complete**: {Complete in this file}
    ```

  - Followed by the `## Tasks` section containing individual tasks.

- **Task Structure (within `docs/tasks/tasks-N.md`)**

  - Tasks are defined with:

    ````markdown
    ### Task ID: {ID}

    - **Title**: Example title
    - **File**: example/file/path (relative to project root, excluding project root dir)
    - **Complete**: [ ]

    #### Prompt:

    ```markdown
    DETAILED PROMPT INCLUDING TARGET FILE PATH AND CONTEXT
    ```
    ````

  - `Complete` checkbox is the task status: `[ ]` pending, `[~]` in progress, `[x]` complete.
  - `- **Started**: <ISO8601>` / `- **Finished**: <ISO8601>` lines are added below `Complete` by `taskctl.py`; do not write them by hand.
  - Task ID in the file (`042`, `002-1`) is the **Task Ref** — the key that links a file task to a runtime task (`[T042]` prefix in the runtime task subject).

## Tooling: `taskctl.py`

`python <rules>/scripts/tasks/taskctl.py <cmd>` — run from the project root (or pass `--root`). Full reference: `scripts/tasks/README.md`.

### Active (agent calls, waits for output)

| Command | Use it when |
|---|---|
| `next --json` | user asks for "next task" — returns the first `[~]`, else the first `[ ]`, with `cc_subject` and full `prompt` |
| `show <ID> --json` | user names a Task ID |
| `list [--status pending\|in_progress\|completed]` | reporting progress |
| `start <ID>` / `finish <ID>` / `reopen <ID>` | changing status **yourself** (no hook, or no runtime Task tools) — also recomputes all summaries |
| `sync-index` | after adding/removing tasks by hand |
| `validate` | before working on a task file, and whenever another command refuses — lists what the CLI/hook cannot read (bad headers, fences, duplicate IDs) with file:line |

### Passive (runtime invokes the hook — nothing for the agent to call)

- The hook fires after `TaskCreate` / `TaskUpdate` / `TodoWrite`. It links the runtime task to the file task via the `[T{ID}]` subject prefix (or `metadata.task_ref`) and applies the status change to the file.
- You will see `[taskctl] T042 -> completed (docs/tasks/tasks-2.md)` in context. That line is the confirmation.
- No `[taskctl]` line after a status change → hook not installed → fall back to the **Active** commands.

## Task Management Workflow

### 1. Locating a Task

- **Preferred:** `taskctl.py next --json` (next task) or `taskctl.py show {ID} --json` (specific task). Run `taskctl.py validate` first when opening a task file for the first time in a session. The manual procedure below is the fallback when the CLI is unavailable.
- **When user requests "next task":**
  1. Open and consult `docs/tasks/tasks-index.md` to understand the overall project status and identify the sequence of task files.
  2. Iterate through `docs/tasks/tasks-1.md`, `docs/tasks/tasks-2.md`, etc., in numerical order as listed in the index.
  3. Within each `docs/tasks/tasks-N.md` file, find the first task where `Complete: [~]` (unfinished work takes priority); if none, the first task where `Complete: [ ]`. This is the next task.
  4. Note the `docs/tasks/tasks-N.md` file this task resides in.
- **When user specifies a Task ID (e.g., "Task 042"):**
  1. Open and consult `docs/tasks/tasks-index.md`.
  2. Read the "Task File Index" to determine which `docs/tasks/tasks-N.md` file contains that Task ID.
  3. Open the identified `docs/tasks/tasks-N.md` file (e.g., if Task 042 is in `tasks-2.md`, open `docs/tasks/tasks-2.md`).
  4. Locate the task with the specified `### Task ID: {ID}`.

### 2. Task Implementation

- **Mirror the task to the runtime task list before coding** (gives the user a live progress UI; the file keeps the full context):
  - `TaskCreate(subject="[T{ID}] {Title}", description=<full Prompt block>, activeForm=..., metadata={"task_ref": "{ID}", "file": "{File}", "tasks_file": "docs/tasks/tasks-N.md"})`
  - `TaskUpdate(taskId=<returned id>, status="in_progress")` → hook marks the file `[~]` + `Started`.
  - Runtime has no `TaskCreate`/`TaskUpdate`, or no `[taskctl]` line appears → run `taskctl.py start {ID}` instead.
- **Always review overall project context as needed:**
  ```javascript
  // ✅ DO: If architectural context is needed, refer to `docs/architecture.md` and other relevant architecture documents located in the `docs/` directory.
  // The task prompt itself should be the primary guide for implementation details.
  ```
- **Implement each task according to its prompt and specified `File` path.**
  ```javascript
  // ✅ DO: Focus implementation *only* on the file specified in the task's "File:" field.
  // ✅ DO: Follow the detailed instructions, context, and references within the task's "Prompt:" section.
  ```

### 3. Updating Task Status (Critical)

- After successfully implementing a task, one of (in order of preference):
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

### 4. Notification

- Inform the user of successful task completion.
- Provide a summary of changes made (files modified).
- State the Task ID and Title of the completed task and which `docs/tasks/tasks-N.md` file it was in.
- Quote the sync confirmation (`[taskctl] T{ID} -> completed ...`) or state that the status was updated manually.

## Task Creation Guidelines (If AI needs to add/modify tasks)

- **Adding New Tasks Based on User Requests:**

  1. **Determine Target Task File:** The user or AI must decide which `docs/tasks/tasks-N.md` file the new task belongs to.
     - If inserting into an existing sequence, identify the `docs/tasks/tasks-N.md` file.
     - If adding to the very end of the project and the last `tasks-N.md` is full (e.g., based on line count or task count), a new `docs/tasks/tasks-N+1.md` file might need to be conceptually created (the Task Master agent would typically handle new file creation).
  2. **ID Assignment:**
     - **End of a `docs/tasks/tasks-N.md` file:** Use the next sequential number based on the highest ID _globally_ (from `docs/tasks/tasks-index.md` "Total Tasks").
     - **Between Existing Tasks (within a `docs/tasks/tasks-N.md` file):** Use decimal extension format (e.g., 002-1, 002-2).
     ```javascript
     // ✅ DO: Ensure Task ID reflects implementation order.
     // ✅ DO: Use decimal extension for insertions.
     ```
  3. **Structure:** Add the task to the chosen `docs/tasks/tasks-N.md` file using the standard Task Structure.
  4. **Update Summaries:** run `taskctl.py sync-index` — it rewrites every local summary, the Overall Project Task Summary and the Task File Index (new `tasks-N+1.md` files included).
     - Manual fallback (no CLI): update the local summary in the modified `docs/tasks/tasks-N.md` file (increment "Tasks in this file", adjust ID range if necessary), update the "Total Tasks" and "Pending" counts in `docs/tasks/tasks-index.md`, and add any new `docs/tasks/tasks-N+1.md` file to the Task File Index.

- **Task Template (for reference when creating new tasks):**

  ````markdown
  ### Task ID: [ID]

  - **Title**: [Concise description]
  - **File**: [Target file path, no project root, e.g., src/components/MyComponent.js]
  - **Complete**: [ ]

  #### Prompt:

  ```markdown
  **Objective:** ...
  **File to Create/Modify:** {e.g., src/components/MyComponent.js}
  **User Story Context:** ...
  **Detailed Instructions:**
  ...
  **Acceptance Criteria (for this task):**
  ...
  ```
  ````

- **Nested code fences (REQUIRED):** an outer fence MUST be longer than any fence inside it.
  - Prompt body contains ` ``` ` → wrap the Prompt with ` ```` ` (4). Contains ` ```` ` → use 5, or switch the outer fence to `~~~`.
  - A 3-inside-3 fence closes the outer block early and the rest of the task renders as plain text (and `taskctl.py` reads a truncated prompt).
  - Status lines (`[~]`, `Started`, `Finished`) are outside the Prompt fence; never put them inside it.

## Navigation and File Management within `docs/tasks/` Directory

- **To find the "next pending task":**
  1. Open `docs/tasks/tasks-index.md`. Review the "Task File Index".
  2. Starting with `docs/tasks/tasks-1.md` (or the first file listed in the index), open it.
  3. Scan for the first task with `Complete: [~]`, else the first with `Complete: [ ]`. If found, this is the target task and its file.
  4. If not found in the current file, proceed to the next `docs/tasks/tasks-N.md` file listed in the index and repeat step 3.
- **To find a specific Task ID `{ID}`:**
  1. Open `docs/tasks/tasks-index.md`.
  2. Read the "Task File Index" to identify which `docs/tasks/tasks-N.md` file contains Task ID `{ID}`.
  3. Open that specific `docs/tasks/tasks-N.md` file (e.g., if `tasks-index.md` indicates Task 042 is in `docs/tasks/tasks-2.md`, then open `docs/tasks/tasks-2.md`).
  4. Search within that file for `### Task ID: {ID}`.
- **When updating task status:** `taskctl.py start|finish|reopen {ID}` (or the hook via `TaskUpdate`) does all of the following. Manual fallback:
  1. Identify the correct `docs/tasks/tasks-N.md` file for the task being updated.
  2. In that specific file, modify `Complete: [ ]` → `[~]` (started) or → `[x]` (done).
  3. **Critically, open `docs/tasks/tasks-index.md` and update the "Overall Project Task Summary" (Pending, In Progress and Complete counts).**
  4. Ensure both modified files (the `docs/tasks/tasks-N.md` and `docs/tasks/tasks-index.md`) are saved.

## Important Considerations for the AI IDE Agent

- All task-related files (`tasks-index.md` and `tasks-*.md`) are located within the `docs/tasks/` directory at the root of the project.
- The `docs/tasks/tasks-index.md` file is the **primary source of truth for overall project progress and for locating tasks within the specific `docs/tasks/tasks-N.md` files.**
- Always update `docs/tasks/tasks-index.md`'s summary when a task in any `docs/tasks/tasks-N.md` file is marked complete (the hook / `taskctl.py` does this; verify, don't redo).
- `docs/tasks/.cc-task-map.json` is a hook-owned cache (runtime task id ⇄ Task Ref). Never edit it by hand; it lives with `docs/tasks/` and follows that directory's git status.
- The files are the source of truth. If the runtime task list and the files disagree, the files win — re-create the runtime task from `taskctl.py show {ID} --json`.
- When asked for the "next task," ensure you are checking files in the correct numerical order as indicated by the `docs/tasks/tasks-index.md`.
- All other project documentation (PRD, Architecture, Stories, etc.) is expected to be in a `docs/` directory at the root of the project.
