#!/usr/bin/env python3
"""Create CLAUDE.md mirror symlinks for other AI-agent runtime filenames.

Enforces `.agents/rules/003-claude-md-canonical.md`:
CLAUDE.md is the single source of truth; sibling filenames used by other AI
runtimes (AGENTS.md, GEMINI.md, .cursorrules, .github/copilot-instructions.md,
…) must be **symlinks** to the same-directory CLAUDE.md — never divergent
copies.

Usage
-----
    # Interactive multi-select (numbered checkboxes)
    python .agents/rules/003-claude-md-canonical.py

    # CLI, comma / semicolon / whitespace separated (aliases or filenames)
    python .agents/rules/003-claude-md-canonical.py agents,gemini
    python .agents/rules/003-claude-md-canonical.py "AGENTS.md GEMINI.md"
    python .agents/rules/003-claude-md-canonical.py copilot;cursor;aider

    # Preview only
    python .agents/rules/003-claude-md-canonical.py --dry-run all

    # Overwrite existing non-symlink mirrors
    python .agents/rules/003-claude-md-canonical.py -f agents

Windows
-------
Symlink creation on Windows needs one of:
  1) Developer Mode ON  (Settings → Update & Security → For developers)
  2) An elevated (admin) shell

If neither is available, the script probes for symlink capability and offers
to relaunch itself via UAC. The elevated child pauses on exit so you can read
its output before the window closes.
"""
from __future__ import annotations

import argparse
import ctypes
import os
import re
import sys
from pathlib import Path

# Windows consoles default to cp1252 -- force UTF-8 so non-ASCII chars never
# blow up. Silent no-op on Python <3.7 or streams that can't be reconfigured.
for _s in (sys.stdout, sys.stderr):
    try:
        _s.reconfigure(encoding="utf-8", errors="replace")  # type: ignore[attr-defined]
    except (AttributeError, OSError):
        pass

# alias (lowercase) → repo-relative path from CLAUDE.md's directory
TARGETS: dict[str, str] = {
    "agents":       "AGENTS.md",
    "gemini":       "GEMINI.md",
    "cursor":       ".cursorrules",
    "cursorrules":  ".cursorrules",
    "copilot":      ".github/copilot-instructions.md",
    "aider":        ".aider.conf.md",
    "windsurf":     ".windsurfrules",
}
# reverse lookup for filename-as-input
FILENAME_TO_KEY: dict[str, str] = {v.lower(): k for k, v in TARGETS.items()}

SEP_RE = re.compile(r"[,;\s]+")


# ---------------------------------------------------------------- source

def find_source() -> Path:
    """Locate CLAUDE.md at `<script>/../..` (`.agents/rules/../..`).

    If missing, prompt the user (interactive-param-collection pattern —
    `[PARAM:<key>] <question>`; the reply is read synchronously in a CLI).
    """
    script = Path(__file__).resolve()
    guess = script.parents[2] / "CLAUDE.md"
    if guess.is_file():
        return guess

    if not sys.stdin.isatty():
        print(f"error: CLAUDE.md not found at {guess} and stdin is not a TTY",
              file=sys.stderr)
        sys.exit(1)

    prompt = f"[PARAM:source] CLAUDE.md not found at {guess}. Enter path to CLAUDE.md"
    hint = "  (example: /path/to/project/CLAUDE.md)"
    print(prompt); print(hint)
    while True:
        raw = input("> ").strip().strip('"').strip("'")
        if not raw:
            print("[PARAM:source] empty input — enter path to CLAUDE.md"); continue
        p = Path(raw).expanduser()
        if not p.is_absolute():
            p = (Path.cwd() / p).resolve()
        else:
            p = p.resolve()
        if p.name != "CLAUDE.md":
            print(f"[PARAM:source] {p.name!r} is not named CLAUDE.md — try again"); continue
        if not p.is_file():
            print(f"[PARAM:source] {p} does not exist — try again"); continue
        return p


# ---------------------------------------------------------------- targets

def parse_targets(raw: str) -> list[str]:
    """Split a raw CLI string on `, ; whitespace` and resolve aliases."""
    if raw.strip().lower() in {"all", "*"}:
        # unique canonical paths, in declaration order
        seen: set[str] = set(); out: list[str] = []
        for v in TARGETS.values():
            if v not in seen:
                seen.add(v); out.append(v)
        return out

    tokens = [t for t in SEP_RE.split(raw) if t]
    resolved: list[str] = []
    for t in tokens:
        key = t.lower().lstrip("/\\").replace("\\", "/")
        if key in TARGETS:
            resolved.append(TARGETS[key])
        elif key in FILENAME_TO_KEY:
            resolved.append(TARGETS[FILENAME_TO_KEY[key]])
        else:
            # allow ad-hoc paths (`.myrunner/foo.md`) — trust the user
            resolved.append(t)
    seen2: set[str] = set(); out2: list[str] = []
    for r in resolved:
        if r not in seen2:
            seen2.add(r); out2.append(r)
    return out2


def interactive_pick() -> list[str]:
    """Numbered multi-select checkboxes (stdlib only)."""
    if not sys.stdin.isatty():
        print("error: no targets given and stdin is not a TTY", file=sys.stderr)
        sys.exit(1)

    # unique (path, alias) items in declaration order
    seen: set[str] = set(); items: list[tuple[str, str]] = []
    for alias, path in TARGETS.items():
        if path in seen: continue
        seen.add(path); items.append((alias, path))

    print("Select target(s) to mirror ← CLAUDE.md:")
    for i, (alias, path) in enumerate(items, 1):
        print(f"  [ ] {i}) {path}   (alias: {alias})")
    print("Enter numbers separated by space/comma  (e.g. '1 3 5'),")
    print("      or 'all' / '*' to pick everything,")
    print("      empty to abort.")
    raw = input("> ").strip().lower()
    if not raw:
        return []
    if raw in {"all", "*"}:
        return [p for _, p in items]

    tokens = [t for t in SEP_RE.split(raw) if t]
    picked: list[str] = []
    for tok in tokens:
        try:
            n = int(tok)
        except ValueError:
            print(f"  skipping non-numeric token: {tok!r}"); continue
        if 1 <= n <= len(items):
            picked.append(items[n - 1][1])
        else:
            print(f"  skipping out-of-range index: {n}")
    seen2: set[str] = set(); out: list[str] = []
    for p in picked:
        if p not in seen2:
            seen2.add(p); out.append(p)
    return out


# ---------------------------------------------------------------- Windows / UAC

def is_windows() -> bool:
    return os.name == "nt"


def is_admin_windows() -> bool:
    try:
        return bool(ctypes.windll.shell32.IsUserAnAdmin())  # type: ignore[attr-defined]
    except Exception:
        return False


def can_symlink_here(root: Path) -> bool:
    """Probe: try to create + delete a symlink inside `root`."""
    probe = root / f".symlink-probe-{os.getpid()}"
    try:
        os.symlink("CLAUDE.md", probe)
    except OSError:
        return False
    finally:
        try:
            if probe.is_symlink() or probe.exists():
                probe.unlink()
        except OSError:
            pass
    return True


def elevate_windows(argv: list[str]) -> None:
    """Relaunch this script via UAC; child pauses on exit."""
    script = Path(__file__).resolve()
    child_args = [str(script), "--_pause-on-exit", *argv]
    # ShellExecuteW quoting: pass everything joined as one string
    params = " ".join(f'"{a}"' for a in child_args)
    print("Windows: cannot create symlinks in this shell.")
    print("Options:")
    print("  1) Enable Developer Mode  -> Settings -> Update & Security -> For developers")
    print("     (no admin needed after that; re-run this script normally)")
    print("  2) Elevate now via UAC prompt (a new admin window opens)")
    ans = input("Elevate via UAC? [y/N] ").strip().lower()
    if ans not in {"y", "yes"}:
        print("Aborting. Enable Developer Mode or run from an admin shell, then retry.")
        sys.exit(2)
    print("Requesting UAC…")
    rc = ctypes.windll.shell32.ShellExecuteW(  # type: ignore[attr-defined]
        None, "runas", sys.executable, params, None, 1,
    )
    if rc <= 32:
        print(f"UAC elevation failed (ShellExecuteW rc={rc}).", file=sys.stderr)
        sys.exit(2)
    print("Elevated window launched; this window can be closed.")
    sys.exit(0)


# ---------------------------------------------------------------- symlink

def _readlink_abs(link: Path) -> Path:
    t = Path(os.readlink(link))
    return t if t.is_absolute() else (link.parent / t).resolve()


def make_symlink(src: Path, dst: Path, *, force: bool, dry_run: bool) -> bool:
    """Create `dst` as a symlink → `src`. Returns True on success/idempotent."""
    rel = os.path.relpath(src, dst.parent)
    dst.parent.mkdir(parents=True, exist_ok=True)

    if dst.is_symlink():
        try:
            if _readlink_abs(dst) == src:
                print(f"  [ok] {dst}: already symlinked -> {rel}")
                return True
        except OSError:
            pass
        # stale symlink — overwrite freely (symlinks don't hold user data)
        if dry_run:
            print(f"  [dry-run] remove stale symlink {dst}")
        else:
            dst.unlink()
    elif dst.exists():
        if not force:
            print(f"  [skip] {dst}: exists (regular file). Pass --force to replace.")
            return False
        # backup instead of delete — never lose user data
        bak = dst.with_suffix(dst.suffix + ".bak")
        i = 0
        while bak.exists():
            i += 1
            bak = dst.with_suffix(f"{dst.suffix}.bak{i}")
        if dry_run:
            print(f"  [dry-run] move {dst} -> {bak.name}, then symlink -> {rel}")
            return True
        dst.rename(bak)
        print(f"  [bak] {dst.name} -> {bak.name}")

    if dry_run:
        print(f"  [dry-run] {dst} -> {rel}")
        return True
    try:
        os.symlink(rel, dst)
    except OSError as e:
        print(f"  [fail] {dst}: symlink failed: {e}")
        return False
    print(f"  [ok] {dst} -> {rel}")
    return True


# ---------------------------------------------------------------- main

def main() -> int:
    ap = argparse.ArgumentParser(
        description="Create CLAUDE.md mirror symlinks "
                    "(.agents/rules/003-claude-md-canonical.md).",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    ap.add_argument("targets", nargs="?",
                    help="Comma/semicolon/space-separated targets -- aliases "
                         "(agents, gemini, cursor, copilot, aider, windsurf) or "
                         "filenames (AGENTS.md, .cursorrules, ...). "
                         "'all' or '*' selects everything known. "
                         "Omit for interactive multi-select.")
    ap.add_argument("-f", "--force", action="store_true",
                    help="Backup + overwrite an existing regular file at the target.")
    ap.add_argument("--dry-run", action="store_true",
                    help="Show what would change; touch nothing.")
    ap.add_argument("--no-elevate", action="store_true",
                    help="Do not offer UAC elevation on Windows.")
    ap.add_argument("--_pause-on-exit", action="store_true",
                    help=argparse.SUPPRESS)
    args = ap.parse_args()

    pause = getattr(args, "_pause_on_exit", False)

    try:
        src = find_source()
        root = src.parent
        print(f"source: {src}")

        targets = parse_targets(args.targets) if args.targets else interactive_pick()
        if not targets:
            print("nothing selected — done.")
            return 0
        print(f"targets ({len(targets)}): {', '.join(targets)}\n")

        # Windows: check symlink capability before touching anything
        if is_windows() and not args.dry_run and not args.no_elevate:
            if not is_admin_windows() and not can_symlink_here(root):
                elevate_windows([a for a in sys.argv[1:] if a != "--_pause-on-exit"])

        ok = fail = 0
        for t in targets:
            dst = (root / t).resolve()
            if make_symlink(src, dst, force=args.force, dry_run=args.dry_run):
                ok += 1
            else:
                fail += 1

        print()
        print(f"summary: {ok} ok, {fail} skipped/failed"
              + ("  (dry-run -- no changes written)" if args.dry_run else ""))
        return 0 if fail == 0 else 1
    finally:
        if pause:
            try:
                input("\nPress Enter to close…")
            except EOFError:
                pass


if __name__ == "__main__":
    sys.exit(main())
