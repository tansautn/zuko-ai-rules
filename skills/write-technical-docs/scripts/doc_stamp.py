#!/usr/bin/env python3
"""Print the "Last updated" line for a document, with a clickable link to the verified commit.

The commit is HEAD at the time of writing: the code the document was checked against.
Once the document itself is committed, that commit becomes the one right before it.

    **Last updated:** 2026-10-09 · verified against [`733b1ae`](https://github.com/o/r/commit/733b1ae...)

When some of the --paths have uncommitted changes, they are listed after the link, because the
document then also describes code that is not in that commit yet.

Usage:
    python doc_stamp.py [--paths PATH ...] [--repo DIR] [--date YYYY-MM-DD]

--paths : code/doc paths the document describes; only these are checked for uncommitted changes.
--repo  : repository to read (default: current directory).
"""
import argparse
import datetime
import re
import subprocess
import sys


def git(args, cwd, strip=True):
    try:
        result = subprocess.run(["git", *args], cwd=cwd, capture_output=True, text=True,
                                encoding="utf-8", errors="replace", timeout=60)
    except (OSError, subprocess.TimeoutExpired):
        return ""
    if result.returncode != 0:
        return ""
    return result.stdout.strip() if strip else result.stdout


def web_base(remote):
    """Turn a git remote URL into the web URL of the repository."""
    remote = remote.strip()
    ssh = re.match(r"^(?:ssh://)?git@([^:/]+)[:/](.+?)(?:\.git)?/?$", remote)
    if ssh:
        return f"https://{ssh.group(1)}/{ssh.group(2)}"
    https = re.match(r"^https?://(?:[^@/]+@)?([^/]+)/(.+?)(?:\.git)?/?$", remote)
    if https:
        return f"https://{https.group(1)}/{https.group(2)}"
    return None


def commit_url(base, full_hash):
    if "gitlab" in base:
        return f"{base}/-/commit/{full_hash}"
    if "bitbucket" in base:
        return f"{base}/commits/{full_hash}"
    return f"{base}/commit/{full_hash}"


def main():
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--paths", nargs="*", default=[])
    parser.add_argument("--repo", default=".")
    parser.add_argument("--date", default=datetime.date.today().isoformat())
    args = parser.parse_args()

    full_hash = git(["rev-parse", "HEAD"], args.repo)
    if not full_hash:
        print(f"**Last updated:** {args.date}")
        print("note: not a git repository - no commit reference", file=sys.stderr)
        return 0
    short = full_hash[:7]
    base = web_base(git(["remote", "get-url", "origin"], args.repo) or "")
    reference = f"[`{short}`]({commit_url(base, full_hash)})" if base else f"`{short}`"

    line = f"**Last updated:** {args.date} · verified against {reference}"
    if args.paths:
        status = git(["status", "--porcelain", "--", *args.paths], args.repo, strip=False)
        entries = {entry[3:].strip().strip('"') for entry in status.splitlines() if entry.strip()}
        # the documents themselves are not "code the doc describes"
        dirty = sorted(path for path in entries
                       if not path.lower().endswith(".md") and "docs" not in path.strip("/").split("/"))
        if dirty:
            shown = ", ".join(f"`{path}`" for path in dirty[:5]) + (" …" if len(dirty) > 5 else "")
            line += f" + chưa commit: {shown}"
    print(line)

    if base and not git(["branch", "-r", "--contains", full_hash], args.repo):
        print(f"note: {short} is not on any remote branch yet - the link works after it is pushed", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
