---
name: what-this-repo-is
description: >
  Analyze and summarize any code repository by fetching its README, extracting documentation links,
  crawling the docs/ folder, and producing a structured Markdown overview. Use this skill whenever
  the user shares a GitHub URL, asks "what is this repo?", "explain this project", "summarize this
  codebase", "what does this library do?", or pastes any repository link and wants to understand it.
  Also trigger when the user says things like "give me an overview of X repo", "what tech does this
  use?", or "tóm tắt repo này". Always use this skill — even for short or casually phrased requests
  — when a repository URL is involved.
---

# What-This-Repo-Is Skill

Fetch and synthesize repository documentation into a structured Markdown summary.

## Trigger

Any message containing a GitHub (or similar) repo URL plus intent to understand the project.
Examples: "what is this?", "explain this repo", "tóm tắt repo này", "summarize", or simply pasting a URL.

---

## Workflow

### Step 1 — Fetch README (weight: 10)

Fetch the repo's main page or raw README. GitHub repos:
- Try `https://github.com/<owner>/<repo>` (main page contains README inline)
- Fallback raw URL: `https://raw.githubusercontent.com/<owner>/<repo>/main/README.md`
  (or `master` branch if `main` fails)

Extract from README:
- Project name, one-line description
- Core features / capabilities list
- Tech stack mentions (languages, frameworks, libraries)
- Architecture overview if present
- Install / quickstart instructions
- All **outbound doc links** (relative paths like `docs/X.md`, `roadmap.md`, etc.) → collect for Step 2

> If the user provides a non-GitHub URL or a direct documentation URL, fetch it directly and treat
> it as the primary source (weight 10). Ask the user if the URL fails or returns no useful content.

---

### Step 2 — Follow README doc links (weight: 2)

From links collected in Step 1, select up to **5 most relevant** (prioritize: architecture, tech
stack, getting started, API reference). Fetch each and extract **compacted** content only:
- Section headings
- Key bullet points or tables
- No raw code blocks (summarize what they do instead)

Weight = 2 means: these are supplementary; include if they add distinct info not in README.
Skip if a link 404s or produces no text content.

---

### Step 3 — Scan docs/ folder (weight: 10)

Try to list the `docs/` directory. GitHub approach:
```
https://github.com/<owner>/<repo>/tree/main/docs
```
If robots.txt blocks tree view, enumerate files by trying common doc filenames based on README
mentions, or fetch the main repo page and parse the file tree listing.

For each doc file found, fetch its **compacted** content:
- Max ~300 words per file
- Extract: purpose, key concepts, notable config/options, caveats
- Prefer files named: architecture, tech-stack, getting-started, api, configuration, modules

Weight = 10 means: docs/ content is high-priority — treat it on par with README itself.

**"Usable docs"** = at least one text doc file (`.md`, `.mdx`, `.rst`, `.txt`, `.adoc`, `.org`, `.html`).
A `docs/` holding only assets (images, GIFs, videos, `CNAME`, config) does NOT count — e.g.
`janestreet/magic-trace` has `docs/assets/*.gif` only, while its real documentation lives in the wiki.
If there's no usable docs, go to Step 3b.

---

### Step 3b — Wiki fallback (weight: 10, replaces docs/)

Run when Step 3 found no `docs/` folder or `docs/` has no text files. Many projects (especially older
or ops/tooling repos) keep their real docs in the GitHub Wiki instead of the tree, so skipping it
produces a thin summary built from README alone.

1. **Detect the wiki.** Fetch `https://github.com/<owner>/<repo>/wiki`.
   - Wiki exists → page shows a "Home" page and a "Pages N" sidebar listing page titles/links.
   - No wiki → GitHub redirects back to the repo root (or 404). Also a hint: the repo nav has no
     "Wiki" tab. In that case note "No docs/ or wiki found" and continue to Step 4.
   - README often links to the wiki directly ("More documentation on the wiki") — treat that as a
     strong signal and use those links first.
2. **Build the page list** from the Home page body + the "Pages" sidebar. The sidebar may truncate
   ("Show N more pages…"); the Home page usually has a curated index, so prefer its structure.
3. **Pick up to ~6 pages**, prioritizing (same spirit as docs/):
   supported platforms / requirements → architecture / codebase tour → getting started / install →
   configuration / modes / options → FAQ / caveats. Skip testimonials, prior art, reading lists,
   changelogs unless nothing else exists.
4. **Fetch in parallel**, compacted exactly like docs/ files (max ~300 words each; purpose, key
   concepts, notable flags/options, caveats). Wiki page URLs follow
   `https://github.com/<owner>/<repo>/wiki/<Page-Title-With-Dashes>`.
5. **Label the source as Wiki** in the output (Docs Overview table + Key Links) so the reader knows
   where the info came from.

If BOTH a usable `docs/` and a wiki exist, docs/ stays primary; use the wiki only to fill gaps (weight 2).

---

### Step 4 — Synthesize & Output

Combine all extracted information into the Markdown template below. Apply judgment:
- Don't repeat the same fact twice
- Higher-weight sources override lower-weight ones on conflicts
- Fill in "Unknown" or omit sections cleanly when data is absent

**CRITICAL — "What It Does" is the primary deliverable of this skill.**

The single most important question to answer is: **"What does this repo actually DO?"**
Before writing anything else, answer these three questions using all fetched content:

1. **Who is it for?** (developers, sysadmins, end users, a specific domain?)
2. **What problem does it solve?** (what pain, manual task, or gap does it eliminate?)
3. **How does it solve it?** (the mechanism — not the tech stack, but the *user-facing workflow*)

The "What It Does" section must:
- Be **4–7 sentences**, not 1–2
- Lead with the **user problem**, not the implementation
- Describe the **end-to-end workflow** a user would experience
- Mention **what would happen without it** (the alternative: doing it manually, using inferior tools)
- Be understandable by someone who has never seen the repo

All other sections (tech stack, features table, docs map) are supplementary context.
If time is limited, write "What It Does" fully first, then fill others as available.

---

## Output Template

```markdown
# 📦 {Repo Name}

> {One-sentence description from README}

**Repo:** {URL} · **License:** {license} · **Latest:** {version if found}

---

## 🔍 What It Does

{2–4 sentence plain-English explanation of the project's purpose and main value proposition.}

---

## ✨ Core Features

| Feature | Description |
|---------|-------------|
| {name} | {one-line description} |
| ... | ... |

---

## 🏗️ Architecture & Tech Stack

**Languages:** {list}
**Frameworks / Libraries:** {list}
**Build / Tooling:** {list}
**Storage / Data:** {list}

{1–2 sentence architecture summary if available.}

---

## 🚀 Getting Started

```
{minimal install/run commands from README or getting-started doc}
```

{Any notable prerequisites.}

---

## 📁 Docs Overview

{Source: `docs/` or `Wiki` (state which). Table of key doc files / wiki pages and what each covers.}

| File / Page | Covers |
|-------------|--------|
| `docs/X.md` or Wiki: *Page Title* | ... |

---

## 🗺️ Roadmap / Status

{Key completed milestones and upcoming items, if roadmap.md or similar was found. Keep compact.}

---

## 🔗 Key Links

- README: {url}
- Docs: {docs/ url} · Wiki: {wiki url, if used}
- {Other notable links from README}

---

*Summary generated by what-this-repo-is skill. Accuracy depends on publicly available documentation.*
```

---

## Edge Cases

| Situation | Handling |
|-----------|----------|
| Private repo / 404 | Inform user; ask them to paste README text directly |
| No docs/ folder | Go to Step 3b (wiki fallback) |
| docs/ has only assets (images/GIFs, no text docs) | Treat as no docs → Step 3b (wiki fallback) |
| No docs/ and no wiki | Note "No docs/ or wiki found"; rely on README + linked docs |
| Wiki sidebar truncated ("Show N more pages…") | Use the Home page index; fetch README-linked wiki pages first |
| Non-GitHub repo (GitLab, Bitbucket, raw URL) | Adapt URLs accordingly; fetch what's accessible |
| Very large README (>5000 words) | Summarize sections rather than reading exhaustively |
| No README at all | Ask user to provide a documentation URL |
| robots.txt blocks tree view | Enumerate files based on README-mentioned paths instead |

---

## Notes

- Always use `web_fetch` — do not use `web_search` for repo content unless looking up context about technologies mentioned.
- Fetch docs/ files (or wiki pages) in parallel where possible (multiple `web_fetch` calls).
- Keep the output under ~800 words — this is a **summary**, not a mirror of the docs.
- If the user asks for deeper detail on a specific section, fetch that doc file on demand.
