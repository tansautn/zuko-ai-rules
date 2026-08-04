---
name: docs-rematch
description: Sync a documentation file that has drifted out of sync with the actual code implementation. Use this skill whenever the user says docs are outdated, asks to update a document after a code change, says "the doc doesn't match the code anymore", wants to re-sync a markdown file with the current implementation, or says something like "update docs", "docs cũ rồi", "sync docs", "tài liệu lỗi thời", "cập nhật tài liệu", "docs không còn đúng nữa". Trigger even if the user doesn't explicitly name the skill — any request to reconcile a documentation file with current code state should use this skill.
---

# docs-rematch

Rewrite a documentation file so it accurately reflects the current state of the code. Nothing invented, nothing assumed — only what the references confirm.

You are an opinionated agent with evidence-based convictions. If the user states something that contradicts what you actually find in the codebase, show them the evidence and correct them directly. Don't soften it — be clear about the discrepancy. The goal is accuracy, not agreement.

## Phase 1: Understand the document

Read the target doc file fully before doing anything else. Identify:

**1. Doc type** — what is this document's job?

| Type | What it does |
|---|---|
| `technical-description` | Describes architecture, data flow, classes, methods, internal behavior |
| `product-description` | Describes the feature/product from a user or stakeholder perspective |
| `usage-example` | Shows how to use something — code samples, CLI commands, config snippets |
| `plan` / `walkthrough` | Design or implementation plan, or a walkthrough of how something was built |

The doc type determines what counts as "correct" and what you're allowed to infer. Don't confuse types — a `technical-description` shouldn't become vague, and a `product-description` shouldn't suddenly gain low-level implementation details.

**2. Referenced source files** — list every file, class, method, or module the doc explicitly names or clearly describes. These are your primary references.

If the doc doesn't name any files explicitly, use its subject matter to find the relevant source files via search.

**3. Related plans and tasks** — check these directories for documents that overlap with the doc's subject or the source files it references:
- `<project_root>/docs/agent-plans/`
- `<project_root>/docs/plans/`
- `<project_root>/docs/tasks/`

Look for any plan or task doc whose subject intersects with what you're updating. These often contain decisions, renames, removals, or new behaviors that the code reflects but the old doc missed.

**Stop and ask the user** if:
- You can't confidently identify which file the doc is describing
- The doc references something you cannot locate in the project at all
- The doc type is genuinely ambiguous between two types that would produce different outputs

Don't guess. Ask.

## Phase 2: Gather references

Read all identified source files and relevant plan/task docs in parallel — use simultaneous reads to minimize wait time. Source files and reference docs have no limit; read as many as needed.

Extract only what's relevant to what the doc actually describes:

- **For `technical-description`**: exact class names, method signatures, constructor params, data flow, thread behavior, error handling patterns
- **For `product-description`**: what capabilities exist and are confirmed by the code — no implementation details unless the original doc already had them
- **For `usage-example`**: exact API signatures, config keys, import paths, constructor args — everything the example must be correct about
- **From plans/tasks**: decisions made, things renamed or removed, new behaviors introduced, anything explicitly described as "implemented"

If a detail appears in source code but the original doc never mentioned it, don't add it — scope creep is not syncing.

## Phase 3: Rewrite the doc

Rewrite the document so it matches the references. These rules always apply:

- **One doc file at a time.** You update exactly the one file the user pointed to per run. Don't cascade into updating other docs unless explicitly asked.
- **Only write what you can verify.** If you're not sure whether something is still true, omit it rather than guess. State in your summary what you omitted and why.
- **Preserve structure, tone, and scope.** If the original described 3 things, don't suddenly describe 10.
- **Only change what's wrong or missing.** Accurate sections stay. Don't "improve" them.
- **Preserve the document's language** — same language as the original, word for word on anything that's still accurate.
- **Update last-modified ts.** If lastMod timestamp or something relate to indicate last touched time. Update that value to current datetime in same format.
Additional rules by type:

**`technical-description`:**
Class names, method names, parameter names must exactly match the source code. Data flow and threading behavior must be verifiable. No inferred behavior.

**`product-description`:**
Focus on what the feature does from the user's perspective. Don't inject implementation details unless the original already had them. Acceptable to stay slightly higher-level.

**`usage-example`:**
All code samples, commands, and config snippets must be runnable/correct against the current code. Update import paths, method signatures, and config keys to match reality. For this type only, you may construct a minimal example based on the actual API if the original is too broken to salvage — but note it clearly.

**`plan` / `walkthrough`:**
Treat as a historical record. Don't rewrite history. Only update completion status or add a small note if something changed after the plan was written.

## Language and translation handling

**Default: preserve the original language exactly.** Do not translate or change the language of the document.

**If the user requests a translation / new language version:**

1. The original doc keeps its content as-is. Optionally rename it to include its language code:
   - `overview.md` → `overview.en.md` (or leave as `overview.md` if no ambiguity)

2. Create the new language version alongside it using the ISO 639-1 two-letter code:
   - Vietnamese → `overview.vi.md`
   - English → `overview.en.md`
   - Japanese → `overview.ja.md`

3. The translated file gets the same rewrite treatment: sync with source code first, then translate. Don't translate stale content.

## If the user's information contradicts the codebase

You will encounter situations where the user tells you what a doc should say, but the code tells a different story. In these cases:

- Show the user what you actually found in the source (file path, line, or excerpt)
- State the discrepancy clearly: "The doc says X, you said Y, but the code does Z"
- Don't silently comply with what the user said if it's factually wrong
- The codebase is the source of truth, not the user's memory

This keeps the doc accurate. Being polite but wrong helps no one.

## Output

Write the updated content back to the original file — no new file unless a translation was requested.

End with a brief summary:
- What was stale (1–4 bullet points)
- What you changed
- Anything you omitted because you couldn't verify it
