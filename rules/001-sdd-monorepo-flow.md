---
description: SDD trong monorepo (umbrella + sub-repos) — spec artifacts sống DUY NHẤT ở umbrella; checkbox tick gắn chặt với submodule pin bump trong cùng một commit
globs: specs/**/*, .specify/**/*, .gitmodules
alwaysApply: true
---

# SDD Monorepo Flow (Umbrella-first)

**Sub-repo chứa code. Umbrella chứa sự thật.**

- **Điều cần triệt tiêu:** Code đã land ở sub-repo nhưng `tasks.md` ở umbrella đứng im `0/N` — hoặc tệ hơn: checkbox được tick trên code chưa push/chưa pin.
- **Lý do loại bỏ:** Trạng thái SDD phải audit được từ MỘT chỗ; submodule pin SHA là bằng chứng công việc tồn tại. Checkbox không gắn pin = tự kể chuyện cổ tích cho chính mình.

## 1) Phạm vi & Routing

- **ÁP DỤNG** khi repo hiện tại là **umbrella**: deployables tách thành sub-repos, mount làm git submodules (nhận diện: `.gitmodules` trỏ các repo con tại `shared/`, `services/*`, `edge/*`, …).
- Repo đơn (không có topology trên) → rule này KHÔNG áp dụng; mọi thứ theo [001-sdd-prompt-journal](mdc:./001-sdd-prompt-journal.md) nguyên bản.
- Đang đứng trong **sub-repo** mà cần động tới spec/tasks/journal → ĐI LÊN umbrella mà làm; sub-repo không phải chỗ của chúng (mục 2).

## 2) Artifact placement (MUST)

| Artifact | Umbrella | Sub-repo |
|---|---|---|
| `.specify/` (constitution, templates, scripts) | ✅ | ❌ |
| `specs/<NNN>/` (spec, plan, tasks, research, contracts, **prompts/**) | ✅ | ❌ |
| `docs/agent-plans/` (session plans) | ✅ | ❌ |
| `docs/prompts/spec-project-wide.md` | ✅ | ❌ |
| Code, tests, migrations | ❌ | ✅ |
| `CLAUDE.md` + mirrors + `.agents` | ✅ (scope umbrella) | ✅ (scope riêng) |

Journaling `/speckit.*` vẫn theo [001-sdd-prompt-journal](mdc:./001-sdd-prompt-journal.md) về format/naming/index — nhưng **mọi journal đặt ở umbrella**, kể cả khi prompt sinh code cho một sub-repo.

## 3) Task tick ⇔ pin bump (MUST)

Flow chuẩn cho MỖI task:

1. Code land ở **sub-repo**: commit + push tại đó trước.
2. **MỘT commit umbrella** làm đồng thời: bump submodule pin của sub-repo đó **VÀ** tick checkbox trong `specs/<NNN>/tasks.md` (+ 1 dòng *Done <date> — <SHA/repo>* note).
3. **Checked ⇔ pinned & pushed.** Không bao giờ tick trên work chưa commit/chưa push.
4. Dở dang → checkbox GIỮ NGUYÊN unchecked + dated ***Partial*** note mô tả phần đã land / phần còn thiếu.
5. Checkpoint gates trong tasks.md = umbrella commits.

## 4) DO/DON'T

```bash
# ✅ DO: sub-repo trước, umbrella chốt sau — một commit vừa pin vừa tick
(cd edge/worker && git add src/routes/playlist.ts && git commit -m 'feat: playlist route (T017)' && git push)
git add edge/worker specs/001-x/tasks.md
git commit -m 'chore(sdd): T017 done — pin edge/worker@<sha>'

# ❌ DON'T: tick checkbox mà không bump pin (checkbox nói dối)
git add specs/001-x/tasks.md && git commit -m 'tick T017'

# ❌ DON'T: specs/ hay prompts/ mọc trong sub-repo
edge/worker/specs/...          ← sai chỗ; đi lên umbrella
edge/worker/prompts/plan.*.md  ← sai chỗ; umbrella specs/<NNN>/prompts/

# ❌ DON'T: tick trên code local chưa push — pin SHA phải fetch được từ remote
```

## 5) Cross-references

- Journal format/naming/index: [001-sdd-prompt-journal](mdc:./001-sdd-prompt-journal.md)
- CLAUDE.md canonical + mirrors per scope: [003-claude-md-canonical](mdc:./003-claude-md-canonical.md)
- `.agents` submodule + excludes per repo: [020-submodule-setup](mdc:./020-submodule-setup.md)
- Git staging: không `git add .` — theo [000-general-rules](mdc:./000-general-rules.mdc)
