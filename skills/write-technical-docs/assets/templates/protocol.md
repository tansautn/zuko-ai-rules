# <Hệ thống> Protocol — Contract <A> ↔ <B> (v<N>)

***<Một câu: bên tích hợp chỉ cần tuân thủ tài liệu này là chạy được.>***

**Last updated:** <dán output của scripts/doc_stamp.py --paths <code paths>>

> [!IMPORTANT]
> **Contract frozen v<N>.** Đổi tên / kiểu field PHẢI phối hợp với mọi implementation phía <B>.

- **Bối cảnh component & lifecycle:** [@architecture-overview.md](architecture-overview.md).
- **Ví dụ request/response đầy đủ:** [@api-endpoints.md](api-endpoints.md).

## Mục lục

- [1. Tổng quan tương tác](#1-tổng-quan-tương-tác)
- [2. Định danh & naming](#2-định-danh--naming)
- [3. Message schema](#3-message-schema)
- [4. HTTP semantics](#4-http-semantics)
- [5. Timing & ngưỡng](#5-timing--ngưỡng)
- [6. Delivery semantics](#6-delivery-semantics)
- [7. Retry policy](#7-retry-policy)
- [8. Bảo mật](#8-bảo-mật)

## 1. Tổng quan tương tác

| # | Ai | Kênh | Hành động | Khi nào |
|---|---|---|---|---|
| 1 | <A> | HTTP | `POST <path>` | <thời điểm> |
| 2 | <B> | <Queue/PubSub> | `<op> <key>` | <thời điểm> |

## 2. Định danh & naming

| Tên logic | Nguồn (config / code) | Tên thật trên hạ tầng |
|---|---|---|
| `<logical key>` | [@<File>](<path>) | `<prefix + key>` |

- **Xác minh trên môi trường thật** (chỉ lệnh đọc):

```bash
<lệnh đọc config / liệt kê key>
```

## 3. Message schema

| Field | Type | BẮT BUỘC | Mô tả |
|---|---|---|---|
| `<field>` | <type> | Có / Không | <1 câu> |

```json
{ "<field>": "<example>" }
```

- **Quy tắc:** <bỏ qua field lạ / giữ nguyên chuỗi raw / …>

## 4. HTTP semantics

### 4.1. `<METHOD> <path>`

| Field | Type | BẮT BUỘC | Ghi chú |
|---|---|---|---|
| `<field>` | <type> | Có | <ràng buộc> |

- **Thành công:** <hiệu ứng>. **Lỗi:** <mã → ý nghĩa → client làm gì>.

## 5. Timing & ngưỡng

| Ngưỡng | Giá trị | Nguồn | Quy tắc cho client |
|---|---|---|---|
| <tên> | <giá trị> | `<config / command>` | <client PHẢI làm gì> |

## 6. Delivery semantics

- **Thứ tự:** <FIFO / LIFO — push/pop đầu nào>.
- **Số lần giao:** <at-least-once / at-most-once> — <nguồn gây giao lặp>.
- **Idempotency:** <client _nên_ làm gì>.

## 7. Retry policy

| Tình huống | Hành động |
|---|---|
| Network error / 5xx | <backoff> |
| `429` | Chờ `Retry-After` |
| `422` | Bug client — KHÔNG retry |

## 8. Bảo mật

- <Auth model, tầng mạng, dữ liệu nhạy cảm KHÔNG được log.>
