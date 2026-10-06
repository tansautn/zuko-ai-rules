---
description: Standardize the creation and maintenance Agent rule files
trigger: manual
globs: .agents/rules/*.md, .agents/rules/*.mdc
---


# Agent Rule Standardization
**Chuẩn hoá và tối ưu format AGENT Rules. File này hướng dẫn cách viết Rule một cách tối ưu nhất**.

- **Điều cần triệt tiêu:** Viết rule tự do, paragraph dài dòng, thiếu ví dụ thực tế, lặp lại logic (Non-DRY).
- **Lý do loại bỏ:** Lãng phí token, LLM parse sai context, giảm độ chính xác khi apply rule vào code.


### 1. Frontmatter Structure (Required)

```markdown
---
description: Clear, 1-line description of enforcement
globs: path/**/*.ext, other/path/*
alwaysApply: boolean
---

# [Rule Title]

**Mục tiêu cốt lõi của Rule (Mô tả ngắn nhất có thể về "Quy tắc này giúp đạt được điều gì")**

- **Điều cần triệt tiêu:** [Chi tiết các anti-patterns/lỗi cần loại bỏ]
- **Lý do loại bỏ:** [Hậu quả/Tác động tiêu cực nếu giữ lại]
- **Tools/Scripts hỗ trợ/đi kèm:**
  - `[Tool/Script 1]`: [1 dòng mô tả ngắn cách hoạt động]
  - `[Tool/Script 2]`: [1 dòng mô tả ngắn cách hoạt động]
```
### 2. Formatting & Structure Guidelines
- **Structure:** 
- Sử dụng Heading cho các đề mục (H2~H5)
  - **Ý chính in đậm (Bold)**
    - Y phụ thụt lề 
      xuống dòng nếu chi tiết quá dài (max paragraph = 50)
- **Content:** 
  - **Vào đề trực tiếp**.
  - Bắt đầu bằng overview cốt lõi. 
  - Giữ tiêu chí ngắn gọn, dễ hành động (actionable).
  - Sử dụng UPPERCASE cho các thuộc tính quan trọng như : required, must, do.
    _Italic_ cho các hành động nên làm, suggestion.
    **BOLD, UPPERCASE** cho các hành động cần được review lại, cần sự phối hợp.
- **DRY Principle:** Cross-reference rules/file khác thay vì viết lại nội dung. 
    Chia nhỏ nội dung theo Category. Đừng gộp chúng vào một file duy nhất.

### 3. File & Code References/Routing
  - **Syntax chuẩn:** `[@filename](path/to/file)` OR `[@relative-path-to-file](path/to/file)`.
  - **Ưu tiên thực tế:** Luôn trỏ link về actual code/file thay vì ví dụ giả định.
  - Ví dụ reference rule: [@rule-template.md](.agents/rules/rule-template.md).

### 4. DO/DON'T Examples (REQUIRED)
- Use language-specific code blocks. Must include both DO and DON'T.
```typescript
// ✅ DO: Show good examples/patterns
const goodExample = true;

// ❌ DON'T: Show anti-patterns
const badExample = false;
```

### 5. Maintaining, Updating rule files
- **Update:** Cập nhật patterns mới, loại bỏ patterns lỗi thời.
- **Enrich:** Liên tục bổ sung ví dụ từ actual codebase.
- **Link:** Duy trì links chéo giữa các rules liên quan.
