---
trigger: always
---

## 🧠 Agent LLM Rules for Zuko's Projects

### 1. Tone and Style

* ❗ **No preamble or postamble**: Trả lời trực tiếp, không giới thiệu thừa hoặc kết luận trừ khi được yêu cầu.
* ✍️ **Language**:

    * Code, class, method, variable: **English only**. Đại loại là chỉ sử dụng tiếng Anh trong bất kỳ code nào.
    * Response/explanation: Cho phép dùng **Tiếng Việt** khi cần diễn giải kỹ thuật.
* 📦 **Minimal output tokens**: Trả lời ngắn gọn, đúng trọng tâm.

---

### 2. Documentation & Workflow – Document First

* 🧾 Mọi thay đổi phải bắt đầu bằng tài liệu (doc-first), gồm:

    * **Diễn giải mục tiêu** (requirement/why),
    * **Kế hoạch thực hiện (step-by-step)**,
    * **Mermaid diagrams** nếu logic phức tạp hoặc liên quan đến nhiều modules.
* 👁️ Chế độ làm việc là Agent, Developer Co-Operative. Luôn luôn ĐỌC LẠI NỘI DUNG file trước khi sửa đổi
* 📂 Đặt tài liệu tại thư mục `docs/agent-plans/` trong module tương ứng nếu có.
* 🔁 Mọi chức năng (Feature, Event, Listener, UI, Policy, v.v...) **phải** có sơ đồ/phác thảo trước khi code.
* ✅ Dùng những thứ sẵn có, hoặc tạo lớp base khi có thể để giảm boilerplate.
* ✅ Nếu dự án hiện tại đã có graph-index được cung cấp bởi `codebase-memory-mcp`. Ưu tiên sử dụng MCP thay vì grep hay fuzy search
* ✅ BẮT BUỘC: TUÂN THEO RULES RIÊNG CỦA TỪNG PROJECT. Nó luôn nằm cùng thư mục chứa file md này.
     Scan và đọc các file này để hiểu rules riêng của project. Các file bắt đầu bằng `000-` là must read before write anything.
     TUÂN THỦ NGHIÊM NGẶT THEO CÁC RULES NÀY. KHÔNG CÓ NGOẠI LỆ NÀO ĐƯỢC PHÉP !
---

### 6. LLM Behavior Guide

#### Allowed

* ✅ Đề xuất refactor nếu code trùng lặp
* ✅ Tự động tạo docs/mermaid nếu thấy thiếu
* ✅ Gợi ý test nếu chưa có

#### Not Allowed

* ❌ Không generate code nếu chưa có tài liệu sơ bộ
* ❌ Không merge logic controller với logic service
* ❌ Không tạo file ngoài cấu trúc module quy định

---

### 7. Agent Tool Usage

#### Package usage
* Kiểm tra sự tồn tại của packages trước khi gợi ý dùng package mới.
* Không assume thư viện tồn tại — kiểm tra `<root project>/composer.json` trước, và cả các file `composer.json` trong các module.
  Depending on language, it's could be: packages.json, pixi.toml, cargo.toml, <name>.csproject,...

#### Intergrating Packages to Project
* Luôn luôn kiểm tra  tài liệu của package đang intergrate, Mỗi developer có một hướng thiết kế khác nhau
* Để tra cứu tài liệu, sử dụng `context7` MCP. Nói chung khi nghĩ về tài liệu (đọc) hãy nhớ `context7`

#### Git
* Git: Project always have untracked files, and i want it remain untracked. Only `git add` what you created or changed.
  Nothing else. `git add .` is fobidden.
* Workflow automation (CI-CD): Khi viết workflow config. 
  Matching rules luôn luôn phải bỏ qua commit/release/pull (đại loại subject type) có chứa "skip ci", "skip-ci", "skip_ci". 
  Không phân biệt hoa/thường