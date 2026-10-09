# <Module> API Reference

***<Một câu: tham chiếu request/response cho các endpoint của <Module>.>***

**Last updated:** <dán output của scripts/doc_stamp.py --paths modules/<Module>/routes modules/<Module>/app/Http>

> [!NOTE]
> **<Điều bên gọi hay sai nhất: auth, envelope, rate limit…>**

- **Component sau mỗi endpoint:** [@architecture-overview.md §3](architecture-overview.md#3-endpoints--component).

## Mục lục

- [1. Chung](#1-chung)
- [2. <Nhóm endpoint A>](#2-nhóm-endpoint-a)

## 1. Chung

| Mục | Giá trị |
|---|---|
| Base URL | `/api/<prefix>` |
| Auth | <none / Bearer Sanctum / role> |
| Envelope | `{ "ok": bool, "error": {code, message} \| null, "data": …, "message": string }` |
| Rate limit | <throttle> |

## 2. <Nhóm endpoint A>

### 2.1. `<METHOD> <path>`

- **Caller:** <ai gọi>. **Auth:** <…>. **Mô tả:** <1 câu>.

| Field | Type | BẮT BUỘC | Ghi chú |
|---|---|---|---|
| `<field>` | <type> | Có / Không | <ràng buộc> |

<details><summary>Request / response mẫu</summary>

```json
{ "<field>": "<value>" }
```

```json
{ "ok": true, "error": null, "data": {}, "message": "ok" }
```

</details>

| HTTP | Khi nào | Client làm gì |
|---|---|---|
| `422` | <validation> | Sửa request, không retry |
| `<code>` | <điều kiện> | <hành động> |
