# CLAUDE.md — Zuko AI Rules Repository

> **Scope**: This CLAUDE.md governs the rules repo itself — how to create/edit rules, scripts, and configs.
> It does NOT contain project-specific coding instructions.
> Projects that add this repo as a submodule should exclude this file via `claudeMdExcludes`.
> See `rules/020-submodule-setup.md` for setup instructions.

---

## Repository Structure

```
rules/          # Agent rules (.md/.mdc) — enforced per-branch
skills/         # Claude Code skills (slash commands)
system-prompts/ # Sub-agent system prompts
scripts/        # Automation scripts
```

**Branches** = rule sets: `master` (general), `python-qt`, `php-laravel`, `csharp-winform`.

## Writing Rules

Follow `rules/200-cursor-rules.md` for rule standardization.

### Format

- Frontmatter: `description`, `globs`, `alwaysApply`
- Start with core objective, anti-patterns, rationale
- **MUST** include DO/DON'T code examples
- Use bold for key terms, UPPERCASE for required actions
- Cross-reference other rules instead of duplicating content

### Naming

- `000-*`: Must-read foundation rules (read before any writes)
- `001-019`: Project-wide conventions
- `020-029`: Tooling, sync, setup documentation
- `200+`: Meta-rules (how to write rules)

### System Prompts

See `system-prompts/README.md` for the 6-pillar structured prompt architecture:
`<system_context>` → `<ethos>` → `<domain_knowledge>` → `<examples>` → `<output_format>` → `<user_input>`

## Scripts

| Script | Purpose |
|--------|---------|
| `scripts/mirror-sync.sh` | Sync files from external GitHub repos. See `rules/020-mirror-source.md` |
| `scripts/spread-master.sh` | Spread master branch changes to other branches |
| `scripts/install-excludes.sh` | Install `claudeMdExcludes` for parent projects using this as submodule. See `rules/020-submodule-setup.md` |

## Git Rules

- **Never `git add .`** — only add files you created or changed
- Untracked files in this repo are intentional (skills/, examples, etc.)
