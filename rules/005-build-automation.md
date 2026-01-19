---
trigger: manual
---

# GitHub Workflow Template Instructions

## Yêu cầu chung
Tạo GitHub workflow thực hiện build project và upload artifact với các tính năng:

### 1. Trigger Events
- **Push to master branch**: Build và tạo dev artifact
- **Release published**: Build và tạo release artifact

### 2. Version Management
- **Release**: Sử dụng tag name từ release (vd: `v1.0.0`)
- **Commit**: Sử dụng short hash với prefix `dev-` (vd: `dev-abc1234`)

### 3. Artifact Management
- **Dev artifacts**: Giữ tối đa 3 artifacts gần nhất, tự động xóa cũ
- **Release artifacts**: Xóa ngay sau khi upload thành công
- **Naming**: `{ProjectName}-{Version}.zip`

### 4. Documentation Updates
- **CHANGELOG.md**: 
  - Tự động cập nhật từ git log commits
  - Parse từ last tag đến HEAD (hoặc toàn bộ nếu chưa có tag)
  - Format: `## [Version] - Date` với danh sách commits
- **README.md** (chỉ cho release):
  - Cập nhật version table
  - Giữ tối đa 8 phiên bản gần nhất
  - Format: `| Version | Date | Notes |`

### 5. Build Configuration
**Cần tùy chỉnh theo project type:**

#### .NET Projects
```yaml
- name: Setup .NET
  uses: actions/setup-dotnet@v4
  with:
    dotnet-version: '8.0.x'

- name: Build
  run: dotnet build --configuration Release

- name: Publish
  run: dotnet publish [PROJECT_PATH] --configuration Release --output ./publish
```

#### Node.js Projects
```yaml
- name: Setup Node.js
  uses: actions/setup-node@v4
  with:
    node-version: '18'

- name: Install dependencies
  run: npm install

- name: Build
  run: npm run build
```

#### Python Projects
```yaml
- name: Setup Python
  uses: actions/setup-python@v4
  with:
    python-version: '3.11'

- name: Install dependencies
  run: pip install -r requirements.txt

- name: Build
  run: python setup.py build
```

### 6. Customization Points
Khi áp dụng cho project mới, cần thay đổi:
- **Project name**: Thay `PasteHelper` bằng tên project
- **Build commands**: Theo ngôn ngữ/framework
- **Output path**: Đường dẫn build output
- **File extensions**: `.zip`, `.tar.gz`, etc.
- **Runner OS**: `windows-latest`, `ubuntu-latest`, `macos-latest`

### 7. Required Permissions  
Đảm bảo workflow có quyền:
```yaml
permissions:
  contents: write
  actions: write
```

### 8. Git Configuration
Workflow tự động commit changes với:
- Email: `action@github.com`
- Name: `GitHub Action`
- Skip CI: `[skip ci]` trong commit message

### 9. Error Handling
- Try-catch cho API calls
- Fallback cho missing files
- Graceful handling khi không có previous tags

### 10. Environment Variables
Sử dụng các built-in variables:
- `${{ github.event_name }}`
- `${{ github.event.release.tag_name }}`
- `${{ github.repository }}`
- `${{ secrets.GITHUB_TOKEN }}`

## Template sử dụng
Copy workflow template và customize theo project requirements. Đặt file tại `.github/workflows/build-release.yml`.