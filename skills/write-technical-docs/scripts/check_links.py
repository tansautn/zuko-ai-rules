#!/usr/bin/env python3
"""Check relative links and #anchors in Markdown files, using GitHub's heading-slug rules.

Links inside fenced code blocks and inline code are ignored. External links
(http, https, mailto, tel, data) are not fetched.

Problems (exit 1):
  - the linked file does not exist
  - the #anchor does not exist in the linked Markdown file

Warnings (exit 0, or 1 with --strict) - the link works locally but breaks on the git host:
  - the target is not tracked by git (and is not one of the files being checked)
  - the target sits inside a git submodule of the current repo

Usage:
    python check_links.py FILE_OR_DIR [...] [--strict]
"""
import re
import subprocess
import sys
from pathlib import Path
from urllib.parse import unquote

SKIP_DIRS = {".git", "node_modules", "vendor", ".venv", "venv", "__pycache__"}
EXTERNAL = re.compile(r"^(https?:|mailto:|tel:|data:|//)", re.I)
FENCE = re.compile(r"^[ \t]{0,3}(`{3,}|~{3,})")
HEADING = re.compile(r"^[ \t]{0,3}(#{1,6})[ \t]+(.*?)[ \t#]*$")
LINK = re.compile(r"!?\[(?:[^\[\]]|\[[^\]]*\])*\]\(\s*<?([^)\s>]*)>?(?:\s+\"[^\"]*\")?\s*\)")
INLINE_CODE = re.compile(r"(`+)(.+?)\1")


def collect_markdown(paths):
    for raw in paths:
        path = Path(raw)
        if path.is_dir():
            for md in sorted(path.rglob("*.md")):
                if not SKIP_DIRS.intersection(md.parts):
                    yield md
        elif path.exists():
            yield path
        else:
            print(f"skip (not found): {raw}", file=sys.stderr)


def prose_lines(text):
    """Yield (line_number, line) outside fenced code blocks."""
    fence = None
    for number, line in enumerate(text.splitlines(), 1):
        match = FENCE.match(line)
        if fence is None and match:
            fence = match.group(1)
            continue
        if fence is not None:
            if match and match.group(1)[0] == fence[0] and len(match.group(1)) >= len(fence):
                fence = None
            continue
        yield number, line


def slugify(heading):
    text = re.sub(r"\[([^\]]*)\]\([^)]*\)", r"\1", heading)   # [text](url) -> text
    text = re.sub(r"<[^>]+>", "", text)                        # inline html
    text = text.replace("`", "").replace("*", "")
    text = re.sub(r"(?<!\w)_+|_+(?!\w)", "", text)             # _emphasis_ markers, keep snake_case
    text = re.sub(r"[^\w\- ]", "", text.strip().lower())
    return text.replace(" ", "-")


_anchor_cache = {}


def anchors_of(md_path):
    key = md_path.resolve()
    if key not in _anchor_cache:
        seen, anchors = {}, set()
        for _, line in prose_lines(md_path.read_text(encoding="utf-8")):
            match = HEADING.match(line)
            if not match:
                continue
            slug = slugify(match.group(2))
            count = seen.get(slug, 0)
            seen[slug] = count + 1
            anchors.add(slug if count == 0 else f"{slug}-{count}")
        _anchor_cache[key] = anchors
    return _anchor_cache[key]


class GitView:
    """Tracked files and submodule roots of the repo that contains `start`."""

    def __init__(self, start):
        self.root, self.tracked, self.submodules = None, set(), []
        top = self._git(["rev-parse", "--show-toplevel"], start)
        if not top:
            return
        self.root = Path(top).resolve()
        for line in self._git(["ls-files", "-s"], self.root).splitlines():
            meta, _, rel = line.partition("\t")
            path = (self.root / rel).resolve()
            if meta.startswith("160000"):
                self.submodules.append(path)
            else:
                self.tracked.add(path)

    @staticmethod
    def _git(args, cwd):
        try:
            result = subprocess.run(["git", *args], cwd=cwd, capture_output=True, text=True,
                                    encoding="utf-8", errors="replace", timeout=60)
        except (OSError, subprocess.TimeoutExpired):
            return ""
        return result.stdout.strip() if result.returncode == 0 else ""

    def warning_for(self, target, checked):
        if not self.root or self.root not in (target, *target.parents):
            return None
        for submodule in self.submodules:
            if submodule == target or submodule in target.parents:
                return f"inside submodule '{submodule.relative_to(self.root).as_posix()}'"
        if target.is_dir() or target in self.tracked or target in checked:
            return None
        return "not tracked by git"


def check_file(md_path, git_view, checked):
    problems, warnings = [], []
    for number, line in prose_lines(md_path.read_text(encoding="utf-8")):
        line = INLINE_CODE.sub("", line)
        for match in LINK.finditer(line):
            target = unquote(match.group(1))
            if not target or EXTERNAL.match(target):
                continue
            path_part, _, anchor = target.partition("#")
            resolved = (md_path.parent / path_part).resolve() if path_part else md_path.resolve()
            if not resolved.exists():
                problems.append(f"{md_path}:{number}: missing file '{path_part}'")
                continue
            if anchor and resolved.suffix.lower() == ".md" and anchor.lower() not in anchors_of(resolved):
                problems.append(f"{md_path}:{number}: missing anchor '#{anchor}' in {resolved.name}")
            if path_part:
                warning = git_view.warning_for(resolved, checked)
                if warning:
                    warnings.append(f"{md_path}:{number}: '{path_part}' {warning} - link breaks on the git host")
    return problems, warnings


def main():
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    args = sys.argv[1:]
    if not args or args[0] in ("-h", "--help"):
        print(__doc__)
        return 0 if args else 1
    strict = "--strict" in args
    files = list(collect_markdown([a for a in args if a != "--strict"]))
    if not files:
        print("no markdown files found")
        return 1
    git_view = GitView(files[0].resolve().parent)
    checked = {md.resolve() for md in files}
    problems, warnings = [], []
    for md in files:
        file_problems, file_warnings = check_file(md, git_view, checked)
        problems += file_problems
        warnings += file_warnings
    for problem in problems:
        print(f"ERROR {problem}")
    for warning in warnings:
        print(f"WARN  {warning}")
    print(f"{len(files)} file(s) checked, {len(problems)} problem(s), {len(warnings)} warning(s)")
    return 1 if problems or (strict and warnings) else 0


if __name__ == "__main__":
    sys.exit(main())
