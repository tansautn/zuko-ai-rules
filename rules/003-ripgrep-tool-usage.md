---
trigger: model_decision
description: Prefer ripgrep (rg) over grep for all fuzzy/content search. Includes cross-platform install guide.
globs: "**/*"
alwaysApply: true
---

# 003 - Ripgrep (`rg`) over `grep`

**Mọi trường hợp cần fuzzy search hoặc content search, PHẢI dùng `rg` thay cho `grep`.**

`rg` nhanh hơn, tôn trọng `.gitignore`, output rõ ràng hơn, và cross-platform.

---

## Quy tắc

1. **KHÔNG dùng `grep`** cho code search — luôn dùng `rg`
2. **KHÔNG dùng `grep -r`** — `rg` recursive mặc định
3. Nếu `rg` chưa có → cài trước khi dùng (xem §Install)
4. Agent có Grep tool riêng (ripgrep-backed) → ưu tiên tool đó, chỉ fallback Bash + `rg` khi cần pipe/transform

## Cheat sheet

| Task | `rg` | ~~grep~~ |
|------|------|----------|
| Search text | `rg "pattern"` | ~~`grep -r "pattern" .`~~ |
| Case insensitive | `rg -i "pattern"` | ~~`grep -ri "pattern" .`~~ |
| File type filter | `rg -t py "pattern"` | ~~`grep -r --include="*.py"`~~ |
| Glob filter | `rg -g "*.ts" "pattern"` | ~~`grep -r --include="*.ts"`~~ |
| Files only | `rg -l "pattern"` | ~~`grep -rl "pattern" .`~~ |
| Count matches | `rg -c "pattern"` | ~~`grep -rc "pattern" .`~~ |
| Context lines | `rg -C3 "pattern"` | ~~`grep -C3 "pattern"`~~ |
| Fixed string | `rg -F "literal.text"` | ~~`grep -F "literal.text"`~~ |
| Invert match | `rg -v "pattern"` | ~~`grep -v "pattern"`~~ |
| Multiline | `rg -U "start.*\nend"` | ~~`grep -Pz` (not portable)~~ |

### Hữu ích

```bash
# Tìm function definition
rg "def |function |fn " -t py -t js -t rust

# Tìm TODO/FIXME
rg "TODO|FIXME|HACK" --glob '!node_modules'

# Tìm và replace (preview)
rg "old_name" -l | xargs sed -i 's/old_name/new_name/g'

# JSON field search
rg '"syncId"' -t json
```

---

## Install — khi `rg` missing

### Detect + auto-install

```bash
ensure_rg() {
    command -v rg &>/dev/null && return 0

    local bin_dir="$HOME/.local/.bin"
    # Check if already downloaded
    if [[ -x "$bin_dir/rg" ]]; then
        export PATH="$bin_dir:$PATH"
        return 0
    fi

    echo "[INFO] ripgrep (rg) not found. Installing to $bin_dir ..."
    mkdir -p "$bin_dir"

    local os arch url
    case "$(uname -s)" in
        Linux*)  os="unknown-linux-musl" ;;
        Darwin*) os="apple-darwin" ;;
        MINGW*|MSYS*|CYGWIN*) os="pc-windows-msvc" ;;
        *) echo "[ERROR] Unsupported OS: $(uname -s)"; return 1 ;;
    esac

    case "$(uname -m)" in
        x86_64|amd64) arch="x86_64" ;;
        aarch64|arm64) arch="aarch64" ;;
        *) echo "[ERROR] Unsupported arch: $(uname -m)"; return 1 ;;
    esac

    local version
    version=$(curl -sfL "https://api.github.com/repos/BurntSushi/ripgrep/releases/latest" \
        | grep '"tag_name"' | head -1 | sed 's/.*"tag_name": *"//;s/".*//')

    local base="ripgrep-${version}-${arch}-${os}"
    if [[ "$os" == "pc-windows-msvc" ]]; then
        url="https://github.com/BurntSushi/ripgrep/releases/download/${version}/${base}.zip"
        local tmp_dir
        tmp_dir=$(mktemp -d)
        curl -sfL "$url" -o "$tmp_dir/rg.zip"
        unzip -q -o "$tmp_dir/rg.zip" -d "$tmp_dir"
        cp "$tmp_dir/${base}/rg.exe" "$bin_dir/rg.exe"
        rm -rf "$tmp_dir"
    else
        url="https://github.com/BurntSushi/ripgrep/releases/download/${version}/${base}.tar.gz"
        curl -sfL "$url" | tar -xz --strip-components=1 -C "$bin_dir" "${base}/rg"
    fi

    chmod +x "$bin_dir/rg" 2>/dev/null || true
    export PATH="$bin_dir:$PATH"

    if command -v rg &>/dev/null; then
        echo "[OK] ripgrep $(rg --version | head -1) installed to $bin_dir"
    else
        echo "[ERROR] Install failed. Manual: https://github.com/BurntSushi/ripgrep/releases"
        return 1
    fi
}
```

### Platform-specific alternatives

| Platform | Command |
|----------|---------|
| **macOS** | `brew install ripgrep` |
| **Ubuntu/Debian** | `sudo apt install ripgrep` |
| **Arch** | `sudo pacman -S ripgrep` |
| **Windows (winget)** | `winget install BurntSushi.ripgrep.MSVC` |
| **Windows (scoop)** | `scoop install ripgrep` |
| **Windows (choco)** | `choco install ripgrep` |
| **Cargo** | `cargo install ripgrep` |

### PATH persistence

Nếu không có quyền sửa PATH system-wide:

```bash
# Thêm vào shell profile (1 lần)
echo 'export PATH="$HOME/.local/.bin:$PATH"' >> ~/.bashrc

# Hoặc export cho session hiện tại
export PATH="$HOME/.local/.bin:$PATH"
```

---

## DON'T

```bash
# ❌ grep -r trong codebase
grep -r "TODO" src/

# ❌ grep pipe chain khi rg có flag sẵn
grep -r "pattern" . | grep -v node_modules | grep "\.ts:"

# ❌ find + grep combo
find . -name "*.py" -exec grep -l "import" {} \;
```

## DO

```bash
# ✅ rg tự skip .gitignore
rg "TODO" src/

# ✅ rg glob + type filter
rg "pattern" -t ts --glob '!node_modules'

# ✅ rg thay find+grep
rg -l "import" -t py
```
