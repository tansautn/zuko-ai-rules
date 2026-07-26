#!/usr/bin/env python3
"""Extract conversation context from a Claude Code CLI session JSONL file.

Usage:
    python extract_session.py <uuid> [--project-slug <slug>] [--claude-dir <path>]
    python extract_session.py --list [--project-slug <slug>] [--claude-dir <path>]
    python extract_session.py --search <keyword> [--project-slug <slug>] [--claude-dir <path>]

Output: JSON with session metadata, user messages, assistant messages, and file history.
"""

import argparse
import json
import os
import sys
import re
from pathlib import Path
from datetime import datetime

sys.stdout.reconfigure(encoding='utf-8')
sys.stderr.reconfigure(encoding='utf-8')


def get_claude_dir(override: str | None = None) -> Path:
    if override:
        return Path(override)
    home = Path.home()
    return home / '.claude'


def get_projects_dir(claude_dir: Path) -> Path:
    return claude_dir / 'projects'


def find_project_slug(projects_dir: Path, slug: str | None = None) -> list[Path]:
    if not projects_dir.exists():
        return []
    if slug:
        target = projects_dir / slug
        return [target] if target.exists() else []
    return [p for p in projects_dir.iterdir() if p.is_dir()]


def find_session_file(projects_dir: Path, uuid: str, slug: str | None = None) -> Path | None:
    fname = f'{uuid}.jsonl'
    for proj_dir in find_project_slug(projects_dir, slug):
        candidate = proj_dir / fname
        if candidate.exists():
            return candidate
    return None


def list_sessions(projects_dir: Path, slug: str | None = None) -> list[dict]:
    results = []
    for proj_dir in find_project_slug(projects_dir, slug):
        for f in proj_dir.glob('*.jsonl'):
            uuid = f.stem
            stat = f.stat()
            title = None
            cwd = None
            branch = None
            try:
                with open(f, encoding='utf-8') as fh:
                    for line in fh:
                        line = line.strip()
                        if not line:
                            continue
                        obj = json.loads(line)
                        if obj.get('type') == 'ai-title' and not title:
                            title = obj.get('aiTitle')
                        if obj.get('type') == 'attachment' and not cwd:
                            cwd = obj.get('cwd')
                            branch = obj.get('gitBranch')
                        if title and cwd:
                            break
            except Exception:
                pass
            results.append({
                'uuid': uuid,
                'project': proj_dir.name,
                'title': title,
                'cwd': cwd,
                'branch': branch,
                'modified': datetime.fromtimestamp(stat.st_mtime).isoformat(),
                'size_kb': round(stat.st_size / 1024, 1),
            })
    results.sort(key=lambda x: x['modified'], reverse=True)
    return results


def search_sessions(projects_dir: Path, keyword: str, slug: str | None = None) -> list[dict]:
    keyword_lower = keyword.lower()
    results = []
    for proj_dir in find_project_slug(projects_dir, slug):
        for f in proj_dir.glob('*.jsonl'):
            uuid = f.stem
            title = None
            matches = []
            try:
                with open(f, encoding='utf-8') as fh:
                    for line in fh:
                        line = line.strip()
                        if not line:
                            continue
                        obj = json.loads(line)
                        if obj.get('type') == 'ai-title' and not title:
                            title = obj.get('aiTitle', '')
                        if obj.get('type') in ('user', 'assistant'):
                            content = obj.get('message', {}).get('content', '')
                            text = _extract_text(content)
                            if keyword_lower in text.lower():
                                matches.append(text[:200])
            except Exception:
                continue
            if keyword_lower in (title or '').lower() or matches:
                stat = f.stat()
                results.append({
                    'uuid': uuid,
                    'project': proj_dir.name,
                    'title': title,
                    'match_count': len(matches),
                    'first_match': matches[0] if matches else title,
                    'modified': datetime.fromtimestamp(stat.st_mtime).isoformat(),
                })
    results.sort(key=lambda x: x['match_count'], reverse=True)
    return results


def _extract_text(content) -> str:
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        parts = []
        for c in content:
            if not isinstance(c, dict):
                continue
            if c.get('type') == 'text':
                parts.append(c['text'])
            elif c.get('type') == 'tool_result':
                rc = c.get('content', '')
                if isinstance(rc, str) and rc.strip():
                    parts.append(rc)
                elif isinstance(rc, list):
                    for r in rc:
                        if isinstance(r, dict) and r.get('type') == 'text' and r.get('text', '').strip():
                            parts.append(r['text'])
        return '\n'.join(parts)
    return ''


def _is_noise_user(text: str) -> bool:
    return bool(
        '<local-command-caveat>' in text
        or '<command-name>' in text
        or text.strip() == ''
    )


def _is_noise_assistant(text: str) -> bool:
    return bool(
        'API Error:' in text
        or 'Please run /login' in text
        or text.strip() == ''
        or len(text.strip()) < 10
    )


def extract_session(jsonl_path: Path, claude_dir: Path) -> dict:
    lines = jsonl_path.read_text(encoding='utf-8').splitlines()

    metadata = {
        'uuid': jsonl_path.stem,
        'project': jsonl_path.parent.name,
        'file': str(jsonl_path),
    }
    user_messages = []
    assistant_messages = []
    file_deltas = []
    tool_uses = []
    title = None
    last_prompt = None

    for raw in lines:
        raw = raw.strip()
        if not raw:
            continue
        try:
            obj = json.loads(raw)
        except json.JSONDecodeError:
            continue

        rec_type = obj.get('type')

        if rec_type == 'mode':
            metadata['mode'] = obj.get('mode')

        elif rec_type == 'ai-title':
            title = obj.get('aiTitle')

        elif rec_type == 'last-prompt':
            last_prompt = obj.get('lastPrompt')

        elif rec_type == 'attachment':
            if not metadata.get('cwd'):
                metadata['cwd'] = obj.get('cwd')
                metadata['branch'] = obj.get('gitBranch')
                metadata['entrypoint'] = obj.get('entrypoint')
                metadata['version'] = obj.get('version')
                metadata['started'] = obj.get('timestamp')

        elif rec_type == 'user':
            content = obj.get('message', {}).get('content', '')
            is_meta = obj.get('isMeta', False)
            if is_meta:
                continue

            has_text = False
            has_tool_results = False
            if isinstance(content, list):
                for c in content:
                    if isinstance(c, dict):
                        if c.get('type') == 'text':
                            has_text = True
                        elif c.get('type') == 'tool_result':
                            has_tool_results = True
            elif isinstance(content, str):
                has_text = bool(content.strip())

            if has_tool_results and not has_text:
                continue

            text = _extract_text(content)
            if not _is_noise_user(text):
                user_messages.append({
                    'text': text,
                    'timestamp': obj.get('timestamp'),
                })

        elif rec_type == 'assistant':
            msg = obj.get('message', {})
            content = msg.get('content', [])
            text_parts = []
            tools = []
            if isinstance(content, list):
                for c in content:
                    if isinstance(c, dict):
                        if c.get('type') == 'text':
                            text_parts.append(c['text'])
                        elif c.get('type') == 'tool_use':
                            tool_name = c.get('name', '')
                            tool_input = c.get('input', {})
                            summary = tool_name
                            if 'command' in tool_input:
                                summary += f': {str(tool_input["command"])[:80]}'
                            elif 'file_path' in tool_input:
                                summary += f': {tool_input["file_path"]}'
                            tools.append(summary)
            elif isinstance(content, str):
                text_parts.append(content)

            text = '\n'.join(text_parts)
            if not _is_noise_assistant(text) or tools:
                entry = {'timestamp': obj.get('timestamp')}
                if text and not _is_noise_assistant(text):
                    entry['text'] = text
                if tools:
                    entry['tools'] = tools
                assistant_messages.append(entry)

        elif rec_type == 'file-history-delta':
            file_deltas.append({
                'path': obj.get('trackingPath'),
                'backup': obj.get('backup', {}).get('backupFileName'),
                'version': obj.get('backup', {}).get('version'),
                'time': obj.get('backup', {}).get('backupTime'),
            })

    metadata['title'] = title
    metadata['last_prompt'] = last_prompt

    # Check file-history directory
    hist_dir = claude_dir / 'file-history' / metadata['uuid']
    file_history = []
    if hist_dir.exists() and hist_dir.is_dir():
        for entry in sorted(hist_dir.iterdir()):
            file_history.append({
                'name': entry.name,
                'size': entry.stat().st_size,
            })

    # Build file change summary from deltas
    files_changed = {}
    for d in file_deltas:
        path = d['path']
        if path not in files_changed:
            files_changed[path] = {
                'path': path,
                'is_new': d['backup'] is None,
                'versions': d['version'],
                'first_change': d['time'],
            }
        else:
            files_changed[path]['versions'] = max(
                files_changed[path]['versions'], d['version']
            )

    return {
        'metadata': metadata,
        'user_messages': user_messages,
        'assistant_messages': assistant_messages,
        'files_changed': list(files_changed.values()),
        'file_history_backups': file_history,
    }


def main():
    parser = argparse.ArgumentParser(description='Extract Claude Code CLI session context')
    parser.add_argument('uuid', nargs='?', help='Session UUID')
    parser.add_argument('--list', action='store_true', help='List recent sessions')
    parser.add_argument('--search', type=str, help='Search sessions by keyword')
    parser.add_argument('--project-slug', type=str, help='Project directory slug (e.g. D--my-project)')
    parser.add_argument('--claude-dir', type=str, help='Override ~/.claude path')
    parser.add_argument('--summary', action='store_true', help='Output human-readable summary instead of JSON')
    args = parser.parse_args()

    claude_dir = get_claude_dir(args.claude_dir)
    projects_dir = get_projects_dir(claude_dir)

    if args.list:
        sessions = list_sessions(projects_dir, args.project_slug)
        if args.summary:
            for s in sessions[:20]:
                print(f'{s["uuid"]}  {s["title"] or "(untitled)":50s}  {s["modified"][:16]}  {s["project"]}')
        else:
            print(json.dumps(sessions[:20], indent=2, ensure_ascii=False))
        return

    if args.search:
        results = search_sessions(projects_dir, args.search, args.project_slug)
        if args.summary:
            for r in results[:10]:
                print(f'{r["uuid"]}  {r["title"] or "(untitled)":50s}  matches:{r["match_count"]}')
                if r.get('first_match'):
                    print(f'  → {r["first_match"][:120]}')
        else:
            print(json.dumps(results[:10], indent=2, ensure_ascii=False))
        return

    if not args.uuid:
        parser.error('Provide a session UUID, or use --list / --search')

    jsonl_path = find_session_file(projects_dir, args.uuid, args.project_slug)
    if not jsonl_path:
        print(json.dumps({'error': f'Session {args.uuid} not found', 'searched': str(projects_dir)}),
              file=sys.stderr)
        sys.exit(1)

    data = extract_session(jsonl_path, claude_dir)

    if args.summary:
        m = data['metadata']
        print(f'# Session: {m.get("title", "(untitled)")}')
        print(f'UUID: {m["uuid"]}')
        print(f'Project: {m["project"]}')
        print(f'CWD: {m.get("cwd", "?")}')
        print(f'Branch: {m.get("branch", "?")}')
        print(f'Started: {m.get("started", "?")}')
        print()

        if data['files_changed']:
            print('## Files Changed')
            for f in data['files_changed']:
                tag = 'NEW' if f['is_new'] else 'MOD'
                print(f'  [{tag}] {f["path"]}')
            print()

        print('## Conversation')
        all_msgs = []
        for msg in data['user_messages']:
            all_msgs.append(('USER', msg.get('timestamp', ''), msg))
        for msg in data['assistant_messages']:
            all_msgs.append(('ASSISTANT', msg.get('timestamp', ''), msg))
        all_msgs.sort(key=lambda x: x[1])

        for role, ts, msg in all_msgs:
            ts_short = ts[:16] if ts else ''
            if role == 'USER':
                print(f'\n### USER ({ts_short})')
                print(msg['text'])
            else:
                if msg.get('text'):
                    print(f'\n### ASSISTANT ({ts_short})')
                    print(msg['text'])
                if msg.get('tools'):
                    if not msg.get('text'):
                        print(f'\n### ASSISTANT tools ({ts_short})')
                    for t in msg['tools']:
                        print(f'  → {t}')

        if m.get('last_prompt'):
            print(f'\n## Last Prompt')
            print(m['last_prompt'])
    else:
        print(json.dumps(data, indent=2, ensure_ascii=False))


if __name__ == '__main__':
    main()
