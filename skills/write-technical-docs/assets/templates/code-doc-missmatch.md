# Code ↔ Docs mismatch — sổ tập trung

***Danh sách các chỗ tài liệu cũ mô tả sai code thực tế, phát hiện khi viết tài liệu mới mà không được (hoặc chưa) sửa tài liệu gốc — một nơi duy nhất để chủ module xử lý.***

**Last updated:** <dán output của scripts/doc_stamp.py>

> [!NOTE]
> **Code là nguồn sự thật.** Mỗi dòng dưới đây là một mô tả lỗi thời trong tài liệu, kèm điều code thực sự làm.
> Sửa tài liệu gốc xong → đổi Trạng thái sang `ĐÃ SỬA` kèm commit, KHÔNG xoá dòng.

<!-- Vị trí cố định: docs/need-reviews/code-doc-missmatch.md tại repo root. -->

## Mục lục

- [1. Cách ghi](#1-cách-ghi)
- [2. <scope, vd modules/Billing>](#2-scope-vd-modulesbilling)

## 1. Cách ghi

- **Một dòng = một mô tả sai.** Ghi đúng mục (§) của tài liệu gốc để người sửa tìm nhanh.
- **Trạng thái:** `MỞ` (chưa sửa) → `ĐÃ SỬA` + link commit. Không xoá dòng.
- **Phát hiện ở:** tài liệu nào đã đối chiếu và ghi nhận điểm lệch.
- Tài liệu mới chỉ trỏ về file này, không lặp lại bảng.

## 2. <scope, vd modules/Billing>

- **Phát hiện ở:** [@<doc mới>.md](<relative/path>) (<yyyy-mm-dd>).

| # | Tài liệu (§) | Tài liệu nói | Code thực tế | Trạng thái |
|---|---|---|---|---|
| <X1> | [@<file>](<relative/path>) §<n> | <mô tả cũ> | <điều code làm — link file nếu được> | MỞ |
