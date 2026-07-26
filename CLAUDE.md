# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

This is Zuko's AI rules repository containing:
- **Rules** (`rules/`): Cursor/AI agent rules in `.mdc` format for project enforcement
- **Skills** (`skills/`): Claude Code skills (slash commands) for various workflows
- **System Prompts** (`system-prompts/`): Sub-agent prompts for specialized tasks

Branch structure:
- `master`: General rules/prompts
- `python-qt`: PySide/PyQt specific rules
- `php-laravel`: Laravel 6.x+ rules  
- `csharp-winform`: C#/WinForm rules

## Key Rules (from `rules/000-general-rules.mdc`)

### Language
- Code, classes, methods, variables: **English only**
- Explanations: Vietnamese allowed for technical clarifications

### Doc-First Workflow
- Every change starts with documentation (requirement/why, step-by-step plan, Mermaid diagrams for complex logic)
- Place docs in `docs/agent-plans/` within the relevant module
- **Read file content before editing** - agent operates in Developer Co-Operative mode

### Code Navigation
- If the project has `codebase-memory-mcp` graph index: prefer MCP over grep/fuzzy search
- Use `context7` MCP for external library documentation lookup

### Git
- **Never `git add .`** - only add files you created or changed
- Projects have untracked files that should remain untracked

### Required
- Follow project-specific rules in the same directory as rule files
- Files starting with `000-` are must-read before any writes
- Strict compliance, no exceptions

## Task Workflow System

Tasks are managed across `docs/tasks/tasks-N.md` files, indexed by `docs/tasks/tasks-index.md`.

Task structure:
```markdown
### Task ID: {ID}
- **Title**: ...
- **File**: path/to/file
- **Complete**: [ ]
#### Prompt:
```

Workflow:
1. Find next task via `tasks-index.md` -> appropriate `tasks-N.md`
2. Implement per the prompt
3. Mark `Complete: [x]` in the task file
4. Update counts in `tasks-index.md`

## External Library Documentation

**Always use Context7 MCP before using external libraries:**
```
1. mcp_context7_resolve-library-id({ libraryName: "express" })
2. mcp_context7_get-library-docs({ context7CompatibleLibraryID: ... })
```

If Context7 fails, fall back to web search with "latest documentation mid 2025".

## Skills Structure

Each skill in `skills/` contains a `SKILL.md` file defining the slash command behavior. Notable skills include:
- `gstack/`: Full development toolkit with browse, QA, review, ship workflows
- `codebase-memory/`: Knowledge graph tools for code exploration
- `docs-rematch/`: Sync documentation with code
- `turnstile-spin/`: Cloudflare Turnstile setup
- `test-driven-development/`: TDD workflow
- Various architecture and pattern skills

## GitHub Workflow Templates

For new projects needing CI/CD:
- Triggers: push to master (dev artifact), release published (release artifact)
- Version: tag name for releases, `dev-{hash}` for commits
- Auto-update CHANGELOG.md from git log
- Customize build commands per project type (.NET, Node.js, Python)
