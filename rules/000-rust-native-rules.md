---
trigger: always_on
description: Rules for pure-Rust projects (lib, CLI, GUI) — rust-native branch
globs: **/*.rs, **/Cargo.toml, rustfmt.toml, clippy.toml
alwaysApply: true
---

# Rust Native Project Rules

**Chuẩn hoá mọi project thuần Rust (lib / CLI / GUI) theo chuẩn chính thức của Rust ecosystem.**

- **Điều cần triệt tiêu:** Code chưa qua `cargo fmt`/`cargo clippy`, naming tuỳ tiện, `unwrap()` trong lib code, error type bằng `String`, `println!` thay cho logging.
- **Lý do loại bỏ:** Panic ở production, API lệch chuẩn ecosystem khó dùng/khó review, style không nhất quán giữa các contributor (người + agent).
- **Tools/Scripts hỗ trợ/đi kèm:**
  - `cargo fmt`: formatter chính thức, enforce Rust Style Guide theo `style_edition`
  - `cargo clippy`: linter chính thức (~800 lints), config tập trung qua `[lints]` trong `Cargo.toml`

## 1) General Rules

- ĐỌC: [General rules for all projects](mdc:./000-general-rules.mdc)
- Áp dụng cho TẤT CẢ project Rust của tôi. KHÔNG CÓ NGOẠI LỆ NÀO ĐƯỢC PHÉP.

## 2) Standards Reference — "PSR/PEP của Rust"

Rust KHÔNG có bộ chuẩn đánh số duy nhất. Chuẩn chính thức gồm 4 nguồn, thứ tự tra cứu khi mâu thuẫn:

1. **Rust Style Guide** — formatting. KHÔNG tranh luận style bằng tay: `cargo fmt` là chân lý.
2. **Rust API Guidelines** (`rust-lang.github.io/api-guidelines`) — checklist `C-*`. BẮT BUỘC đối chiếu khi thiết kế public API của lib.
3. **RFC 430** — naming conventions (mục 4 dưới).
4. **Clippy** — máy móc hoá các idiom. Zero-warning policy khi commit.

## 3) Toolchain Setup (MUST)

- MUST có `rustfmt.toml` ở root — pin cả 2 giá trị, vì `rustfmt` chạy trực tiếp mặc định style 2015 còn `cargo fmt` suy từ `Cargo.toml` (không pin → 2 tool format lệch nhau):

  ```toml
  edition = "2024"
  style_edition = "2024"
  ```

- Lint config đặt TẬP TRUNG trong `Cargo.toml` qua `[lints]` / `[workspace.lints]` (Rust 1.74+). KHÔNG rải `#![allow(...)]` khắp source:

  ```toml
  [workspace.lints.clippy]
  correctness = { level = "deny", priority = -1 }
  suspicious  = { level = "warn", priority = -1 }
  complexity  = { level = "warn", priority = -1 }
  perf        = { level = "warn", priority = -1 }
  style       = { level = "warn", priority = -1 }
  # Restriction: CHỈ opt-in từng lint, KHÔNG BAO GIỜ enable cả nhóm
  unwrap_used  = "warn"
  dbg_macro    = "warn"
  print_stdout = "warn"
  todo         = "warn"
  # Team style: explicit `return` mọi nơi (mục 5) — override idiom mặc định
  implicit_return = "warn"
  needless_return = "allow"
  ```

- Sau mỗi thay đổi: `cargo fmt` + `cargo clippy -p <crate-đã-sửa> --all-targets` (chạy scoped, chỉ package thay đổi).
- Suppress lint phải kèm lý do: `#[allow(clippy::xxx, reason = "...")]` — và chỉ ở item-level, không crate-level.

## 4) Naming (RFC 430 / C-CASE)

| Item | Convention |
|---|---|
| Crates, modules, fn, methods, variables, macros | `snake_case` |
| Types, Traits, Enum variants | `UpperCamelCase` |
| `const`, `static` | `SCREAMING_SNAKE_CASE` |
| Lifetimes, generic params | ngắn, lowercase: `'a`, `T`, `E` |
| Cargo features | ngắn gọn, KHÔNG placeholder words (`use-abc` ❌ → `abc` ✅) (C-FEATURE) |

- Conversion methods theo C-CONV: `as_` (borrow, free) / `to_` (expensive) / `into_` (consume ownership).
- Getter KHÔNG prefix `get_`: `fn name(&self)` chứ không phải `fn get_name(&self)` (C-GETTER).

## 5) Code Style

- **Explicit return (team style)**: LUÔN viết `return expr;` tường minh ở MỌI exit point, kể cả tail expression.
    + Đi ngược idiom mặc định của ecosystem (implicit tail return) — lựa chọn có chủ đích: nhận diện exit point bằng mắt/syntax-highlight khi đọc code, nhất quán với các stack explicit-return khác (PHP/C#/TS).
    + Enforce bởi `implicit_return = "warn"` + `needless_return = "allow"` (mục 3). Auto-fix: `cargo clippy --fix`.
    + **LƯU Ý**: `?` operator vẫn là exit ẨN giữa hàm — chấp nhận, KHÔNG cấm `?`. Soi exit bằng IDE exit-point highlighting (mục 5.1).
    + Khi sửa code/crate ngoài repo (upstream PR, vendored code): giữ style của upstream, KHÔNG áp rule này.
- **Early return + `?`**: ưu tiên guard clause và `?` operator, không deep nesting.
- Mỗi function ≤ **40 dòng** (UI/declarative builder code được miễn, như các stack khác).
- **Error handling**:
    + Lib crate → typed errors với `thiserror`. App/bin crate → `anyhow` (hoặc `color-eyre`).
    + KHÔNG dùng `String`/`Box<dyn Error>` làm public error type của lib.
    + `unwrap()`/`expect()`: CẤM trong lib code. Bin code chỉ cho phép ở setup/main với `expect("context rõ ràng")`.
- **Docs**: `///` cho mọi public item; thêm sections `# Errors`, `# Panics`, `# Safety` khi applicable (C-FAILURE). Example trong doc dùng `?` thay vì `unwrap` (C-QUESTION-MARK).
- Implement/derive `Debug, Clone, PartialEq` cho public types khi hợp lý (C-COMMON-TRAITS).

### 5.1) Tìm exit point khi đọc code (IDE)

- **RustRover/IntelliJ**: đặt caret lên `fn`, `->`, `return` hoặc `?` → IDE highlight toàn bộ exit points của hàm.
- **VSCode/rust-analyzer**: tương tự, setting `rust-analyzer.highlightRelated.exitPoints.enable` (bật mặc định) — cursor trên `return`, `?`, `fn`, `->` sẽ highlight mọi điểm thoát, gồm cả `?`.

## 6) Project Layout

- Project > 1 concern → Cargo **workspace**: `crates/<name>/`, shared deps qua `[workspace.dependencies]`.
- App luôn tách **bin + lib**: toàn bộ logic trong lib, `main.rs` mỏng (parse args → gọi lib → map error sang exit code).
- CLI: dùng `clap` (derive API). GUI: stack (egui/iced/slint/tauri...) do rules riêng của từng project quyết định — đọc `000-*` của project đó.
- Kiểm tra dependency đã tồn tại trong `Cargo.toml` (root + members) trước khi đề xuất thêm crate mới.

## 7) Testing

- Unit tests: in-module `#[cfg(test)] mod tests` cùng file với code.
- Integration tests: thư mục `tests/` của crate.
- `cargo test --workspace` phải pass trước khi commit. Doc-tests tính là test.

## 8) Logging & Diagnostics

- Dùng `tracing` (hoặc `log` + facade) — KHÔNG `println!`/`eprintln!`/`dbg!` trong lib code (enforce bởi `print_stdout`, `dbg_macro` ở mục 3).
- Structured fields thay vì format string: `tracing::info!(task_id, "task started")`.
- KHÔNG log secrets/credentials/PII.

## 9) DO/DON'T Examples

```rust
// ✅ DO: typed error, `?`, early return, explicit return ở MỌI exit, doc với # Errors
use std::{fs, path::Path};

/// Loads the app config from a TOML file.
///
/// # Errors
/// Returns [`ConfigError`] when the file is unreadable, empty, or malformed.
pub fn load_config(path: &Path) -> Result<Config, ConfigError> {
    let raw = fs::read_to_string(path)?;
    if raw.trim().is_empty() {
        return Err(ConfigError::Empty); // early return
    }
    return toml::from_str(&raw).map_err(ConfigError::Parse); // explicit return cả ở tail
}

// ❌ DON'T: unwrap trong lib, String error, implicit tail return, get_ prefix
pub fn get_config(path: &str) -> Result<Config, String> {
    let raw = std::fs::read_to_string(path).unwrap();      // panic ở production
    let config = toml::from_str(&raw).map_err(|e| e.to_string())?; // stringly-typed
    Ok(config)                                              // thiếu `return` (clippy::implicit_return)
}
```

## 10) Definition of Done

- `cargo fmt --check` sạch; `cargo clippy --all-targets` zero warning.
- `cargo test --workspace` pass.
- Public API mới đã đối chiếu API Guidelines checklist; doc `///` đầy đủ.
- Plan doc trong `docs/agent-plans/` đã cập nhật nếu behavior non-trivial.
