---
name: everything-local-search
description: "Locate files/folders and detect installed tools on the local Windows PC via the voidtools Everything HTTP Server JSON API."
---

# Everything local file search (HTTP JSON API)

Everything (voidtools) keeps an instant, full-machine index of every file and
folder on all NTFS volumes. Its HTTP Server exposes that index as a plain
`GET` JSON API. Prefer it over `dir`/`Get-ChildItem` recursion or PATH probing:
one request searches the whole machine in milliseconds.

Guiding principle: **the HTTP params are a 1:1 mirror of the desktop Search
menu.** Whatever toggle exists in the UI (Match Case, Match Whole Word, Match
Path, Match Diacritics, Enable Regex) has a corresponding query param — see the
mapping table below.

## When to use

- Confirm a tool exists and get its exact path before invoking or installing it.
- Enumerate every copy of a tool (multiple Node/Python/CMake versions) and
  choose one deliberately instead of relying on whatever `PATH` resolves.
- Find config/data/log/project files anywhere on disk by name, extension,
  path fragment, or regex.
- Decide the environment (which SDKs/toolchains are present) before choosing a
  build/make strategy or a download.

Do NOT use it to read file *contents* — it returns metadata only (name, path,
size, modified time). Read contents with the normal filesystem tools once you
have the path.

## Endpoint & transport

Base URL for this machine: `http://127.0.0.1:8086/`
(The port is user-configurable in Everything → Tools → Options → HTTP Server;
default is `80`. 8086 is this user's setting — confirm if requests fail.)

The request must originate ON the Windows host (or a machine that can route to
it). From a Windows-native shell (PowerShell / cmd) or a local agent, call it
directly. Note: a Linux/WSL/VM shell's `127.0.0.1` is the VM, NOT the PC — from
there target the host IP, not loopback.

PowerShell (recommended — handles encoding + JSON):

```powershell
function Find-Everything([string]$Search, [int]$Count = 20, [switch]$Regex, [switch]$MatchPath) {
    $base = 'http://127.0.0.1:8086/'
    $q = @(
        'json=1', 'path_column=1', 'size_column=1', 'date_modified_column=1',
        "count=$Count",
        ('regex=' + [int]$Regex.IsPresent), ('path=' + [int]$MatchPath.IsPresent),
        'search=' + [uri]::EscapeDataString($Search)
    ) -join '&'
    (Invoke-WebRequest -Uri ($base + '?' + $q) -UseBasicParsing).Content | ConvertFrom-Json
}

# examples
(Find-Everything '^cmake\.exe$' -Regex).results | ForEach-Object { "$($_.path)\$($_.name)" }
(Find-Everything '^C:\\Program Files.*\\node\.exe$' -Regex -MatchPath).results
```

curl (cmd / Git Bash) — URL-encode the search value (`space`->`%20`, `:` is ok):

```bash
curl "http://127.0.0.1:8086/?json=1&regex=1&path_column=1&count=20&search=%5Enode%5C.exe%24"
```

Python:

```python
import urllib.parse, urllib.request, json
def find_everything(search, count=20, regex=0, match_path=0):
    qs = urllib.parse.urlencode({
        "json": 1, "regex": regex, "path": match_path, "path_column": 1,
        "size_column": 1, "date_modified_column": 1, "count": count, "search": search,
    })
    with urllib.request.urlopen(f"http://127.0.0.1:8086/?{qs}") as r:
        return json.load(r)
```

If the HTTP Server has a username/password set, add Basic auth
(`Invoke-WebRequest -Credential`, `curl -u user:pass`). This machine's server is
currently open.

## UI toggles ↔ HTTP params (the mental model)

Each Search-menu toggle is one boolean query param. Value `1` = on, `0` = off.

| Search menu (UI) | Hotkey | HTTP param | Alias |
|---|---|---|---|
| Match Case | Ctrl+I | `case` | `i` |
| Match Whole Word | Ctrl+B | `wholeword` | `w` |
| Match Path | Ctrl+U | `path` | `p` |
| Match Diacritics | Ctrl+M | `diacritics` | `m` |
| Enable Regex | Ctrl+R | `regex` | `r` |

## Request parameters

Long form shown; all are `GET` query keys. Omit any you do not need.

| Param | Alias | Meaning | Values |
|---|---|---|---|
| `search` | `s`, `q` | search text (Everything syntax, see below) | any |
| `json` | `j` | return JSON instead of HTML | `1` (always set this) |
| `count` | `c` | max results returned | e.g. `20`, `100` |
| `offset` | `o` | skip first N results (paging) | `0`, `50`, ... |
| `path_column` | — | include `path` field | `1` (almost always set) |
| `size_column` | — | include `size` field | `1` |
| `date_modified_column` | — | include `date_modified` field | `1` |
| `sort` | — | sort field | `name`, `path`, `size`, `date_modified` |
| `ascending` | — | sort direction | `1` asc, `0` desc |
| `case` `wholeword` `path` `diacritics` `regex` | `i` `w` `p` `m` `r` | search toggles (see mapping above) | `0`/`1` |

Always request `json=1` and enable the columns you read; a field is absent from
the JSON unless its `*_column` flag is on.

## Response format

```json
{
  "totalResults": 913,
  "results": [
    {
      "type": "file",
      "name": "node.exe",
      "path": "C:\\Program Files\\nodejs",
      "size": "88849152",
      "date_modified": "133586176217993072"
    }
  ]
}
```

- `totalResults` is the count of ALL matches, not just the ones returned — use it
  as a cheap "is it installed / how many copies" probe with `count=0` or `count=1`.
- `results` length is capped by `count`.
- `type` is `"file"` or `"folder"`.
- `path` is the parent directory (no trailing slash). Full path = `path\name`.
- `size` is **bytes as a decimal string** (for a folder it is the recursive
  size). Cast to int64 before math.
- `date_modified` is a **Windows FILETIME string** (100-ns ticks since
  1601-01-01 UTC). Decode it, do not display raw.

### Decode size & date_modified

```powershell
[int64]$bytes = $item.size
[DateTime]::FromFileTimeUtc([int64]$item.date_modified)   # -> UTC DateTime
```

```python
from datetime import datetime, timedelta, timezone
size = int(item["size"])
modified = datetime(1601, 1, 1, tzinfo=timezone.utc) + timedelta(microseconds=int(item["date_modified"]) / 10)
```

## Everything search syntax (the important part)

Default matching is **substring in the filename** — `cmake.exe` also matches
`bscmake.exe`. That is fine for a broad sweep. For a precise match, control it
explicitly:

- **Anchored regex (most precise, preferred for tool detection).** Set
  `regex=1` and anchor: `^cmake\.exe$` returns only real `cmake.exe`, never
  `bscmake.exe`. Variants are easy: `^py(thon)?3?\d*\.exe$`,
  `^(g?make|ninja)\.exe$`.
- **What the regex anchors against depends on `path` (Match Path):**
  - `path=0` (default) — regex matches the **filename**. Anchor the name:
    `^node\.exe$`.
  - `path=1` — regex matches the **full path**. Anchor the path:
    `^C:\\Program Files.*\\node\.exe$`.
  (Verified: `regex=1&path=1&search=^C:\\1drv.*DB Browser.*$` returns only items
  under that folder.)
- `wfn:NAME` — whole-filename match without regex (`file: wfn:cmake.exe`).
  Equivalent to an anchored filename regex for a single literal name; use regex
  when you need alternation or patterns.
- `file:` / `folder:` — restrict result type. `ext:exe;bat;cmd` — by extension.
- `path:FRAGMENT` — require a substring in the full path
  (e.g. `path:\nodejs\ wfn:node.exe`). `parent:C:\dir` — direct children.
- wildcards `*` `?` in names (`python3*.exe`); `size:>100mb`; `dm:today`,
  `dm:thisyear`. Space = AND, `|` = OR, `!term` = NOT. `"phrase"` for spaces.

Note: `regex=1` and Everything's own function syntax (`file:`, `wfn:`, ...) are
mutually exclusive per query — in regex mode the whole `search` is one regex.
Express type/extension constraints inside the pattern, or drop regex and use
`wfn:` + the boolean toggles.

### Recipes for detecting the build/make environment

Regex mode, anchored (filename; `path=0`) — precise by construction:

```text
^node\.exe$                 # every Node install (sort by date to pick newest)
^python\.exe$               # (this machine: 900+ via venvs; add path scope, see below)
^git\.exe$
^cmake\.exe$
^cl\.exe$                   # MSVC compiler present?
^msbuild\.exe$
^(gcc|clang)\.exe$
^cargo\.exe$                # Rust toolchain
^(g?make|ninja)\.exe$       # make / ninja
```

Scope to a location with `path=1`, e.g. only Program Files pythons:
`regex=1&path=1&search=^C:\\Program Files.*\\python\.exe$`.

Pattern: query with `count=0` first to read `totalResults` (present? how many?);
if you need the actual path, re-query with `sort=date_modified&ascending=0` and
`count=1..5` to grab the newest copy.

## Guardrails

- Read-only tool. It never modifies files.
- Broad terms return huge `totalResults` (e.g. `python.exe` → 900+). Set a small
  `count` and prefer an anchored regex / `path=1` scope before listing.
- The full path is `path + \\ + name` — don't use `path` field alone as the file path.
- Everything only indexes what its config includes (NTFS volumes by default;
  network/removable drives only if enabled). A zero result means "not in the
  index," which usually but not always means "not on disk."
- If a request fails: verify Everything is running, the HTTP Server is enabled,
  and the port (8086 here) is correct; and that you are calling from the host,
  not a VM loopback.

## Verification

After locating a tool, confirm the chosen path is real and runnable before using
it (e.g. `& $path --version`). Cross-check `totalResults` against expectation:
if you expected one install and got 50, tighten the anchor / add `path=1` scope
and re-query rather than trusting the first row.