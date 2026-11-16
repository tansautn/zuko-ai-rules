---
description: SDD (Spec-Kit) prompt journal — persist every agent-generated /speckit.* prompt into specs/<NNN>/prompts/ for observability, replay and audit
globs: specs/**/*, .specify/**/*
alwaysApply: true
---

# SDD Prompt Journal (Spec-Kit)

**Mọi prompt agent tạo ra để chạy `/speckit.*` PHẢI được lưu thành file journal trong `prompts/` của feature tương ứng — user quan sát được, replay được, audit được chuỗi instruction → spec.**

- **Điều cần triệt tiêu:** Chạy `/speckit.*` với prompt "tàng hình" chỉ tồn tại trong chat session; spec files có version nhưng prompt sinh ra chúng thì bay hơi.
- **Lý do loại bỏ:** Spec sai không truy vết được agent đã breakdown instruction thành gì; không reproduce/diff được giữa các lần chạy; user mất khả năng review trước-trong-sau.

## 1) Context & Vai trò

- User đưa **instruction mức cao**. AGENT breakdown instruction thành chuỗi `/speckit.*` commands (`constitution` → `specify` → `clarify` → `plan` → `tasks` → `analyze` → `implement`).
- Artifact cần journal là **prompt agent đã soạn và đưa vào command** — instruction gốc của user được nhúng verbatim kèm theo trong cùng file.

## 2) Vị trí & Naming (MUST)

- **Monorepo (umbrella + sub-repos)?** → vị trí tuân theo [001-sdd-monorepo-flow](mdc:./001-sdd-monorepo-flow.md): MỌI journal đặt ở **umbrella**, kể cả khi prompt sinh code cho sub-repo; sub-repo KHÔNG BAO GIỜ chứa `prompts/`. Format/naming/index vẫn là rule này.
- Feature-scoped commands → `specs/<NNN-slug>/prompts/`, mỗi invocation 1 file.
- **Project-wide specs** (`constitution`, specs không thuộc feature nào, cross-feature) → gộp vào MỘT file duy nhất: `docs/prompts/spec-project-wide.md`, mỗi invocation là 1 entry APPEND vào cuối (format ở mục 4.1).
- Filename (feature-scoped): `<command>.<yyyymmdd>_<short_title>.md`
    + `<command>`: tên command BỎ prefix `speckit.` → `specify`, `clarify`, `plan`, `tasks`, `analyze`, `implement`, `checklist`
    + `<short_title>`: snake_case, tóm tắt nội dung prompt (không phải tên feature)
    + Ex: `specs/001-hls-proxy/prompts/specify.20261113_initial_requirements.md`
- Feature-scoped: mỗi invocation = 1 file; trùng tên trong ngày → hậu tố `_2`, `_3`. Project-wide: mỗi invocation = 1 entry trong file chung.

## 3) Workflow

### 3.1) Trước khi invoke command (journal-before-run)

1. Soạn prompt từ instruction của user.
2. Ghi file journal theo template (mục 4) với `status: pending` — TRƯỚC khi invoke.
    + **Ngoại lệ duy nhất — `specify` tạo feature mới**: `specs/<NNN-slug>/` chưa tồn tại (speckit tạo khi chạy, kèm số NNN). → Invoke xong, ghi journal NGAY LẬP TỨC vào dir vừa được tạo, trước mọi bước khác.
3. Output path của file journal trong response — user mở xem song song được. Đây là tính "quan sát được".
4. Invoke `/speckit.<command>` với NGUYÊN VĂN nội dung `Generated Prompt` đã lưu.
    + **Prompt chạy ≠ prompt lưu là VI PHẠM.** Muốn sửa prompt → sửa file journal trước, rồi chạy lại.

### 3.2) Sau khi command hoàn tất

1. Cập nhật file journal: `status: done | failed`, điền section `## Outcome` (artifacts created/modified, notes).
2. Append 1 row vào `prompts/index.md` (mục 5).
3. `git add` từng file journal + spec files nó sinh ra. KHÔNG `git add .` (theo [000-general-rules](mdc:./000-general-rules.mdc)).

## 4) Prompt Journal Template

**Fence discipline (REQUIRED)**: khối bọc ngoài dùng **4 backticks**, khối bên trong dùng **3 backticks**. KHÔNG lồng 3-tick trong 3-tick — editor/linter sẽ bắt format nhầm. Nếu `Generated Prompt` tự chứa code fence 3-tick → nâng fence bọc nó lên 4-tick.

````markdown
---
command: /speckit.plan
feature: 001-hls-proxy
date: 2026-11-13
agent: claude-code
status: pending
---

# plan — edge cache design

## User Instruction (verbatim)

```text
<nguyên văn instruction user đưa, không chỉnh sửa, không tóm tắt>
```

## Generated Prompt (verbatim — fed to command)

```text
<nguyên văn prompt agent đưa vào /speckit.plan>
```

## Outcome

- Status: <done | failed>
- Artifacts: <specs/001-hls-proxy/plan.md (created), ...>
- Notes: <ngắn gọn, optional>
````

### 4.1) Entry format cho `docs/prompts/spec-project-wide.md`

- Cùng nội dung template trên nhưng BỎ frontmatter (file chung không có frontmatter per-entry); thay bằng heading entry, append vào cuối file:

````markdown
## [2026-11-13] constitution — initial project principles

- **Command**: /speckit.constitution · **Status**: done

### User Instruction (verbatim)

```text
<nguyên văn>
```

### Generated Prompt (verbatim — fed to command)

```text
<nguyên văn>
```

### Outcome

- Artifacts: .specify/memory/constitution.md (created)
````

- File này tự nó là chronological log → KHÔNG cần index riêng. KHÔNG sửa entry cũ trừ cột Status của chính entry đó.

## 5) Index — Observability per Feature

- `specs/<NNN-slug>/prompts/index.md` là **nguồn truth về trình tự chạy thực tế** (chronological, giống vai trò `tasks-index.md` trong [001-tasks-workflow](mdc:./001-tasks-workflow.mdc)):

````markdown
# Prompt Journal — 001-hls-proxy

| # | Date | Command | File | Status |
|---|------|---------|------|--------|
| 1 | 2026-11-13 | specify | [specify.20261113_initial_requirements.md](./specify.20261113_initial_requirements.md) | done |
| 2 | 2026-11-13 | plan | [plan.20261113_edge_cache_design.md](./plan.20261113_edge_cache_design.md) | done |
````

- Append 1 row mỗi invocation, kể cả `failed` (failed cũng là lịch sử cần audit).
- KHÔNG sửa row cũ trừ cập nhật cột Status của chính invocation đó.

## 6) DO/DON'T Examples

```bash
# ✅ DO: journal trước → announce path → chạy nguyên văn → update index
write   specs/002-auth/prompts/plan.20261113_jwt_rotation.md   # status: pending
say     "Journal: specs/002-auth/prompts/plan.20261113_jwt_rotation.md"
run     /speckit.plan "<đúng nguyên văn Generated Prompt trong file trên>"
update  journal (status: done, Outcome) + prompts/index.md

# ❌ DON'T: chạy với prompt chỉ tồn tại trong chat — mất truy vết
run     /speckit.plan "ad-hoc prompt..."

# ❌ DON'T: lưu bản "đã làm đẹp" khác với bản thực tế đã chạy
# ❌ DON'T: gộp nhiều invocations vào 1 file journal
```
