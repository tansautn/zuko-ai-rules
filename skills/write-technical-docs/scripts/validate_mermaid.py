#!/usr/bin/env python3
"""Render every ```mermaid block found in Markdown files, with SEVERAL Mermaid versions.

Renderers in the wild run different Mermaid versions (IDE plugins and app viewers often
still ship 10.x, GitHub and mermaid-cli ship 11.x). A block that parses on one version can
fail on another, so each block is rendered with every version in --versions.

Before rendering, a static lint pass prints HINT lines for the syntax traps listed in
references/mermaid-styling.md section 8 (special characters). Rendering is the verdict;
hints only explain the usual cause.

Usage:
    python validate_mermaid.py FILE_OR_DIR [...] [--versions 10.9.1,11.4.2]
                               [--png OUT_DIR] [--dark] [--mmdc PATH] [--browser PATH]

--versions : mermaid-cli versions run through npx (default 10.9.1,11.4.2).
--mmdc     : use this one mmdc executable instead (single version, no npx).
--browser  : Chrome/Edge/Chromium path; default: $PUPPETEER_EXECUTABLE_PATH or an installed one.
             When a local browser is found, Chromium is never downloaded.

Exit code: 0 when every block renders on every version, 1 otherwise, 2 when no renderer.
"""
import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import textwrap
from pathlib import Path

DEFAULT_VERSIONS = "10.9.1,11.4.2"
SKIP_DIRS = {".git", "node_modules", "vendor", ".venv", "venv", "__pycache__"}
BLOCK_RE = re.compile(r"^[ \t]*```mermaid[^\n]*\n(.*?)^[ \t]*```[ \t]*$", re.S | re.M)
BROWSER_PATHS = [
    r"C:\Program Files\Google\Chrome\Application\chrome.exe",
    r"C:\Program Files (x86)\Google\Chrome\Application\chrome.exe",
    r"C:\Program Files\Microsoft\Edge\Application\msedge.exe",
    r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe",
    "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
    "/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge",
    "/Applications/Chromium.app/Contents/MacOS/Chromium",
]
BROWSER_COMMANDS = ["google-chrome", "google-chrome-stable", "chromium", "chromium-browser", "microsoft-edge"]


# ---------------------------------------------------------------- discovery
def collect_markdown(paths):
    for raw in paths:
        path = Path(raw)
        if path.is_dir():
            for md in sorted(path.rglob("*.md")):
                if not SKIP_DIRS.intersection(md.parts):
                    yield md
        elif path.suffix.lower() == ".md" and path.exists():
            yield path
        else:
            print(f"skip (not a markdown file): {raw}", file=sys.stderr)


def extract_blocks(md_path):
    text = md_path.read_text(encoding="utf-8")
    for match in BLOCK_RE.finditer(text):
        line = text.count("\n", 0, match.start()) + 1
        yield line, textwrap.dedent(match.group(1))


def diagram_kind(source):
    for line in source.splitlines():
        stripped = line.strip()
        if stripped and not stripped.startswith("%%"):
            return stripped.split()[0]
    return "empty"


# ---------------------------------------------------------------- static lint
NODE_OPEN = re.compile(r"\b[\w-]+(\[\[|\[\(|\(\[|\(\(|\{\{|\[|\(|\{)")
NODE_CLOSE = {"[[": "]]", "[(": ")]", "([": "])", "((": "))", "{{": "}}", "[": "]", "(": ")", "{": "}"}
STATE_TRANSITION = re.compile(r"^(\[\*\]|[\w.-]+)\s*-->\s*(\[\*\]|[\w.-]+)\s*(?::(.*))?$")
STATE_DESCRIPTION = re.compile(r"^([\w.]+)\s*:(.*)$")
SEQ_TEXT = re.compile(r"^(?:[\w-]+\s*[-.x)>+]+\s*[\w-]+|note\s+(?:over|left of|right of)\s+[^:]+)\s*:(.*)$", re.I)
ENTITY = re.compile(r"#\w+;")  # Mermaid escapes such as #58; #59; #quot;
STATE_KEYWORDS = ("classDef", "class ", "state ", "note ", "direction ", "end note", "[*]")


def unquoted_node_texts(line):
    """Yield the text of flowchart nodes written without quotes."""
    for match in NODE_OPEN.finditer(line):
        opener = match.group(1)
        rest = line[match.end():]
        if rest.startswith('"'):
            continue
        end = rest.find(NODE_CLOSE[opener])
        yield rest if end < 0 else rest[:end]


def lint(source):
    kind = diagram_kind(source)
    hints, in_note = [], False
    for number, line in enumerate(source.splitlines(), 1):
        stripped = line.strip()
        if not stripped or stripped.startswith("%%"):
            continue
        if kind in ("graph", "flowchart"):
            if stripped != "end" and re.search(r"(^end\s*(-|=)|(-->|---|==>|-\.->)\s*end\s*($|[\[(;]))", stripped):
                hints.append((number, "node id 'end' breaks flowcharts - rename it (e.g. done) or use End"))
            if any(re.search(r"[()\[\]{}]", text) for text in unquoted_node_texts(stripped)):
                hints.append((number, "node text has ( ) [ ] { } without quotes - write A[\"text (x)\"]"))
            if re.search(r"-{2,}[ox][A-Za-z]", stripped):
                hints.append((number, "'---o'/'---x' + id draws a circle/cross arrow - add a space or rename the id"))
        elif kind.startswith("stateDiagram"):
            if in_note:
                in_note = stripped != "end note"
                continue
            if re.match(r"^note\s+(left|right)\s+of\s+\S+\s*$", stripped):
                in_note = True
                continue
            transition = STATE_TRANSITION.match(stripped)
            if transition:
                names = transition.group(1) + " " + transition.group(2)
                if re.search(r"\w-\w", names):
                    hints.append((number, "state name with '-' is invalid - use state \"pre-check\" as precheck"))
                text = transition.group(3)
            else:
                description = None if stripped.startswith(STATE_KEYWORDS) else STATE_DESCRIPTION.match(stripped)
                text = description.group(2) if description else None
            if text and ":" in ENTITY.sub("", text):
                hints.append((number, "second ':' in a state label fails on Mermaid 10.x - write #58; or rephrase"))
        elif kind == "sequenceDiagram":
            message = SEQ_TEXT.match(stripped)
            if message and ";" in ENTITY.sub("", message.group(1)):
                hints.append((number, "';' ends a statement in sequence diagrams - write #59; or rephrase"))
    return hints


# ---------------------------------------------------------------- rendering
def find_browser(explicit):
    for candidate in [explicit, os.environ.get("PUPPETEER_EXECUTABLE_PATH")] + BROWSER_PATHS:
        if candidate and Path(candidate).exists():
            return candidate
    for command in BROWSER_COMMANDS:
        found = shutil.which(command)
        if found:
            return found
    return None


def build_renderers(args):
    """Return a list of (label, command-prefix)."""
    if args.mmdc or os.environ.get("MMDC"):
        return [("mmdc", [args.mmdc or os.environ["MMDC"]])]
    npx = shutil.which("npx")
    if npx:
        versions = [v.strip() for v in args.versions.split(",") if v.strip()]
        return [(v, [npx, "--yes", "-p", f"@mermaid-js/mermaid-cli@{v}", "mmdc"]) for v in versions]
    local = shutil.which("mmdc")
    if local:
        print("warning: npx not found - checking with the single mmdc on PATH only", file=sys.stderr)
        return [("mmdc", [local])]
    return []


def render(command_prefix, source_file, output_file, config_file, env, dark=False, scale=None):
    command = command_prefix + ["-q", "-i", str(source_file), "-o", str(output_file)]
    if config_file:
        command += ["-p", str(config_file)]
    command += ["-t", "dark", "-b", "#0d1117"] if dark else ["-b", "white"]
    if scale:
        command += ["-s", str(scale)]
    try:
        result = subprocess.run(command, capture_output=True, text=True, encoding="utf-8",
                                errors="replace", env=env, timeout=240)
    except subprocess.TimeoutExpired:
        return "timeout after 240s"
    if result.returncode == 0 and output_file.exists():
        return None
    output = (result.stderr or "") + (result.stdout or "")
    errors = [line.strip() for line in output.splitlines() if re.search(r"error|expect|parse", line, re.I)]
    return " | ".join((errors or output.splitlines() or ["unknown error"])[:2])[:300]


def main():
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("paths", nargs="+", help="Markdown files or directories (recursive)")
    parser.add_argument("--versions", default=DEFAULT_VERSIONS, help="comma separated mermaid-cli versions")
    parser.add_argument("--png", metavar="OUT_DIR", help="also export PNG files (newest version) for a visual check")
    parser.add_argument("--dark", action="store_true", help="with --png: also export a dark-theme PNG")
    parser.add_argument("--mmdc", help="path to one mmdc executable (single version)")
    parser.add_argument("--browser", help="path to a Chrome/Edge/Chromium executable")
    args = parser.parse_args()

    renderers = build_renderers(args)
    if not renderers:
        print("No renderer: install Node.js (for npx) or pass --mmdc.", file=sys.stderr)
        return 2

    env = dict(os.environ)
    work_dir = Path(tempfile.mkdtemp(prefix="mermaid-check-"))
    config_file = None
    browser = find_browser(args.browser)
    if browser:
        env["PUPPETEER_SKIP_DOWNLOAD"] = "1"
        config_file = work_dir / "puppeteer.json"
        config_file.write_text(json.dumps({"executablePath": browser, "args": ["--no-sandbox"]}), encoding="utf-8")

    png_dir = Path(args.png) if args.png else None
    if png_dir:
        png_dir.mkdir(parents=True, exist_ok=True)
    print("renderers: " + ", ".join(label for label, _ in renderers))

    total, failures = 0, 0
    for md_path in collect_markdown(args.paths):
        for index, (line, source) in enumerate(extract_blocks(md_path), 1):
            total += 1
            stem = re.sub(r"[\\/:]+", "__", str(md_path.with_suffix(""))).strip("_.") + f"-{index}"
            source_file = work_dir / f"{stem}.mmd"
            source_file.write_text(source, encoding="utf-8")
            label = f"{md_path}:{line} #{index} ({diagram_kind(source)})"
            errors = {}
            for version, prefix in renderers:
                error = render(prefix, source_file, work_dir / f"{stem}-{version}.svg", config_file, env)
                if error:
                    errors[version] = error
            for hint_line, hint in lint(source):
                print(f"HINT {md_path}:{line + hint_line} {hint}")
            if errors:
                failures += 1
                for version, error in errors.items():
                    print(f"FAIL {label} [mermaid-cli {version}]: {error}")
                continue
            print(f"OK   {label}")
            if png_dir:
                prefix = renderers[-1][1]
                render(prefix, source_file, png_dir / f"{stem}.png", config_file, env, scale=1.5)
                if args.dark:
                    render(prefix, source_file, png_dir / f"{stem}-dark.png", config_file, env, dark=True, scale=1.5)

    shutil.rmtree(work_dir, ignore_errors=True)
    summary = f"\n{total} diagram(s), {failures} failure(s) across {len(renderers)} renderer version(s)"
    print(summary + (f"; PNG in {png_dir}" if png_dir else ""))
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
