#!/usr/bin/env python3
"""Extract conversation context from a Claude Code CLI session JSONL file.

Usage:
    python extract_session.py <uuid> [--summary] [--project-slug <slug>] [--claude-dir <path>]
    python extract_session.py --list [--today] [--project-slug <slug>] [--summary]
    python extract_session.py --search <keyword> [--project-slug <slug>] [--summary]
    python extract_session.py --find-live [--exclude <uuid>] [--project-slug <slug>]
    python extract_session.py --write-title --target <jsonl-path> --title "<text>"

Output: JSON with session metadata, user/assistant messages, and file history
(or a human-readable summary with --summary).
"""

import argparse
import json
import os
import sys
from pathlib import Path
from datetime import datetime, date

sys.stdout.reconfigure(encoding='utf-8')
sys.stderr.reconfigure(encoding='utf-8')

# Title record precedence: a user-set title wins, then an auto summary,
# then the model's ai-title. Field name per record type.
TITLE_SOURCES = [
    ('custom-title', 'customTitle'),
    ('summary', 'summary'),
    ('ai-title', 'aiTitle'),
]


def get_claude_dir(override=None):
    return Path(override) if override else Path.home() / '.claude'


def get_projects_dir(claude_dir):
    return claude_dir / 'projects'


def find_project_slug(projects_dir, slug=None):
    if not projects_dir.exists():
        return []
    if slug:
        target = projects_dir / slug
        return [target] if target.exists() else []
    return [p for p in projects_dir.iterdir() if p.is_dir()]


def find_session_file(projects_dir, uuid, slug=None):
    fname = f'{uuid}.jsonl'
    for proj_dir in find_project_slug(projects_dir, slug):
        candidate = proj_dir / fname
        if candidate.exists():
            return candidate
    return None


def _extract_text(content):
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


def _is_noise_user(text):
    return bool(
        '<local-command-caveat>' in text
        or '<command-name>' in text
        or text.strip() == ''
        or text.strip().lower() in ('again', 'continue', 'go', 'go on', 'next')
    )


def _is_noise_assistant(text):
    return bool(
        'API Error:' in text
        or 'Please run /login' in text
        or text.strip() == ''
        or len(text.strip()) < 10
    )


def _resolve_title(titles, first_user_text=None):
    """Pick a display title by precedence; fall back to first real prompt."""
    for rtype, _field in TITLE_SOURCES:
        val = titles.get(rtype)
        if val:
            return val
    if first_user_text:
        snippet = ' '.join(first_user_text.split())[:60]
        if snippet:
            return snippet + ('…' if len(first_user_text) > 60 else '')
    return None


def _scan_titles(fh, want_first_user=False):
    """Read a file handle once, collecting all title candidates (+ first user msg)."""
    titles = {}
    first_user = None
    for line in fh:
        line = line.strip()
        if not line:
            continue
        try:
            obj = json.loads(line)
        except json.JSONDecodeError:
            continue
        rtype = obj.get('type')
        for src_type, field in TITLE_SOURCES:
            if rtype == src_type and src_type not in titles:
                titles[src_type] = obj.get(field)
        if want_first_user and first_user is None and rtype == 'user' and not obj.get('isMeta'):
            text = _extract_text(obj.get('message', {}).get('content', ''))
            if not _is_noise_user(text):
                first_user = text
        # custom-title is highest precedence; once we have it (and first user if needed) stop early
        if 'custom-title' in titles and (not want_first_user or first_user is not None):
            break
    return titles, first_user


def list_sessions(projects_dir, slug=None, today_only=False):
    results = []
    today = date.today()
    for proj_dir in find_project_slug(projects_dir, slug):
        for f in proj_dir.glob('*.jsonl'):
            stat = f.stat()
            mtime = datetime.fromtimestamp(stat.st_mtime)
            if today_only and mtime.date() != today:
                continue
            cwd = branch = None
            try:
                with open(f, encoding='utf-8') as fh:
                    titles, first_user = _scan_titles(fh, want_first_user=True)
                # cwd/branch need a second light pass only if not found above; grab from attachment
                with open(f, encoding='utf-8') as fh:
                    for line in fh:
                        line = line.strip()
                        if not line:
                            continue
                        try:
                            obj = json.loads(line)
                        except json.JSONDecodeError:
                            continue
                        if obj.get('type') == 'attachment':
                            cwd = obj.get('cwd')
                            branch = obj.get('gitBranch')
                            break
            except Exception:
                titles, first_user = {}, None
            results.append({
                'uuid': f.stem,
                'project': proj_dir.name,
                'title': _resolve_title(titles, first_user),
                'cwd': cwd,
                'branch': branch,
                'modified': mtime.isoformat(),
                'size_kb': round(stat.st_size / 1024, 1),
            })
    results.sort(key=lambda x: x['modified'], reverse=True)
    return results


def search_sessions(projects_dir, keyword, slug=None):
    kw = keyword.lower()
    results = []
    for proj_dir in find_project_slug(projects_dir, slug):
        for f in proj_dir.glob('*.jsonl'):
            titles = {}
            first_user = None
            matches = []
            try:
                with open(f, encoding='utf-8') as fh:
                    for line in fh:
                        line = line.strip()
                        if not line:
                            continue
                        try:
                            obj = json.loads(line)
                        except json.JSONDecodeError:
                            continue
                        rtype = obj.get('type')
                        for src_type, field in TITLE_SOURCES:
                            if rtype == src_type and src_type not in titles:
                                titles[src_type] = obj.get(field)
                        if rtype in ('user', 'assistant'):
                            text = _extract_text(obj.get('message', {}).get('content', ''))
                            if rtype == 'user' and first_user is None and not obj.get('isMeta') and not _is_noise_user(text):
                                first_user = text
                            if kw in text.lower():
                                matches.append(text[:200])
            except Exception:
                continue
            title = _resolve_title(titles, first_user)
            if kw in (title or '').lower() or matches:
                stat = f.stat()
                results.append({
                    'uuid': f.stem,
                    'project': proj_dir.name,
                    'title': title,
                    'match_count': len(matches),
                    'first_match': matches[0] if matches else title,
                    'modified': datetime.fromtimestamp(stat.st_mtime).isoformat(),
                })
    results.sort(key=lambda x: x['match_count'], reverse=True)
    return results


def find_live_session(projects_dir, slug=None, exclude=None):
    """Return the most-recently-modified transcript — the session being written
    right now is almost always the live one. Excludes a uuid (the one just resumed)."""
    newest = None
    for proj_dir in find_project_slug(projects_dir, slug):
        for f in proj_dir.glob('*.jsonl'):
            if exclude and f.stem == exclude:
                continue
            mt = f.stat().st_mtime
            if newest is None or mt > newest[0]:
                newest = (mt, f)
    return newest[1] if newest else None


def write_custom_title(target, title):
    """Append a custom-title record to a transcript JSONL (same shape /rename writes).
    Best-effort: the host may ignore or overwrite it."""
    target = Path(target)
    if not target.exists():
        raise FileNotFoundError(f'target transcript not found: {target}')
    record = {
        'type': 'custom-title',
        'customTitle': title,
        'sessionId': target.stem,
        'timestamp': datetime.now().astimezone().isoformat(),
    }
    with open(target, 'a', encoding='utf-8') as fh:
        fh.write(json.dumps(record, ensure_ascii=False) + '\n')
    return record


def extract_session(jsonl_path, claude_dir):
    lines = jsonl_path.read_text(encoding='utf-8').splitlines()
    metadata = {'uuid': jsonl_path.stem, 'project': jsonl_path.parent.name, 'file': str(jsonl_path)}
    user_messages, assistant_messages, file_deltas = [], [], []
    titles = {}
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

        for src_type, field in TITLE_SOURCES:
            if rec_type == src_type and src_type not in titles:
                titles[src_type] = obj.get(field)

        if rec_type == 'mode':
            metadata['mode'] = obj.get('mode')
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
            if obj.get('isMeta'):
                continue
            content = obj.get('message', {}).get('content', '')
            has_text = has_tool_results = False
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
                user_messages.append({'text': text, 'timestamp': obj.get('timestamp')})
        elif rec_type == 'assistant':
            content = obj.get('message', {}).get('content', [])
            text_parts, tools = [], []
            if isinstance(content, list):
                for c in content:
                    if isinstance(c, dict):
                        if c.get('type') == 'text':
                            text_parts.append(c['text'])
                        elif c.get('type') == 'tool_use':
                            name = c.get('name', '')
                            inp = c.get('input', {})
                            s = name
                            if 'command' in inp:
                                s += f': {str(inp["command"])[:80]}'
                            elif 'file_path' in inp:
                                s += f': {inp["file_path"]}'
                            tools.append(s)
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

    first_user = user_messages[0]['text'] if user_messages else None
    metadata['title'] = _resolve_title(titles, first_user)
    metadata['title_source'] = next((t for t, _ in TITLE_SOURCES if titles.get(t)), 'derived' if first_user else None)
    metadata['last_prompt'] = last_prompt

    hist_dir = claude_dir / 'file-history' / metadata['uuid']
    file_history = []
    if hist_dir.exists() and hist_dir.is_dir():
        for entry in sorted(hist_dir.iterdir()):
            file_history.append({'name': entry.name, 'size': entry.stat().st_size})

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
            files_changed[path]['versions'] = max(files_changed[path]['versions'], d['version'])

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
    parser.add_argument('--today', action='store_true', help='With --list: only sessions modified today')
    parser.add_argument('--search', type=str, help='Search sessions by keyword')
    parser.add_argument('--find-live', action='store_true', help='Print path of the live (most-recent) transcript')
    parser.add_argument('--exclude', type=str, help='With --find-live: uuid to exclude (the one just resumed)')
    parser.add_argument('--write-title', action='store_true', help='Append a custom-title record to --target')
    parser.add_argument('--target', type=str, help='With --write-title: transcript JSONL path')
    parser.add_argument('--title', type=str, help='With --write-title: title text')
    parser.add_argument('--project-slug', type=str, help='Project dir slug (e.g. D--my-project)')
    parser.add_argument('--claude-dir', type=str, help='Override ~/.claude path')
    parser.add_argument('--summary', action='store_true', help='Human-readable output')
    args = parser.parse_args()

    claude_dir = get_claude_dir(args.claude_dir)
    projects_dir = get_projects_dir(claude_dir)

    if args.write_title:
        if not args.target or not args.title:
            parser.error('--write-title requires --target and --title')
        try:
            rec = write_custom_title(args.target, args.title)
            print(json.dumps({'ok': True, 'wrote': rec}, ensure_ascii=False))
        except Exception as e:
            print(json.dumps({'ok': False, 'error': str(e)}), file=sys.stderr)
            sys.exit(1)
        return

    if args.find_live:
        live = find_live_session(projects_dir, args.project_slug, args.exclude)
        if live:
            print(str(live))
        else:
            print(json.dumps({'error': 'no live session found', 'searched': str(projects_dir)}), file=sys.stderr)
            sys.exit(1)
        return

    if args.list:
        sessions = list_sessions(projects_dir, args.project_slug, today_only=args.today)
        if args.summary:
            for s in sessions[:20]:
                print(f'{s["uuid"]}  {s["modified"][:16]}  {(s["title"] or "(untitled)")[:50]:50s}  {s["project"]}')
        else:
            print(json.dumps(sessions[:20], indent=2, ensure_ascii=False))
        return

    if args.search:
        results = search_sessions(projects_dir, args.search, args.project_slug)
        if args.summary:
            for r in results[:10]:
                print(f'{r["uuid"]}  {(r["title"] or "(untitled)")[:50]:50s}  matches:{r["match_count"]}')
                if r.get('first_match'):
                    print(f'  → {r["first_match"][:120]}')
        else:
            print(json.dumps(results[:10], indent=2, ensure_ascii=False))
        return

    if not args.uuid:
        parser.error('Provide a session UUID, or use --list / --search / --find-live / --write-title')

    jsonl_path = find_session_file(projects_dir, args.uuid, args.project_slug)
    if not jsonl_path:
        print(json.dumps({'error': f'Session {args.uuid} not found', 'searched': str(projects_dir)}), file=sys.stderr)
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
            print(f'\n## Last prompt\n{m["last_prompt"]}')
    else:
        print(json.dumps(data, indent=2, ensure_ascii=False))


if __name__ == '__main__':
    main()
