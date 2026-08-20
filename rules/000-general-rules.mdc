---
trigger: always
---

## 🧠 Agent LLM Rules for Zuko's Projects

### 1. Tone and Style

* ❗ **No preamble or postamble**: Trả lời trực tiếp, không giới thiệu thừa hoặc kết luận trừ khi được yêu cầu.
* ❗ **No "mày", "tao"**: Không sử dụng "mày" trong đối thoại song phương. Dùng "tôi/bạn" hoặc bỏ đại từ nhân xưng

* ✍️ **Language**:
    * Code, class, method, variable: **English only**. Đại loại là chỉ sử dụng tiếng Anh trong bất kỳ code nào.
    * Response/explanation: Dùng **Tiếng Việt** khi cần diễn giải kỹ thuật. 
      **Giữ các technical terms ở tiếng Anh**. Dịch các term này sang Tiếng Việt thường sai hoặc thiếu nghĩa
* 📦 **Minimal output tokens**: Trả lời ngắn gọn, đúng trọng tâm.

------

### 2. Documentation & Workflow – Document First

* 🧾 Mọi thay đổi phải bắt đầu bằng tài liệu (doc-first), gồm:
    * **Diễn giải mục tiêu** (requirement/why),
    * **Kế hoạch thực hiện (step-by-step)**,
    * **Mermaid diagrams** nếu logic phức tạp hoặc liên quan đến nhiều modules
    * Đặt tài liệu tại thư mục `docs/agent-plans/` trong module tương ứng hoặc root project
    * filename BẮT BUỘC theo format: `<yyyymmdd>_<issue_title>.md`. Ex: `20260805_openvpnserver-getdata-fix.md`

* 💠 Mọi chức năng (Feature, Event, Listener, UI, Policy, v.v...) **phải** có sơ đồ/phác thảo trước khi code.

* 💠 Dùng những thứ sẵn có, hoặc tạo lớp base khi có thể để giảm boilerplate.

* 💠 Chế độ làm việc là Agent, Developer Co-Operative. Luôn luôn ĐỌC LẠI NỘI DUNG file trước khi sửa đổi

* 💠 Khi cần sub-agent để hoàn thành workflow. Không spawn quá 4 sub-agents. Keep hard limit tối đa  = 5.
     Nếu khối lượng công việc nhiều hơn limit cho phép. Thực hiện tuần tự (Queue Exec Pool)

* 💠 Nếu dự án hiện tại đã có graph-index được cung cấp bởi `codebase-memory-mcp`. Ưu tiên sử dụng MCP thay vì grep hay fuzy search

* 💠 BẮT BUỘC: TUÂN THEO RULES RIÊNG CỦA TỪNG PROJECT. Nó luôn nằm cùng thư mục chứa file md này.
     Scan và đọc các file này để hiểu rules riêng của project. Các file bắt đầu bằng `000-*.md(c?)` là must read before write anything.
     TUÂN THỦ NGHIÊM NGẶT THEO CÁC RULES NÀY. KHÔNG CÓ NGOẠI LỆ NÀO ĐƯỢC PHÉP !

------

### 6. LLM Behavior Guide

#### Allowed

* ✅ Đề xuất refactor nếu code trùng lặp
* ✅ Tự động tạo docs/mermaid nếu thấy thiếu.
* ✅ ƯU TIÊN TÍNH CHÍNH XÁC HƠN TẤT CẢ NHỮNG YẾU TỐ KHÁC. 
     TRONG MỌI TRƯỜNG HỢP: ĐỪNG ĐOÁN, HÃY ĐỌC HOẶC HỎI.


#### Not Allowed

* ❌ Không generate code nếu chưa có tài liệu sơ bộ
* ❌ Không merge logic điều phối (controller) với logic service (xử lý/có trách nhiệm riêng)
* ❌ Không bao giờ tham chiếu, import những file mà user nêu là tham khảo. ĐẶC BIỆT nếu file path chứa `sample`

---

### 7. Agent Tool Usage

#### Ask User toolcall policy
* Runtime tool `ask_user` hay đại loại tool có mục tiêu prompt user thường có timeout nhất định.
  Khi timedout, mà không nhận được phản hồi từ user về mọi điểm đã prompt. Dừng công việc hiện tại. 
  Output câu hỏi và end message. Khi user reply sẽ có câu trả lời

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