---
name: write-technical-docs
description: Write, restructure or beautify technical docs (architecture overviews, protocol/contract specs, how-to guides, API references, docs indexes) in GitHub Flavored Markdown using per-type templates — abstract, Last updated stamp linked to the verified commit, ToC, mapping tables, GFM alerts — plus high-contrast color-coded Mermaid diagrams (graph, sequence, state) validated by rendering on Mermaid 10.x and 11.x. Use whenever the user asks to write or standardize docs, draw or colour Mermaid diagrams, document components/endpoints/lifecycles, write a worker/API contract or a how-to guide, log where old docs disagree with code, or says "viết tài liệu", "chuẩn hoá docs", "viết arch overview", "vẽ mermaid", "tô màu sơ đồ", "viết guide" — even if the skill is not named. For only re-syncing an existing doc with changed code, prefer docs-rematch.
---

# Write Technical Documentation (GFM Standard)

***Định chuẩn cách viết tài liệu kỹ thuật (Architecture, Module, Protocol, Guide, API) bằng GitHub Flavored Markdown, template theo từng loại, Mermaid màu tương phản theo ngữ nghĩa, và kiểm chứng bằng render thật.***

- **Điều cần triệt tiêu:** "wall-of-text", Markdown thuần thiếu điểm nhấn, thiếu mục lục, mô tả chay không sơ đồ/bảng,
  nhồi nội dung nâng cao vào luồng cơ bản, sơ đồ một màu hoặc màu na ná nhau, sơ đồ chỉ render thử trên một phiên bản Mermaid.
- **Lý do loại bỏ:** Giảm readability, khó tra cứu, tốn công maintain; sơ đồ vỡ ở máy người đọc thì không ai đọc.
- **Tools/Scripts đi kèm:**
  - [@scripts/validate_mermaid.py](scripts/validate_mermaid.py): render mọi block Mermaid trên **Mermaid 10.x và 11.x**, in `HINT` cho bẫy ký tự, xuất PNG sáng/tối.
  - [@scripts/check_links.py](scripts/check_links.py): link tương đối + anchor theo slug GitHub; cảnh báo link tới file chưa track / trong submodule.
  - [@scripts/doc_stamp.py](scripts/doc_stamp.py): sinh dòng `Last updated` có link click được tới commit đã đối chiếu.
  - [@references/mermaid-styling.md](references/mermaid-styling.md): bảng màu, công thức từng loại sơ đồ, bảng ký tự đặc biệt, pitfalls.
  - [@assets/templates/](assets/templates/): template cho từng loại tài liệu.

## 1. GFM Standards & Formatting (BẮT BUỘC)

- **Chuẩn Markdown:** PHẢI dùng **GitHub Flavored Markdown** (https://github.github.com/gfm).
- **Last updated:** BẮT BUỘC, ngay dưới abstract. Tài liệu lỗi thời còn tệ hơn không có tài liệu.
  - Sinh bằng `doc_stamp.py --paths <code mà tài liệu mô tả>` — không gõ tay.
  - Commit ghi trong dòng là **HEAD lúc viết** = code đã đối chiếu. Khi tài liệu được commit, đó chính là commit ngay trước commit của tài liệu.
  - Link tới commit trên remote (GitHub/GitLab/Bitbucket) để click được; script tự dựng URL từ `origin`.
  - Code đang có thay đổi chưa commit trong `--paths` → script tự nối `+ chưa commit: …` để người đọc biết tài liệu mô tả cả phần đó.
- **Table of Contents:** BẮT BUỘC, ngay trước `## 1. ...`. Anchor theo slug GitHub — kiểm bằng `check_links.py`.
- **Alert blocks:** `> [!NOTE]`, `> [!TIP]`, `> [!IMPORTANT]`, `> [!WARNING]`, `> [!CAUTION]`.
  - Marker PHẢI đứng **một mình trên dòng đầu**, nội dung ở các dòng `>` tiếp theo — viết chung dòng thì GitHub không render.
- **Collapsible content:** ví dụ nâng cao, cấu hình phụ, logic không cốt lõi → `<details><summary>…</summary>`.

### 1.1. Structural Requirements

- **Phần đầu chung — MỌI loại tài liệu:**
  1. **H1** + 1 câu tổng quan `***bold-italic***`.
  2. **Last updated** (output của `doc_stamp.py`).
  3. **Một alert** chứa điều quan trọng nhất PHẢI nắm trước khi đọc tiếp.
  4. **Legend màu** — chỉ khi tài liệu có graph/sequence dùng > 3 nhóm màu.
  5. **Mục lục.**
- **Thân tài liệu theo loại** — copy template tương ứng, xoá mục tuỳ chọn không dùng:

| Loại | Template | Trả lời câu hỏi | Mục BẮT BUỘC | Mục tuỳ chọn |
|---|---|---|---|---|
| Index (`README.md`) | [@readme.md](assets/templates/readme.md) | Đọc gì, theo thứ tự nào? | Bảng đọc theo thứ tự, tra cứu nhanh | Tài liệu khác, cần review. **Không sơ đồ, không legend** |
| Architecture | [@architecture-overview.md](assets/templates/architecture-overview.md) | Gồm những gì, nối nhau thế nào? | Components + mapping, luồng dữ liệu, lifecycle | Thuật ngữ; endpoints (BẮT BUỘC khi có HTTP/CLI/queue surface); vận hành |
| Protocol / contract | [@protocol.md](assets/templates/protocol.md) | Wire format, timing, lỗi, retry? | Tương tác, schema, semantics, timing, delivery, retry | Bảo mật, naming |
| Guide (`guides/how-to-*.md`) | [@guide.md](assets/templates/guide.md) | Làm từng bước thế nào? | Điều kiện tiên quyết, các bước (mục tiêu → làm → kiểm tra), checklist | DO/DON'T, khắc phục sự cố |
| API reference | [@api-reference.md](assets/templates/api-reference.md) | Request/response cụ thể? | Chung (base URL, auth, envelope), từng endpoint | Bảng lỗi |
| Sổ lệch code ↔ docs | [@code-doc-missmatch.md](assets/templates/code-doc-missmatch.md) | Tài liệu cũ nào sai so với code? | Cách ghi, bảng theo scope | — |

- **Một tài liệu = một câu hỏi.** Chủ đề lớn → tách thành bộ, `README.md` làm index. Nội dung đã có ở file khác → link, KHÔNG chép lại.

### 1.2. Quy ước link

- **File/code:** `[@filename](relative/path)` — đường dẫn **tính từ file tài liệu**, không phải repo root.
- **Một mục của tài liệu khác:** `[@file.md §4](file.md#4-tên-mục)`. **Thư mục:** `[@app/Services/](../app/Services/)`.
- **KHÔNG tạo link tới:**
  - file chưa được git track (link chạy ở local nhưng gãy trên remote);
  - file nằm trong git submodule (vd `.agents/rules/…`) — repo cha trên GitHub không mở được.
  - Hai trường hợp này viết bằng code span: `` `.agents/rules/002-repository-pattern.md` ``. `check_links.py` cảnh báo cả hai.

### 1.3. Tài liệu cũ lệch code

- **Ghi tập trung vào `docs/need-reviews/code-doc-missmatch.md` (repo root)** — template [@code-doc-missmatch.md](assets/templates/code-doc-missmatch.md).
  - Tạo file nếu chưa có. Thêm dòng vào đúng scope (`modules/<Name>`, root…), Trạng thái `MỞ`.
  - Trong tài liệu đang viết chỉ để 1 dòng link về sổ — KHÔNG lặp bảng.
  - Được phép sửa tài liệu gốc → sửa luôn, rồi ghi dòng với Trạng thái `ĐÃ SỬA` + commit.
- Lý do: điểm lệch rải rác trong nhiều tài liệu thì không ai xử lý; một sổ duy nhất thì chủ module duyệt một lần.

## 2. Formatting & Structure Guidelines

- **Structure:**
  - Heading cho đề mục (H2~H5).
  - **Ý chính in đậm (Bold)**
    - Ý phụ thụt lề,
      xuống dòng nếu chi tiết quá dài (max paragraph = 50).
- **Content:**
  - **Vào đề trực tiếp.** Bắt đầu bằng overview cốt lõi.
  - Ngắn gọn, dễ hành động (actionable).
  - UPPERCASE cho thuộc tính quan trọng. _Italic_ cho hành động nên làm, suggestion.
    **BOLD, UPPERCASE** cho hành động cần review lại, cần phối hợp.
- **Từ khoá mức độ — tài liệu tiếng Việt dùng tiếng Việt:**
  - `PHẢI`, `BẮT BUỘC`, `LUÔN`, `KHÔNG ĐƯỢC`, `KHÔNG` — thay cho `MUST`, `REQUIRED`, `ALWAYS`, `MUST NOT`.
  - Tài liệu viết bằng tiếng Anh giữ `MUST`/`REQUIRED`. Technical terms (job, payload, endpoint, queue…) giữ tiếng Anh.
- **Marker phối hợp** (BOLD UPPERCASE, kèm 1 câu lý do):
  - `**CẦN FIX:**` lỗi đã xác minh trong code. `**CẦN REVIEW:**` thiết kế đáng xem lại.
  - `**CẦN PHỐI HỢP:**` cần thống nhất giữa các bên. `**CẦN XÁC NHẬN:**` chưa kiểm chứng được.
  - Gom mọi marker vào một bảng "Điểm cần xử lý" cuối tài liệu (Marker → Vấn đề → link mục chi tiết).
  - Lỗi được fix → gỡ marker ở các tài liệu được phép sửa, cập nhật `Last updated`.
- **DRY:** cross-reference rules/file khác thay vì viết lại nội dung.

## 3. DO/DON'T Examples

````markdown
// ✅ DO: GFM Alerts, Details block và Table rõ ràng
> [!IMPORTANT]
> Payload PHẢI tuân thủ schema JSON trước khi dispatch.

<details><summary>Advanced — Setup Watchdog Cronjob</summary>

```bash
* * * * * cd /path-to-your-project && php artisan schedule:run >> /dev/null 2>&1
```
</details>

| Component | File | Vai trò |
|---|---|---|
| **Dispatcher** | [@JobDispatcher.php](app/JobDispatcher.php) | Entry point tạo Job |

// ❌ DON'T: viết chay, không dùng cấu trúc GFM
Lưu ý quan trọng là payload phải chuẩn JSON.
Dispatcher nằm ở file app/JobDispatcher.php có vai trò tạo job.

// ❌ DON'T: alert viết chung dòng — GitHub không render
> [!NOTE] Payload phải chuẩn JSON.

// ❌ DON'T: link vào submodule / file chưa track — gãy trên GitHub
Xem [@002-repository-pattern.md](../../../.agents/rules/002-repository-pattern.md)
````

## 4. Mermaid Standard Guidelines

- **PHẢI đọc [@references/mermaid-styling.md](references/mermaid-styling.md) trước khi vẽ.** Tóm tắt:
- **Chọn loại sơ đồ theo câu hỏi:**
  - Architecture/Components → `graph TB` / `graph TD`, gom cụm bằng `subgraph` có id.
  - Luồng theo thời gian → `sequenceDiagram` + `autonumber`; `box` nhóm service, `rect` nhóm phase.
  - Trạng thái của một entity → `stateDiagram-v2`.
- _Ghi chú luồng:_ LUÔN có label trên mũi tên hoặc `autonumber`.
- **Màu — không giới hạn số nhóm, chỉ đòi hỏi độ tương phản:**
  - Một khái niệm (vai trò hoặc luồng) = một nhóm màu, nhất quán trong toàn tài liệu.
  - Lấy nhóm theo thứ tự trong bảng màu (các nhóm đầu cách xa nhau nhất). KHÔNG dùng hai sắc độ "anh em" (blue/indigo, green/teal…) trong cùng sơ đồ.
  - Hết nhóm → tái dùng nhóm + đổi kiểu viền/hình, ghi vào legend.
  - Màu cạnh = khái niệm sở hữu luồng; một màu dùng cho cả node và cạnh PHẢI cùng một khái niệm.
  - LUÔN set `color:` (màu chữ) tường minh; vùng nhạt hơn node một bậc.
- **Legend:** > 3 nhóm màu → một bảng ở đầu tài liệu. State diagram có dòng chú thích riêng ngay dưới sơ đồ.
- **Độ phức tạp:** graph > ~12 node / ~15 cạnh, sequence > ~8 participant → tách sơ đồ.

### 4.1. Những quy tắc hay vỡ nhất

- **Ký tự đặc biệt** — bảng đầy đủ, đã kiểm chứng trên Mermaid 10.x + 11.x: [§8 reference](references/mermaid-styling.md#8-ký-tự-đặc-biệt).
  - Flowchart: text node có `( ) [ ] { }` PHẢI quote `A["call (x)"]`; KHÔNG dùng node id `end`.
  - State: label/description KHÔNG có dấu `:` thứ hai (vỡ trên 10.x) → `#58;`; tên state KHÔNG chứa `-`.
  - Sequence: KHÔNG có `;` trong message/Note → `#59;`.
  - Cẩn thận với `:` `()` `-` `><` `[]` ở mọi loại sơ đồ — khi nghi ngờ, quote hoặc dùng entity.
- **`linkStyle` đếm cạnh từ 0 theo thứ tự khai báo.** Mỗi cạnh một dòng, comment chỉ số; KHÔNG dùng `A --> B --> C` hay `A & B --> C`.
- **Sequence: `box` alpha 0.05, `rect` alpha 0.16** — `box` đậm làm `rect` đục.

## 5. Workflow viết tài liệu

1. **Đọc trước khi viết — không đoán.** Routes, controllers, services, models, migrations, config, commands, tests.
   - Hành vi không chắc → xác minh tại runtime, **chỉ bằng lệnh đọc**:
     `route:list`, `schedule:list`, `tinker` chỉ đọc `config(...)`, `git log/status/show`, `redis-cli` lệnh đọc, test Unit thuần.
   - KHÔNG chạy: `migrate`, `db:seed`, `queue:work`, lệnh ghi Redis/DB, test Feature dùng DB — trừ khi đã đọc `phpunit.xml`
     và chắc chắn test trỏ DB riêng. Lệnh nào nghi ngờ → hỏi trước.
   - Docs cũ mâu thuẫn code → code thắng; ghi vào sổ lệch ([§1.3](#13-tài-liệu-cũ-lệch-code)).
2. **Chọn loại tài liệu + template** theo [§1.1](#11-structural-requirements). Viết plan ngắn nếu dự án yêu cầu doc-first.
3. **Viết** theo template; link theo [§1.2](#12-quy-ước-link).
4. **Vẽ sơ đồ** theo [@references/mermaid-styling.md](references/mermaid-styling.md); thêm legend khi cần.
5. **Đóng dấu:** dán output của

```bash
python <skill-dir>/scripts/doc_stamp.py --paths <code paths tài liệu mô tả>
```

6. **Kiểm chứng — BẮT BUỘC trước khi báo xong:**

```bash
python <skill-dir>/scripts/check_links.py <docs-dir>
```

```bash
python <skill-dir>/scripts/validate_mermaid.py <docs-dir> --png <scratch>/mermaid-png --dark
```

   - `validate_mermaid.py` mặc định render trên mermaid-cli 10.9.1 + 11.4.2. FAIL ở bất kỳ phiên bản nào = phải sửa.
   - Mở PNG sáng + tối, soát: chữ đọc được, màu các nhóm phân biệt rõ, cạnh đúng màu luồng, không tràn chữ.
   - Không render được (thiếu Node/browser) → báo rõ "chưa render được", KHÔNG khẳng định sơ đồ hợp lệ.
7. **Bảo trì:** code đổi hoặc lỗi được fix → sửa mọi chỗ được phép sửa, cập nhật `Last updated`, cập nhật sổ lệch.
   Xem thêm skill `docs-rematch`.
