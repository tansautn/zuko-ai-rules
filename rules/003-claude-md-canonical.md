---
trigger: always_on
description: CLAUDE.md is the single source of truth for every AI coding agent. Other agent-config filenames must be symlinks to CLAUDE.md — never divergent copies.
globs: **/*
---

# CLAUDE.md — Canonical Agent Configuration

**One source of truth. No exceptions.**

Every AI coding agent runtime looks for its own filename in the repo root or the working directory (`AGENTS.md`, `GEMINI.md`, `.cursorrules`, `.github/copilot-instructions.md`, `.aider.conf.md`, `.windsurfrules`, etc.). Maintaining a separate copy per runtime **guarantees drift** — updates land in one file, others rot, and different agents behave differently on the same codebase.

This project fixes the problem at the filesystem level: **`CLAUDE.md` is the authoritative file. Every other runtime's filename must be a symlink pointing at the sibling `CLAUDE.md`.**

---

## Rules

1. **`CLAUDE.md` is canonical.** Every content change lands here — never in a mirror file.
2. **Other runtime filenames are symlinks.** No hard copies, no partial mirrors, no "just this one section is different."
3. **Scope-respecting.** A symlink always points to the `CLAUDE.md` in **the same directory**. `modules/Foo/AGENTS.md` → `modules/Foo/CLAUDE.md`, never to the root file.
4. **Hierarchical loading is preserved.** Agents that walk up directories (Claude Code) still find the correct scope via `CLAUDE.md`. Agents that only look at the root file (some Copilot / older Cursor setups) get the root scope, which is the correct fallback.
5. **`.agents/rules/` overrides nothing.** Rule files here are inputs referenced by `CLAUDE.md`, not competitors to it. Do not create per-runtime rule directories (`.cursor/rules/`, `.github/instructions/`, …).

---

## Recognised runtime filenames (must symlink → `./CLAUDE.md` if present)

| Runtime | Filename it looks for |
|---|---|
| Claude Code | `CLAUDE.md` *(the canonical target)* |
| OpenAI Codex CLI / Codex agents | `AGENTS.md` |
| GitHub Copilot (repo instructions) | `.github/copilot-instructions.md` |
| Gemini CLI | `GEMINI.md` |
| Cursor | `.cursorrules` (legacy) — modern Cursor uses `.cursor/rules/*.mdc`; still, if a root `.cursorrules` is present, symlink it |
| Aider | `.aider.conf.md` |
| Windsurf | `.windsurfrules` |
| Continue.dev | `.continue/config.json` — **not** a Markdown mirror; leave it alone |

Any runtime not in this table but expecting a single `.md` prompt file: apply the same rule.

---

## How to add a mirror

```bash
# From the directory that already contains CLAUDE.md
ln -s CLAUDE.md AGENTS.md
ln -s CLAUDE.md GEMINI.md
mkdir -p .github && ln -s ../CLAUDE.md .github/copilot-instructions.md
```

On Windows in Git Bash, `ln -s` creates a Git-tracked symlink (`core.symlinks=true` must be on — it is in this repo, verified via `git config --list`). Verify:

```bash
git ls-files -s AGENTS.md   # mode 120000 = symlink
readlink AGENTS.md          # should print: CLAUDE.md
```

---

## Anti-patterns

```
# ❌ DON'T: keep two full files
CLAUDE.md               (900 lines)
AGENTS.md               (872 lines, drifted)

# ❌ DON'T: keep "just a header" mirrors
AGENTS.md: "See CLAUDE.md"          ← still a divergent regular file; a partial-truth mirror is worse than none

# ❌ DON'T: cross-scope symlinks
modules/Foo/AGENTS.md → ../../CLAUDE.md    ← breaks scope; module agents lose module-level rules

# ✅ DO: same-scope symlink
modules/Foo/AGENTS.md → CLAUDE.md          ← relative, sibling target, correct scope
```

---

## Enforcement

- On PR review, reject any commit that adds or edits a mirror filename as a regular file.
- When authoring a new mirror, create it **only** with `ln -s`. If your OS/tooling cannot produce a symlink, do not create the mirror — file an issue instead.
- Any script that scaffolds agent-config for a new tool must emit a symlink, not a copy.
