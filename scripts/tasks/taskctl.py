#!/usr/bin/env python3
"""
taskctl.py — CLI + Claude Code hook bridge for the docs/tasks/ workflow.

Source of truth : docs/tasks/tasks-N.md (+ tasks-index.md)
Live mirror     : Claude Code Task tools (TaskCreate / TaskUpdate / TodoWrite)

Stdlib only. Works on Windows (Git Bash / PowerShell) and Linux.

Usage:
  taskctl.py list [--status pending|in_progress|completed|all] [--json]
  taskctl.py next [--json]
  taskctl.py show <ref> [--json]
  taskctl.py start <ref> | finish <ref> | reopen <ref>
  taskctl.py sync-index
  taskctl.py validate [--json]   # exit 1 on errors; mutating commands refuse files with errors
  taskctl.py hook            # reads PostToolUse JSON on stdin, always exits 0
  taskctl.py session-start   # SessionStart hook: injects task summary + next task

Global options:
  --root <dir>        project root (default: $CLAUDE_PROJECT_DIR or cwd)
  --tasks-dir <rel>   tasks dir relative to root (default: docs/tasks)
"""
from __future__ import annotations

import argparse
import json
import os
import re
import sys
from dataclasses import dataclass, field, asdict
from datetime import datetime
from pathlib import Path
from typing import Iterable

# --------------------------------------------------------------------------- #
# Constants
# --------------------------------------------------------------------------- #

STATUS_PENDING = "pending"
STATUS_IN_PROGRESS = "in_progress"
STATUS_COMPLETED = "completed"
ALL_STATUSES = (STATUS_PENDING, STATUS_IN_PROGRESS, STATUS_COMPLETED)

CHECKBOX_TO_STATUS = {" ": STATUS_PENDING, "~": STATUS_IN_PROGRESS, "x": STATUS_COMPLETED, "X": STATUS_COMPLETED}
STATUS_TO_CHECKBOX = {STATUS_PENDING: " ", STATUS_IN_PROGRESS: "~", STATUS_COMPLETED: "x"}

TASK_HEADER_RE = re.compile(r"^###\s+Task ID:\s*(?P<id>[A-Za-z]?\d+(?:-\d+)*)[ \t]*$", re.M)
TITLE_RE = re.compile(r"^-\s+\*\*Title\*\*:\s*(?P<v>.*)$", re.M)
FILE_RE = re.compile(r"^-\s+\*\*File\*\*:\s*(?P<v>.*)$", re.M)
COMPLETE_RE = re.compile(r"^(?P<prefix>-\s+\*\*Complete\*\*:\s*)\[(?P<box>[ xX~])\][ \t]*$", re.M)
STARTED_RE = re.compile(r"^-\s+\*\*Started\*\*:\s*(?P<v>.*)$", re.M)
FINISHED_RE = re.compile(r"^-\s+\*\*Finished\*\*:\s*(?P<v>.*)$", re.M)
PROMPT_HEADER_RE = re.compile(r"^####\s+Prompt:\s*$", re.M)
FENCE_RE = re.compile(r"^(?P<fence>`{3,}|~{3,})[^\n]*\n(?P<body>.*?)^(?P=fence)[ \t]*$", re.M | re.S)

TASK_FILE_RE = re.compile(r"^tasks-(\d+)\.md$")
INDEX_FILE = "tasks-index.md"
MAP_FILE = ".cc-task-map.json"

# Ref extracted from a CC task subject / todo content: "[T042] ..." or "[042] ..."
SUBJECT_REF_RE = re.compile(r"^\s*\[T?(?P<ref>\d+(?:-\d+)*)\]")
CC_ID_IN_TEXT_RE = re.compile(r"Task\s+#(?P<id>\d+)", re.I)

# fix stdout issues Windows
sys.stdout.reconfigure(encoding="utf-8")

# --------------------------------------------------------------------------- #
# Helpers
# --------------------------------------------------------------------------- #

def now_iso() -> str:
    return datetime.now().astimezone().replace(microsecond=0).isoformat()


def norm_ref(raw: str) -> str:
    """'T42' / '042' / '42' -> '042' ; '2-1' -> '002-1'. Used only for comparison."""
    raw = raw.strip().lstrip("Tt")
    head, *tail = raw.split("-")
    try:
        head = f"{int(head):03d}"
    except ValueError:
        pass
    return "-".join([head, *tail])


def ref_sort_key(ref: str) -> tuple:
    parts = norm_ref(ref).split("-")
    key = []
    for p in parts:
        key.append((0, int(p)) if p.isdigit() else (1, p))
    return tuple(key)


def eprint(*a, **k) -> None:
    print(*a, file=sys.stderr, **k)


# --------------------------------------------------------------------------- #
# Model
# --------------------------------------------------------------------------- #

@dataclass
class Task:
    ref: str
    title: str
    file: str
    status: str
    tasks_file: str          # e.g. docs/tasks/tasks-2.md (relative to root, posix)
    started: str | None = None
    finished: str | None = None
    prompt: str = ""
    span: tuple[int, int] = field(default=(0, 0), repr=False)  # char offsets in tasks_file

    def to_public(self, with_prompt: bool = False) -> dict:
        d = asdict(self)
        d.pop("span")
        if not with_prompt:
            d.pop("prompt")
        d["cc_subject"] = f"[T{self.ref}] {self.title}"
        return d


@dataclass
class TaskFile:
    path: Path
    number: int
    content: str
    tasks: list[Task]


@dataclass
class Issue:
    level: str            # "error" | "warning"
    file: str             # relative posix path
    line: int | None
    msg: str

    def __str__(self) -> str:
        loc = f"{self.file}:{self.line}" if self.line else self.file
        return f"{self.level.upper():7} {loc}: {self.msg}"


class TaskStore:
    def __init__(self, root: Path, tasks_dir: str):
        self.root = root
        self.tasks_dir = root / tasks_dir
        self.tasks_dir_rel = Path(tasks_dir).as_posix()
        self.files: list[TaskFile] = []
        self.issues: list[Issue] = []
        self.load()

    # ---- loading ------------------------------------------------------------
    def load(self) -> None:
        self.files = []
        if not self.tasks_dir.is_dir():
            raise SystemExit(f"tasks dir not found: {self.tasks_dir}")
        candidates = []
        for p in self.tasks_dir.iterdir():
            m = TASK_FILE_RE.match(p.name)
            if m:
                candidates.append((int(m.group(1)), p))
        for number, p in sorted(candidates):
            content = p.read_text(encoding="utf-8")
            self.files.append(TaskFile(p, number, content, self._parse(p, content)))
        self.issues = self.validate()

    # ---- validation ----------------------------------------------------------
    def errors(self, file_rel: str | None = None) -> list[Issue]:
        return [i for i in self.issues if i.level == "error" and (file_rel is None or i.file == file_rel)]

    def _require_valid(self, file_rel: str | None, what: str) -> None:
        errs = self.errors(file_rel)
        if errs:
            where = file_rel or self.tasks_dir_rel
            raise SystemExit(f"{what} refused: {len(errs)} validation error(s) in {where} — run `taskctl.py validate`")

    def validate(self) -> list[Issue]:
        issues: list[Issue] = []
        seen: dict[str, str] = {}

        if not self.files:
            issues.append(Issue("error", self.tasks_dir_rel, None, "no tasks-N.md files found"))
        if not (self.tasks_dir / INDEX_FILE).exists():
            issues.append(Issue("warning", f"{self.tasks_dir_rel}/{INDEX_FILE}", None, "missing (sync-index will create it)"))
        for p in sorted(self.tasks_dir.iterdir()):
            if p.is_file() and p.suffix == ".md" and p.name != INDEX_FILE and not TASK_FILE_RE.match(p.name):
                issues.append(Issue("warning", self._rel(p), None, "ignored: task files must be named tasks-N.md"))

        for tf in self.files:
            issues.extend(self._validate_file(tf))
            for t in tf.tasks:
                key = norm_ref(t.ref)
                if key in seen:
                    issues.append(Issue("error", tf_rel(tf, self), _line_of(tf.content, t.span[0]),
                                        f"duplicate Task ID {t.ref} (also in {seen[key]})"))
                seen[key] = tf_rel(tf, self)

        mp = self.map_path()
        if mp.exists():
            try:
                m = json.loads(mp.read_text(encoding="utf-8"))
                if not isinstance(m, dict):
                    raise ValueError("not an object")
                stale = [r for r in m.values() if norm_ref(str(r)) not in seen]
                if stale:
                    issues.append(Issue("warning", self._rel(mp), None, f"maps to unknown Task IDs: {', '.join(map(str, stale))}"))
            except (json.JSONDecodeError, ValueError) as e:
                issues.append(Issue("warning", self._rel(mp), None, f"invalid JSON ({e}); hook will reset it"))
        issues.sort(key=lambda i: (i.file, i.line or 0, i.level))
        return issues

    def _validate_file(self, tf: TaskFile) -> list[Issue]:
        rel = tf_rel(tf, self)
        c = tf.content
        out: list[Issue] = []

        # headers that look like task headers but the parser cannot read -> their content merges into the previous task
        for i, line in enumerate(c.splitlines(), 1):
            if line.startswith("###") and "Task ID" in line and not TASK_HEADER_RE.match(line):
                out.append(Issue("error", rel, i, f"malformed task header {line.strip()!r}; expected '### Task ID: 042' (digits, optional -N suffix)"))
        if not re.search(r"^## Summary\b", c, re.M):
            out.append(Issue("warning", rel, None, "missing '## Summary (tasks-N.md)' section (sync-index will add it)"))
        if not re.search(r"^## Tasks\b", c, re.M):
            out.append(Issue("warning", rel, None, "missing '## Tasks' section"))
        if not tf.tasks:
            out.append(Issue("warning", rel, None, "no tasks in file"))

        prev_key = None
        for t in tf.tasks:
            block = c[t.span[0]:t.span[1]]
            at = _line_of(c, t.span[0])
            if not t.title:
                out.append(Issue("error", rel, at, f"T{t.ref}: missing '- **Title**:'"))
            if not t.file:
                out.append(Issue("error", rel, at, f"T{t.ref}: missing '- **File**:'"))
            if not COMPLETE_RE.search(block):
                out.append(Issue("error", rel, at, f"T{t.ref}: missing or malformed '- **Complete**: [ ]' (allowed: [ ] [~] [x])"))
            if t.status == STATUS_IN_PROGRESS and not t.started:
                out.append(Issue("warning", rel, at, f"T{t.ref}: [~] without '- **Started**:' (reopen + start to fix)"))
            if t.status == STATUS_PENDING and (t.started or t.finished):
                out.append(Issue("warning", rel, at, f"T{t.ref}: [ ] but has Started/Finished lines"))

            pm = PROMPT_HEADER_RE.search(block)
            if not pm:
                out.append(Issue("error", rel, at, f"T{t.ref}: missing '#### Prompt:'"))
            else:
                out.extend(self._validate_prompt_fence(t, block, pm.end(), rel, _line_of(c, t.span[0] + pm.start())))

            key = ref_sort_key(t.ref)
            if prev_key is not None and key < prev_key:
                out.append(Issue("warning", rel, at, f"T{t.ref}: out of order (IDs should increase within a file)"))
            prev_key = key
        return out

    @staticmethod
    def _validate_prompt_fence(t: Task, block: str, start: int, rel: str, prompt_line: int) -> list[Issue]:
        out: list[Issue] = []
        tail = block[start:]
        opening = re.search(r"^(`{3,}|~{3,})", tail, re.M)
        if not opening:
            return [Issue("error", rel, prompt_line, f"T{t.ref}: Prompt has no code fence")]
        fence = opening.group(1)
        closed = FENCE_RE.search(block, start)
        if not closed:
            return [Issue("error", rel, prompt_line, f"T{t.ref}: Prompt fence {fence} is never closed — rest of the file is swallowed")]
        inner = [m.group(1) for m in re.finditer(r"^(`{3,}|~{3,})", closed.group("body"), re.M)]
        after = block[closed.end():]
        leftover = re.search(r"^(`{3,}|~{3,})", after, re.M)
        if leftover:
            out.append(Issue("error", rel, prompt_line,
                             f"T{t.ref}: fence line {leftover.group(1)!r} after the Prompt block — nested fence closed the outer {fence} early; "
                             f"use an outer fence longer than any inner one (e.g. ```` or ~~~)"))
        for f in inner:
            if f[0] == fence[0] and len(f) >= len(fence):
                out.append(Issue("error", rel, prompt_line, f"T{t.ref}: inner fence {f!r} is not shorter than outer {fence!r}"))
        if not closed.group("body").strip():
            out.append(Issue("warning", rel, prompt_line, f"T{t.ref}: Prompt is empty"))
        return out

    def _rel(self, p: Path) -> str:
        return p.relative_to(self.root).as_posix()

    def _parse(self, path: Path, content: str) -> list[Task]:
        headers = list(TASK_HEADER_RE.finditer(content))
        tasks: list[Task] = []
        for i, h in enumerate(headers):
            start = h.start()
            end = headers[i + 1].start() if i + 1 < len(headers) else len(content)
            block = content[start:end]
            cm = COMPLETE_RE.search(block)
            status = CHECKBOX_TO_STATUS.get(cm.group("box"), STATUS_PENDING) if cm else STATUS_PENDING
            tm, fm = TITLE_RE.search(block), FILE_RE.search(block)
            sm, fim = STARTED_RE.search(block), FINISHED_RE.search(block)
            prompt = ""
            pm = PROMPT_HEADER_RE.search(block)
            if pm:
                fence = FENCE_RE.search(block, pm.end())
                if fence:
                    prompt = fence.group("body").rstrip("\n")
            tasks.append(Task(
                ref=h.group("id").lstrip("Tt"),
                title=(tm.group("v").strip() if tm else ""),
                file=(fm.group("v").strip() if fm else ""),
                status=status,
                tasks_file=self._rel(path),
                started=(sm.group("v").strip() if sm else None),
                finished=(fim.group("v").strip() if fim else None),
                prompt=prompt,
                span=(start, end),
            ))
        return tasks

    # ---- queries ------------------------------------------------------------
    def all_tasks(self) -> list[Task]:
        return [t for f in self.files for t in f.tasks]

    def find(self, ref: str) -> tuple[TaskFile, Task] | None:
        want = norm_ref(ref)
        for f in self.files:
            for t in f.tasks:
                if norm_ref(t.ref) == want:
                    return f, t
        return None

    def next_task(self) -> Task | None:
        tasks = self.all_tasks()
        for t in tasks:
            if t.status == STATUS_IN_PROGRESS:
                return t
        for t in tasks:
            if t.status == STATUS_PENDING:
                return t
        return None

    # ---- mutations ----------------------------------------------------------
    def set_status(self, ref: str, status: str) -> Task:
        found = self.find(ref)
        if not found:
            raise SystemExit(f"task not found: {ref}")
        tf, task = found
        self._require_valid(tf_rel(tf, self), f"{status} T{task.ref}")
        block = tf.content[task.span[0]:task.span[1]]

        cm = COMPLETE_RE.search(block)
        if not cm:
            raise SystemExit(f"task {task.ref}: missing '- **Complete**: [ ]' line")
        new_box = STATUS_TO_CHECKBOX[status]
        block = block[:cm.start()] + f"{cm.group('prefix')}[{new_box}]" + block[cm.end():]

        ts = now_iso()
        if status == STATUS_IN_PROGRESS:
            block = _upsert_meta_line(block, "Started", ts)
            block = _remove_meta_line(block, "Finished")
        elif status == STATUS_COMPLETED:
            if not STARTED_RE.search(block):
                block = _upsert_meta_line(block, "Started", ts)
            block = _upsert_meta_line(block, "Finished", ts)
        elif status == STATUS_PENDING:
            block = _remove_meta_line(block, "Started")
            block = _remove_meta_line(block, "Finished")

        tf.content = tf.content[:task.span[0]] + block + tf.content[task.span[1]:]
        tf.path.write_text(tf.content, encoding="utf-8")
        self.load()
        if self.errors():
            eprint(f"[taskctl] summaries NOT recomputed: {len(self.errors())} validation error(s) elsewhere in {self.tasks_dir_rel} — fix, then run `taskctl.py sync-index`")
        else:
            self.sync_index()
        _, updated = self.find(ref)  # type: ignore[misc]
        return updated

    # ---- summaries ----------------------------------------------------------
    def sync_index(self) -> dict:
        self._require_valid(None, "sync-index")
        totals = {s: 0 for s in ALL_STATUSES}
        index_lines = []
        for tf in self.files:
            counts = {s: 0 for s in ALL_STATUSES}
            for t in tf.tasks:
                counts[t.status] += 1
                totals[t.status] += 1
            refs = sorted((t.ref for t in tf.tasks), key=ref_sort_key)
            lo, hi = (refs[0], refs[-1]) if refs else ("-", "-")
            summary = "\n".join([
                f"## Summary ({tf.path.name})",
                "",
                f"- **Tasks in this file**: {len(tf.tasks)}",
                f"- **Task IDs**: {lo} - {hi}",
                f"- **Pending**: {counts[STATUS_PENDING]}",
                f"- **In Progress**: {counts[STATUS_IN_PROGRESS]}",
                f"- **Complete**: {counts[STATUS_COMPLETED]}",
                "",
            ])
            new_content = _replace_section(tf.content, r"## Summary\b", summary, insert_at_top=True)
            if new_content != tf.content:
                tf.path.write_text(new_content, encoding="utf-8")
                tf.content = new_content
            index_lines.append(
                f"- `{self._rel(tf.path)}`: Contains Tasks {lo} - {hi} ({len(tf.tasks)} tasks)"
            )

        total = sum(totals.values())
        overall = "\n".join([
            "## Overall Project Task Summary",
            "",
            f"- **Total Tasks**: {total}",
            f"- **Pending**: {totals[STATUS_PENDING]}",
            f"- **In Progress**: {totals[STATUS_IN_PROGRESS]}",
            f"- **Complete**: {totals[STATUS_COMPLETED]}",
            "",
        ])
        file_index = "\n".join(["## Task File Index", "", *index_lines, ""])

        index_path = self.tasks_dir / INDEX_FILE
        content = index_path.read_text(encoding="utf-8") if index_path.exists() else "# Tasks Index\n\n"
        content = _replace_section(content, r"## Overall Project Task Summary", overall, insert_at_top=False)
        content = _replace_section(content, r"## Task File Index", file_index, insert_at_top=False)
        index_path.write_text(content, encoding="utf-8")
        return {"total": total, **totals}

    # ---- CC id map ----------------------------------------------------------
    def map_path(self) -> Path:
        return self.tasks_dir / MAP_FILE

    def load_map(self) -> dict:
        p = self.map_path()
        if p.exists():
            try:
                return json.loads(p.read_text(encoding="utf-8"))
            except json.JSONDecodeError:
                eprint(f"[taskctl] corrupt {p}, resetting")
        return {}

    def save_map(self, m: dict) -> None:
        self.map_path().write_text(json.dumps(m, indent=2, sort_keys=True) + "\n", encoding="utf-8")


# --------------------------------------------------------------------------- #
# Markdown surgery helpers
# --------------------------------------------------------------------------- #

def tf_rel(tf: TaskFile, store: "TaskStore") -> str:
    return store._rel(tf.path)


def _line_of(content: str, pos: int) -> int:
    return content.count("\n", 0, pos) + 1


def _upsert_meta_line(block: str, key: str, value: str) -> str:
    rx = re.compile(rf"^-\s+\*\*{key}\*\*:.*$", re.M)
    line = f"- **{key}**: {value}"
    if rx.search(block):
        return rx.sub(line, block, count=1)
    cm = COMPLETE_RE.search(block)
    assert cm
    # insert right after the Complete line; keep Started before Finished
    insert_at = cm.end()
    if key == "Finished":
        sm = STARTED_RE.search(block)
        if sm:
            insert_at = sm.end()
    return block[:insert_at] + "\n" + line + block[insert_at:]


def _remove_meta_line(block: str, key: str) -> str:
    rx = re.compile(rf"^-\s+\*\*{key}\*\*:.*\n?", re.M)
    return rx.sub("", block, count=1)


def _replace_section(content: str, heading_rx: str, new_section: str, insert_at_top: bool) -> str:
    """Replace a '## heading' section (up to the next '## ' heading) with new_section.
    If absent: insert after the first H1 (insert_at_top) or append at end."""
    rx = re.compile(rf"^{heading_rx}[^\n]*\n(?:(?!^##\s).*\n?)*", re.M)
    m = rx.search(content)
    new_section = new_section.rstrip("\n") + "\n\n"
    if m:
        return content[:m.start()] + new_section + content[m.end():].lstrip("\n")
    if insert_at_top:
        h1 = re.search(r"^#\s[^\n]*\n", content, re.M)
        if h1:
            return content[:h1.end()] + "\n" + new_section + content[h1.end():].lstrip("\n")
        return new_section + content
    return content.rstrip("\n") + "\n\n" + new_section


# --------------------------------------------------------------------------- #
# CLI commands
# --------------------------------------------------------------------------- #

def _print_table(tasks: Iterable[Task]) -> None:
    icon = {STATUS_PENDING: "[ ]", STATUS_IN_PROGRESS: "[~]", STATUS_COMPLETED: "[x]"}
    rows = list(tasks)
    if not rows:
        print("(no tasks)")
        return
    for t in rows:
        print(f"{icon[t.status]} T{t.ref:<8} {t.title:<60} {t.file}  ({t.tasks_file})")


def _warn_if_invalid(store: TaskStore) -> None:
    errs = store.errors()
    if errs:
        eprint(f"[taskctl] {len(errs)} validation error(s) in {store.tasks_dir_rel} — run `taskctl.py validate` (read-only output below may be incomplete)")


def cmd_validate(store: TaskStore, args) -> int:
    issues = store.issues
    errs = [i for i in issues if i.level == "error"]
    if args.json:
        print(json.dumps([asdict(i) for i in issues], indent=2, ensure_ascii=False))
    else:
        for i in issues:
            print(i)
        n_files = len(store.files)
        n_tasks = len(store.all_tasks())
        print(f"{'FAIL' if errs else 'OK'}: {n_files} file(s), {n_tasks} task(s), {len(errs)} error(s), {len(issues) - len(errs)} warning(s)")
    return 1 if errs else 0


def cmd_list(store: TaskStore, args) -> int:
    _warn_if_invalid(store)
    tasks = store.all_tasks()
    if args.status != "all":
        tasks = [t for t in tasks if t.status == args.status]
    if args.json:
        print(json.dumps([t.to_public() for t in tasks], indent=2, ensure_ascii=False))
    else:
        _print_table(tasks)
    return 0


def cmd_next(store: TaskStore, args) -> int:
    _warn_if_invalid(store)
    t = store.next_task()
    if args.json:
        print(json.dumps(t.to_public(with_prompt=True) if t else None, indent=2, ensure_ascii=False))
    elif t:
        _print_table([t])
        print("\n" + t.prompt)
    else:
        print("(no pending task)")
    return 0


def cmd_show(store: TaskStore, args) -> int:
    _warn_if_invalid(store)
    found = store.find(args.ref)
    if not found:
        eprint(f"task not found: {args.ref}")
        return 1
    _, t = found
    if args.json:
        print(json.dumps(t.to_public(with_prompt=True), indent=2, ensure_ascii=False))
    else:
        _print_table([t])
        for k in ("started", "finished"):
            if getattr(t, k):
                print(f"{k}: {getattr(t, k)}")
        print("\n" + t.prompt)
    return 0


def _cmd_set(status: str):
    def run(store: TaskStore, args) -> int:
        t = store.set_status(args.ref, status)
        print(f"T{t.ref} -> {t.status}  ({t.tasks_file})")
        return 0
    return run


def cmd_sync_index(store: TaskStore, args) -> int:
    print(json.dumps(store.sync_index()))
    return 0


# --------------------------------------------------------------------------- #
# Hook mode (PostToolUse: TaskCreate | TaskUpdate | TodoWrite)
# --------------------------------------------------------------------------- #

CC_STATUS_TO_ACTION = {
    "in_progress": STATUS_IN_PROGRESS,
    "completed": STATUS_COMPLETED,
    "pending": STATUS_PENDING,
}


def _extract_ref(subject: str | None, metadata: dict | None) -> str | None:
    if metadata:
        for k in ("task_ref", "taskRef", "ref"):
            v = metadata.get(k)
            if v:
                return str(v).lstrip("Tt")
    if subject:
        m = SUBJECT_REF_RE.match(subject)
        if m:
            return m.group("ref")
    return None


def _extract_cc_id(tool_response) -> str | None:
    if isinstance(tool_response, dict):
        task = tool_response.get("task")
        if isinstance(task, dict) and task.get("id") is not None:
            return str(task["id"])
        if tool_response.get("id") is not None:
            return str(tool_response["id"])
        for k in ("content", "output", "result", "message"):
            v = tool_response.get(k)
            if isinstance(v, str):
                m = CC_ID_IN_TEXT_RE.search(v)
                if m:
                    return m.group("id")
    if isinstance(tool_response, str):
        m = CC_ID_IN_TEXT_RE.search(tool_response)
        if m:
            return m.group("id")
    if isinstance(tool_response, list):
        for item in tool_response:
            r = _extract_cc_id(item)
            if r:
                return r
    return None


def _apply(store: TaskStore, ref: str, status: str, notes: list[str]) -> None:
    found = store.find(ref)
    if not found:
        notes.append(f"T{ref}: not found in {store.tasks_dir_rel} (skipped)")
        return
    _, t = found
    if t.status == status:
        notes.append(f"T{ref}: already {status}")
        return
    t = store.set_status(ref, status)
    notes.append(f"T{t.ref} -> {t.status} ({t.tasks_file})")


def cmd_hook(_store_unused, args) -> int:
    try:
        payload = json.load(sys.stdin)
    except json.JSONDecodeError as e:
        eprint(f"[taskctl hook] bad JSON on stdin: {e}")
        return 0

    root = Path(args.root or payload.get("cwd") or os.environ.get("CLAUDE_PROJECT_DIR") or os.getcwd())
    if not (root / args.tasks_dir).is_dir():
        return 0  # project does not use the tasks workflow — stay silent (user-scope hooks run everywhere)
    try:
        store = TaskStore(root, args.tasks_dir)
    except SystemExit as e:
        eprint(f"[taskctl hook] {e}")
        return 0

    tool = payload.get("tool_name", "")
    tin = payload.get("tool_input") or {}
    tres = payload.get("tool_response")
    notes: list[str] = []
    if store.errors():
        notes.append(f"{len(store.errors())} validation error(s) in {store.tasks_dir_rel}; status changes are refused until `taskctl.py validate` passes")

    try:
        if tool == "TaskCreate":
            ref = _extract_ref(tin.get("subject"), tin.get("metadata"))
            cc_id = _extract_cc_id(tres)
            if ref and cc_id:
                m = store.load_map()
                m[cc_id] = ref
                store.save_map(m)
                notes.append(f"mapped CC task #{cc_id} -> T{ref}")
            elif ref:
                notes.append(f"T{ref}: could not read CC task id from tool_response")
            # TaskCreate never changes file status (task stays pending until TaskUpdate)

        elif tool == "TaskUpdate":
            cc_id = tin.get("taskId") or tin.get("id") or tin.get("task_id")
            status = tin.get("status")
            ref = _extract_ref(tin.get("subject"), tin.get("metadata"))
            if not ref and cc_id is not None:
                ref = store.load_map().get(str(cc_id))
            if not ref:
                return 0  # unrelated CC task
            if status in CC_STATUS_TO_ACTION:
                _apply(store, ref, CC_STATUS_TO_ACTION[status], notes)
            elif status == "deleted":
                m = store.load_map()
                m.pop(str(cc_id), None)
                store.save_map(m)
                notes.append(f"CC task #{cc_id} deleted; T{ref} left unchanged in file")

        elif tool == "TodoWrite":
            for todo in tin.get("todos") or []:
                ref = _extract_ref(todo.get("content"), None)
                status = todo.get("status")
                if ref and status in CC_STATUS_TO_ACTION:
                    _apply(store, ref, CC_STATUS_TO_ACTION[status], notes)
        else:
            return 0
    except SystemExit as e:  # raised by store on bad task layout
        notes.append(f"error: {e}")

    if notes:
        msg = "[taskctl] " + "; ".join(notes)
        eprint(msg)
        print(json.dumps({"hookSpecificOutput": {"hookEventName": "PostToolUse", "additionalContext": msg}}))
    return 0


def cmd_session_start(_store_unused, args) -> int:
    """SessionStart hook: prime the agent with task-list status. Silent if no docs/tasks."""
    try:
        payload = json.load(sys.stdin) if not sys.stdin.isatty() else {}
    except json.JSONDecodeError:
        payload = {}
    root = Path(args.root or payload.get("cwd") or os.environ.get("CLAUDE_PROJECT_DIR") or os.getcwd())
    if not (root / args.tasks_dir).is_dir():
        return 0
    try:
        store = TaskStore(root, args.tasks_dir)
    except SystemExit as e:
        eprint(f"[taskctl session-start] {e}")
        return 0
    tasks = store.all_tasks()
    counts = {s: sum(1 for t in tasks if t.status == s) for s in ALL_STATUSES}
    lines = [
        f"[taskctl] {store.tasks_dir_rel}: {len(tasks)} tasks — "
        f"pending {counts[STATUS_PENDING]}, in_progress {counts[STATUS_IN_PROGRESS]}, completed {counts[STATUS_COMPLETED]}."
    ]
    if store.errors():
        lines.append(f"VALIDATION: {len(store.errors())} error(s) — run `taskctl.py validate` and fix before changing task status.")
    open_tasks = [t for t in tasks if t.status == STATUS_IN_PROGRESS]
    if open_tasks:
        lines.append("In progress: " + ", ".join(f"T{t.ref} {t.title} ({t.tasks_file})" for t in open_tasks))
    nxt = store.next_task()
    if nxt:
        lines.append(f"Next: T{nxt.ref} {nxt.title} -> {nxt.file} ({nxt.tasks_file}). "
                     f"Use `taskctl.py next --json` for the full prompt, then TaskCreate with subject \"{nxt.to_public()['cc_subject']}\".")
    msg = "\n".join(lines)
    print(json.dumps({"hookSpecificOutput": {"hookEventName": "SessionStart", "additionalContext": msg}}))
    return 0


# --------------------------------------------------------------------------- #
# Entry
# --------------------------------------------------------------------------- #

def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(prog="taskctl", description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--root", default=None, help="project root (default: $CLAUDE_PROJECT_DIR or cwd)")
    p.add_argument("--tasks-dir", default="docs/tasks", help="tasks dir relative to root")
    sub = p.add_subparsers(dest="cmd", required=True)

    s = sub.add_parser("list"); s.add_argument("--status", choices=(*ALL_STATUSES, "all"), default="all"); s.add_argument("--json", action="store_true"); s.set_defaults(fn=cmd_list)
    s = sub.add_parser("next"); s.add_argument("--json", action="store_true"); s.set_defaults(fn=cmd_next)
    s = sub.add_parser("show"); s.add_argument("ref"); s.add_argument("--json", action="store_true"); s.set_defaults(fn=cmd_show)
    s = sub.add_parser("start"); s.add_argument("ref"); s.set_defaults(fn=_cmd_set(STATUS_IN_PROGRESS))
    s = sub.add_parser("finish"); s.add_argument("ref"); s.set_defaults(fn=_cmd_set(STATUS_COMPLETED))
    s = sub.add_parser("reopen"); s.add_argument("ref"); s.set_defaults(fn=_cmd_set(STATUS_PENDING))
    s = sub.add_parser("sync-index"); s.set_defaults(fn=cmd_sync_index)
    s = sub.add_parser("validate"); s.add_argument("--json", action="store_true"); s.set_defaults(fn=cmd_validate)
    s = sub.add_parser("hook"); s.set_defaults(fn=cmd_hook, is_hook=True)
    s = sub.add_parser("session-start"); s.set_defaults(fn=cmd_session_start, is_hook=True)
    return p


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    if getattr(args, "is_hook", False):
        return args.fn(None, args)
    root = Path(args.root or os.environ.get("CLAUDE_PROJECT_DIR") or os.getcwd())
    store = TaskStore(root, args.tasks_dir)
    return args.fn(store, args)


if __name__ == "__main__":
    sys.exit(main())
