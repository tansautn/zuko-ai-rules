# Scripts

Automation scripts for the zuko-ai-rules repository.

## Overview

| Script | Purpose |
|--------|---------|
| `spread-master.sh` | Merge master branch changes into all other branches |
| `mirror-sync.sh` | Sync files from external GitHub repositories |
| `install-excludes.sh` | Configure `claudeMdExcludes` for parent projects using this repo as submodule |
| `update-changelog.sh` | Generate/update CHANGELOG.md from git history |

## spread-master.sh

Merges `master` into every remote branch using a temporary git worktree.

```bash
./scripts/spread-master.sh
```

**Behavior:**
- **CI** (`$GITHUB_ACTIONS` / `$CI`): fails immediately on merge conflicts
- **Local**: pauses and polls every 10s, waiting for manual conflict resolution in the worktree at `tmp/spread-master/`

**Requirements:** git

## mirror-sync.sh

Syncs files from external GitHub repos based on `mirror-sources.json`.

```bash
./scripts/mirror-sync.sh [--dry-run] [--source-id ID]
```

**Source types:**
- `git` — fetch raw files from a branch (default)
- `release` — fetch from a release source archive
- `release_asset` — fetch & optionally extract release assets

**Options:**
- `--dry-run` — preview without making changes
- `--source-id ID` — sync a single source only

**Environment:**
- `GITHUB_TOKEN` — GitHub PAT for authenticated API calls (avoids 60 req/h unauthenticated limit)

**Requirements:** jq, git, curl, tar. On Windows, auto-installs jq via winget if missing.

**Config:** `mirror-sources.json` (looked up in `$CWD` first, then `scripts/`). Optionally updates `config.json` version fields after sync.

## install-excludes.sh

Adds this repo's `CLAUDE.md` to the parent project's exclude list so it doesn't conflict with the parent's own instructions.

```bash
# Run from the PARENT project root
.agents/zuko-ai-rules/scripts/install-excludes.sh
.agents/zuko-ai-rules/scripts/install-excludes.sh --submodule-path .agents/zuko-ai-rules
```

Auto-detects submodule path from `.gitmodules`. Writes to `.claude/settings.local.json`.

**Requirements:** jq

## update-changelog.sh

Generates changelog entries from git commit history.

```bash
./scripts/update-changelog.sh <version> <is_release>
# Examples:
./scripts/update-changelog.sh dev-abc1234 false   # dev build — wrapped in DEV markers
./scripts/update-changelog.sh v1.2.0 true          # release — permanent entry
```

- Skips merge commits and `chore(changelog)` commits
- Dev builds: replaces the `<!-- DEV_CHANGELOG_START -->` block (idempotent)
- Releases: strips dev block, inserts permanent `## [version]` section
- Exits with code 2 if log lines unchanged (no-op signal)

**Requirements:** git (full history, `fetch-depth: 0`)
