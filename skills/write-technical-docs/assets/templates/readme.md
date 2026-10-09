# <Module> — Docs

***<Một câu: module này là gì và bộ tài liệu này giúp ai làm gì.>***

**Last updated:** <dán output của scripts/doc_stamp.py>

> [!NOTE]
> **<Định vị module trong 1–2 câu: vai trò trong hệ thống, điều người đọc dễ hiểu sai nhất.>**

<!--
README = trang index. KHÔNG cần sơ đồ, KHÔNG cần legend màu.
Mọi nội dung chi tiết nằm ở tài liệu con — README chỉ trỏ tới.
-->

## Mục lục

- [1. Đọc theo thứ tự](#1-đọc-theo-thứ-tự)
- [2. Tra cứu nhanh](#2-tra-cứu-nhanh)
- [3. Tài liệu khác](#3-tài-liệu-khác)
- [4. Cần review](#4-cần-review)

## 1. Đọc theo thứ tự

| # | Tài liệu | Dành cho | Trả lời câu hỏi |
|---|---|---|---|
| 1 | [@architecture-overview.md](architecture-overview.md) | Mọi người | Gồm những gì, nối với nhau thế nào? |
| 2 | [@<x>-protocol.md](<x>-protocol.md) | Bên tích hợp | Wire format, timing, lỗi, retry? |
| 3 | [@guides/how-to-<task>.md](guides/how-to-<task>.md) | Dev | Làm <task> từng bước thế nào? |
| 4 | [@api-endpoints.md](api-endpoints.md) | Dev | Request / response cụ thể? |

## 2. Tra cứu nhanh

| Cần | Xem |
|---|---|
| <Câu hỏi thường gặp 1> | [@<file>.md §<n>](<file>.md#<anchor>) |
| <Câu hỏi thường gặp 2> | [@<file>.md §<n>](<file>.md#<anchor>) |

## 3. Tài liệu khác

- **Plans:** `agent-plans/<yyyymmdd>_<slug>.md`.
- **Agent guidance:** [@CLAUDE.md](../CLAUDE.md) (module).
- <Tài liệu cũ còn giá trị — link + 1 câu khi nào đọc.>

## 4. Cần review

- Điểm lệch giữa tài liệu cũ và code: `docs/need-reviews/code-doc-missmatch.md` (repo root) — link tương đối từ file này.
- <Các marker **CẦN …** quan trọng nhất của module, mỗi dòng trỏ tới mục chi tiết.>
