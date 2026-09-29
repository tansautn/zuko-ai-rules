---
trigger: manual
globs: .agents/rules/*.mdc
---

- **Required Rule Structure:**

  ```markdown
  ---
  description: 1-line enforcement description
  globs: path/to/files/*.ext, other/path/**/*
  alwaysApply: boolean
  ---

  # [Title Rule] - [Mục tiêu cốt lõi của rule]

  - **Mô tả (Core Objectives):**
    - **Cần triệt tiêu:** [Điều/Pattern cần loại bỏ]
    - **Lý do:** [Tại sao cần loại bỏ/Hậu quả]
    - **Tools/Scripts:**
      - `[Tool 1]`: [1 dòng ngắn gọn mô tả cách hoạt động]
      - `[Tool 2]`: [1 dòng ngắn gọn mô tả cách hoạt động]

  - **Main Points in Bold**
    - Sub-points with details
  ```

- **Formatting & References:**
  - **File Links:** Use `[filename](mdc:path/to/file)` (e.g., `[schema.prisma](mdc:prisma/schema.prisma)`).
  - **Code Blocks:** Language-specific. Must include `// ✅ DO:` (good patterns) and `// ❌ DON'T:` (anti-patterns).
  - **Style:** Bullet points, concise phrasing, consistent formatting.

- **Content & Best Practices:**
  - **Actionable:** Focus on specific, implementable requirements.
  - **Contextual:** Prefer actual codebase examples over theoretical ones.
  - **DRY:** Cross-reference existing rules to avoid duplication.

- **Maintenance:**
  - Continually update with new patterns.
  - Add fresh examples from the live codebase.
  - Remove outdated anti-patterns.
