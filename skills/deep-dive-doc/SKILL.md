---
name: deep-dive-doc
description: >
  Sub-skill of what-this-repo-is. Activate IMMEDIATELY after any repo summary that contains a
  "Key Docs", "Key Points", or "📁 Docs Overview" section — no URL needed again. Use when the user
  says "deep dive", "go deeper", "explain X", "dive into", "more about [doc/aspect]", "/deep-dive",
  "/deep-dive-doc", references a specific file from the Key Docs table, or asks a follow-up question
  about a specific aspect of the repo that was just summarized. Also trigger on casual follow-ups like
  "tell me more about the architecture", "how does the daemon work?", "what's in CLI_AND_DAEMON.md?"
  The active repo URL and context carry forward from the previous what-this-repo-is output —
  never ask the user to re-provide the URL.
parent: what-this-repo-is
---

# Deep-Dive-Doc Skill

Extend a `what-this-repo-is` summary by fetching and analyzing a specific doc file or architectural
aspect of the repo that was just summarized.

## Preconditions

- A `what-this-repo-is` summary **must already exist** in the conversation (has "Key Docs" / "📁 Docs
  Overview" / "Key Points" section).
- The active `<owner>/<repo>` is inferred from that summary — do **not** ask the user to repeat it.

---

## Step 0 — Identify Target

From the user's follow-up, determine:

1. **Target**: a specific doc file (e.g. `CLI_AND_DAEMON.md`), a section name (e.g. "Architecture"),
   or a concept/aspect (e.g. "Skills system", "daemon", "WebSocket flow").
2. **Repo coords**: extract `owner/repo` from the previous summary's "Repo:" line.

If the target is ambiguous (user says "go deeper" with no specific aspect), present a numbered menu
of items from the Key Docs table and wait for selection. Do NOT proceed blind.

---

## Step 1 — Resolve File URL(s)

Map the target to fetchable URLs. Priority order:

| Target type | URL pattern to try |
|-------------|-------------------|
| Named doc file | `https://raw.githubusercontent.com/<owner>/<repo>/main/<FILE>` |
| Named doc file (fallback) | `https://github.com/<owner>/<repo>/blob/main/<FILE>` |
| Architecture aspect | Fetch `docs/` tree: `https://github.com/<owner>/<repo>/tree/main/docs` then pick most relevant file(s) |
| Concept (no file) | Search README first, then fetch the most relevant doc file based on section headings |

For ambiguous aspects (e.g. "daemon"), fetch up to **2 most relevant files** in parallel.

---

## Step 2 — Fetch & Extract

For each fetched file:

- Read fully (no truncation for files < 500 lines).
- For files > 500 lines: read first 300 lines + last 100 lines, note truncation.
- Extract:
  - Section headings (full hierarchy)
  - Key concepts, config options, data flow descriptions
  - Notable code snippets — **summarize what they do**, never reproduce verbatim blocks > 20 lines
  - Caveats, gotchas, prerequisites
  - Cross-references to other files → add to "Related Docs" output section

---

## Step 3 — Cross-Reference (optional, weight: 3)

If the fetched doc references other files (e.g. "See also: SELF_HOSTING.md"), and those are relevant
to the user's question, fetch up to **2 additional files** to fill gaps. Skip if the primary file
already answers the question completely.

---

## Step 4 — Synthesize Output

Use this template:

```markdown
## 🔬 Deep Dive: {Target Name}

> *From [`{filename}`]({github_url}) in `{owner}/{repo}`*

### TL;DR
{2–3 sentence plain-English summary of what this doc/aspect covers and why it matters.}

### Key Concepts

| Concept | Explanation |
|---------|-------------|
| {name} | {one-line description} |

### How It Works
{Narrative explanation of the mechanism / data flow / workflow. 3–7 paragraphs. Lead with the
"why", then the "how". Use subheadings if the doc has multiple distinct phases.}

### Configuration / Options
{Table or list of key config options, env vars, CLI flags — only if present in the doc.}
{Omit this section entirely if not applicable.}

### Gotchas & Caveats
- {Notable edge cases, warnings, or non-obvious behaviors from the doc}

### Related Docs
{List of cross-referenced files worth reading next, with one-line descriptions.}
{Omit if none found.}

---
*Deep dive sourced from: {list of fetched URLs}*
```

**Tone:** Match the repo's own documentation style. Technical but approachable. Never pad.

---

## Edge Cases

| Situation | Handling |
|-----------|----------|
| File 404 | Try `master` branch; if still 404, tell user and offer to search `docs/` tree |
| No Key Docs in prior summary | Refuse gracefully: "Run `/what-this-repo-is <url>` first" |
| User asks about code, not docs | Fetch the source file from `apps/` or `server/` and summarize its structure |
| Very large file (>1000 lines) | Fetch in 2 chunks (head + tail), note limitation, offer to fetch specific sections |
| Ambiguous target | Show numbered menu from Key Docs table, wait for user choice |

---

## Chaining

After output, always append a **"Go Deeper?"** suggestion with 2–3 natural next targets:

```
---
**Go deeper?** Try:
- `/deep-dive-doc {RelatedFile1}` — {one-line reason}
- `/deep-dive-doc {Concept}` — {one-line reason}
```

This encourages progressive exploration without overwhelming the user upfront.
