---
alwaysApply: true
---
## 🧠 Agent LLM Rules for Laravel + Filament Modular Project

### 1. General Rules

* ĐỌC : [General rules for all project](mdc:./000-general-rules.mdc)
* Áp dụng cho tất cả project của tôi. KHÔNG CÓ NGOẠI LỆ NÀO ĐƯỢC PHÉP

### 2. Architecture & Structure

* 🧱 Dự án Laravel 12, **modular structure** với:

  * `nwidart/laravel-modules` – tách biệt domain logic.
  * `filament/filament` – Admin CP
  * `bezhansalleh/filament-shield` – Role/Permission
* 👇 **Mỗi module** phải:

  * Có file `composer.json`
  * Có `Providers`, `Routes`, `Events`, `Models`, `Policies`, `Docs`, `Tests`, v.v...
  * **Không dùng Facade ngoài `AppServiceProvider` nếu không cần thiết**
* 📁 Tên thư mục lowercase\_snake\_case, class PascalCase, function camelCase
* Thông thường môi trường phát triển không nằm ở local hoặc chỉ có sourcecode mà không có kết nối DB.
    + Bỏ qua các bước như run migration hay exec DB schema update
    + Nếu cần đối chiếu dữ liệu thực tế: 
      SCHEMA: xem Model ứng với table cần tra cứu
      DATA: yêu cầu người dùng cung cấp
---

### 3. Implement Guide.

- Tuân theo các nguyên tắc, triết lý thiết kế tôi đã áp dụng ở các dự án PHP để đồng nhất về cấu trúc, dễ hiểu khi đọc
- Các triết lý, cách kiến tạo cấu trúc là các rules có prefix number: `002`.
- List dưới đây có thể không đầy đủ nhưng là những rule bắt buộc đọc và áp dụng:
    + `002-repository-pattern.mdc` or `002-repository-pattern.md`
    + `002-lazy-dependencies-injection-pattern.mdc` or `002-lazy-dependencies-injection-pattern.md`
    + `002-repository-pattern.mdc` or `002-repository-pattern.md`

---


### 4. Code Style Guidelines

* 🧪 **Testing-first** nếu logic >= 3 bước xử lý
* 🛠️ Tuân theo PSR:

  * PSR-4: autoloading
  * PSR-12: code style
* 🧠 Mỗi method không vượt quá **40 dòng**
* 🔍 Sử dụng **type hint**, **dependency injection**, không viết code hard-coupled
* 🚫 Không log thông tin nhạy cảm. Không commit credentials.
* Nếu project có linter, fixer riêng đi kèm. Sử dụng chúng mỗi khi thay đổi nội trên 1 file (run only files which changed)


---

### 5. Filament Admin Rules

* Tạo Resource thông qua command hoặc `miguilim/filament-auto-panel`
* Field validation, authorization policy tách riêng – không nhét trong Resource class
* Không override default view trừ khi thực sự cần thiết
