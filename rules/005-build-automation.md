---
trigger: model_decision
description: Checklist bat buoc cho workflow ghi nguoc vao repo (changelog, version bump, codestyle autofix). Doc truoc khi tao/sua file trong .github/workflows/.
globs: .github/workflows/**
---

# 005 - Automation Workflow (GitHub Actions)

Rule áp dụng cho workflow **ghi ngược vào repo**: changelog, version bump, codestyle autofix, README version table, tracked build binaries.

**Reference**: `.agents/scripts/update-changelog.sh` + `build-release.yml`

## 1. Checklist — thiếu 1 dòng = không merge

| # | Yêu cầu | Mục |
|---|---------|-----|
| 1 | Bot commit chứa `[skip ci]` | §2 |
| 2 | Guard event không tự honor skip-ci (`release`, `schedule`, ...) | §2 |
| 3 | Run budget — không sinh commit rác khi source không đổi | §3 |
| 4 | CHANGELOG dùng marker block, update in-place | §4 |
| 5 | No-op guard — `git diff --cached --quiet` trước commit | §5 |
| 6 | `concurrency` group + push rebase/retry — **cấm `git push \|\| true`** | §6 |
| 7 | `permissions` tối thiểu, khai báo cấp job | §7 |

---

## 2. Skip-CI

**Bot commit**: luôn `[skip ci]` lowercase.

```bash
git commit -m "chore(changelog): update for ${ver} [skip ci]"
```

**GitHub chỉ tự skip cho `push` và `pull_request`.** Các event sau phải tự guard:
`release` · `workflow_dispatch` · `workflow_run` · `schedule` · `repository_dispatch`

**Guard expression** (event `push` only):

```yaml
# ✅ DO:
jobs:
  build:
    if: >-
      !contains(github.event.head_commit.message, 'skip ci') &&
      !contains(github.event.head_commit.message, 'skip-ci') &&
      !contains(github.event.head_commit.message, 'skip_ci')
```

**Guard job** (nhiều event) — xem §2 snippet dưới.

<details><summary>Guard job snippet (multi-event workflow)</summary>

```yaml
jobs:
  guard:
    runs-on: ubuntu-latest
    outputs:
      should_run: ${{ steps.check.outputs.should_run }}
    steps:
      - uses: actions/checkout@v5
        with: { fetch-depth: 1 }
      - id: check
        shell: bash
        env:
          ACTOR: ${{ github.actor }}
          PR_TITLE: ${{ github.event.pull_request.title }}
        run: |
          set -euo pipefail
          subject=$(git log -1 --pretty=%s)
          if printf '%s\n%s' "$subject" "${PR_TITLE:-}" \
              | grep -qiE '\[?((skip|no)[ _-]?ci|ci[ _-]?skip)\]?'; then
            echo "should_run=false" >> "$GITHUB_OUTPUT"; exit 0
          fi
          if [[ "$ACTOR" == "github-actions[bot]" ]]; then
            echo "should_run=false" >> "$GITHUB_OUTPUT"; exit 0
          fi
          echo "should_run=true" >> "$GITHUB_OUTPUT"

  build:
    needs: guard
    if: needs.guard.outputs.should_run == 'true'
```

</details>

---

## 3. Run budget — chống commit rác

Cây quyết định (dừng ở tier đầu tiên áp dụng được):

| Tier | Khi nào | Cách |
|------|---------|------|
| **0** | Job không cần chạy theo push | Đổi trigger sang `schedule` + `workflow_dispatch` |
| **1** | Job ghi file vào repo | Parse `lastRunAt` từ chính file/commit đó |
| **2** | Config, không phải state | `vars.*` (miễn phí, luôn có `\|\| 'default'`) |
| **3** | State = "source đã đổi chưa?" | `actions/cache` + `hashFiles()` |
| **4** | Không gì khác được | Actions Variables API — cần PAT/GitHub App |

<details><summary>Tier 1 — parse lastRunAt từ git</summary>

```bash
last_run=$(git log -1 --format=%cI --fixed-strings --grep='chore(duster)' || true)
if [[ -n "$last_run" ]]; then
  age_days=$(( ( $(date +%s) - $(date -d "$last_run" +%s) ) / 86400 ))
  (( age_days < ${THRESHOLD_DAYS:-7} )) && exit 0
fi
```

Bắt buộc `fetch-depth: 0` — depth=1 không thấy commit cũ.

</details>

<details><summary>Tier 3 — actions/cache + hashFiles</summary>

```yaml
- uses: actions/cache@v4
  id: build-stamp
  with:
    path: .build-stamp
    key: build-${{ hashFiles('scripts/portscan/**/*.go', 'scripts/portscan/go.sum') }}
- name: Build
  if: steps.build-stamp.outputs.cache-hit != 'true'
  run: go build -trimpath -ldflags="-s -w" -o portscan-linux-amd64 .
```

Limits: 7-day TTL, 10GB/repo, immutable key, scope theo branch.

</details>

<details><summary>Tier 4 — Variables API (cần PAT)</summary>

```bash
# GITHUB_TOKEN bị chặn cứng ở /actions/variables — cần fine-grained PAT
gh variable set LAST_RUN_AT --repo "$GITHUB_REPOSITORY" --body "$(date -u +%FT%TZ)"
```

</details>

**Cấm**: orphan branch làm store, artifact run trước làm state, gist/issue body, `GITHUB_ENV`/`GITHUB_STATE`.

---

## 4. Changelog — marker block + script

### 4.1 Output format

```markdown
# Changelog

<!-- DEV_CHANGELOG_START -->
## [dev-abc1234] - 2026-08-21

- feat: add ocop favorites (abc1234)
- fix: feedback sender polymorphism (9f31c02)
<!-- DEV_CHANGELOG_END -->

## [v1.2.0] - 2026-08-01
- feat: initial release
```

- **Dev push**: xoá dev block cũ → ghi block mới (commits từ last release tag đến HEAD)
- **Release**: xoá marker → dev content đóng băng thành release section

### 4.2 Commit filter — `shouldIncludeInLog`

```bash
# ✅ DO: filter theo subject trước khi format
shouldIncludeInLog() {
  [[ "$1" == Merge\ remote-tracking* ]] && return 1
  [[ "$1" == chore\(changelog\)* ]] && return 1
  return 0
}
```

```bash
# ❌ DON'T: grep -v trên dòng đã format — miss khi pattern nằm trong hash
echo "$raw_log" | grep -v "chore(changelog):"
```

### 4.3 Git log range

```bash
# Luôn dùng last release tag, không parse CHANGELOG, không dùng HEAD~N
base_ref=$(git tag --list --sort=-version:refname | grep -v "^dev-" | head -n1 || true)
```

### 4.4 No-op exit code

Script trả exit code `2` khi **log lines không đổi** (chỉ dev version hash khác).

```bash
# ✅ DO: handle exit 2 trong workflow
rc=0
bash .agents/scripts/update-changelog.sh "$ver" "$is_release" || rc=$?
[[ $rc -eq 2 ]] && exit 0   # content unchanged, skip commit
[[ $rc -ne 0 ]] && exit $rc  # real error
```

```bash
# ❌ DON'T: nuốt mọi exit code
bash scripts/update-changelog.sh "$ver" "$is_release" || true
```

### 4.5 Single-writer policy

**Chỉ `update-changelog.sh` được sửa content `CHANGELOG.md`.**

- Workflow `.yml`: không `sed`, `awk`, `echo >>` nhắm vào CHANGELOG. Chỉ `git add` + commit.
- Script khác: không mở ghi file này.
- Lý do: changelog là lịch sử — xoá nhầm không phục hồi được. Single-writer loại bỏ rủi ro.

### 4.6 Script distribution

Source of truth: **`.agents/scripts/update-changelog.sh`** (submodule `tansautn/zuko-ai-rules`).

```
.agents/scripts/update-changelog.sh   ← sửa ở đây
scripts/update-changelog.sh           ← stub: exec sang .agents/scripts/
```

**Trên CI — chọn 1 trong 2 cách:**

| Cách | Khi nào | Ưu | Nhược |
|------|---------|-----|-------|
| **A — Selective init** | Đã có `.agents` submodule | Version pin tự động theo submodule pointer | Thêm submodule mới phải sửa yml |
| **C — curl + pin SHA** | Không dùng submodule, hoặc cần audit trail rõ | Không cần init gì | Update SHA thủ công |

```yaml
# ✅ Cách A (mặc định):
- uses: actions/checkout@v4
  with:
    fetch-depth: 0
    submodules: false        # tránh fail private submodules
- run: git submodule update --init .agents

# ✅ Cách C:
- run: |
    curl -fsSL \
      "https://raw.githubusercontent.com/tansautn/zuko-ai-rules/${AGENTS_SCRIPT_SHA}/scripts/update-changelog.sh" \
      -o /tmp/update-changelog.sh
```

Sửa logic changelog → sửa ở `tansautn/zuko-ai-rules`, rồi `git submodule update --remote .agents`.

---

## 5. No-op guard

### Text file

```bash
git add -- CHANGELOG.md
git diff --cached --quiet && exit 0
git commit -m "chore(changelog): update for ${ver} [skip ci]"
```

### Binary (tracked bởi git)

Binary rebuild luôn khác byte dù source y hệt. Chọn 1:

- **(a) Reproducible build**: `SOURCE_DATE_EPOCH` + toolchain flags (`-trimpath`, `<Deterministic>true`)
- **(b) Source-hash stamp**: `git ls-files -s dir/ | git hash-object --stdin` → so sánh `.build-stamp`

---

## 6. Git push an toàn + concurrency

```yaml
concurrency:
  group: ${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: false   # false cho job ghi repo
```

```bash
# ✅ DO:
git config user.name  "github-actions[bot]"
git config user.email "41898282+github-actions[bot]@users.noreply.github.com"

for attempt in 1 2 3 4; do
  git pull --rebase --autostash origin "$GITHUB_REF_NAME" || true
  git push origin "HEAD:$GITHUB_REF_NAME" && break
  sleep $(( 2 ** attempt ))
done
```

```bash
# ❌ DON'T:
git push || true       # nuốt lỗi
git config user.name "GitHub Action"   # identity cũ, không gắn bot account
```

---

## 7. Permissions — tối thiểu, cấp job

```yaml
permissions:
  contents: read          # root

jobs:
  changelog:
    permissions:
      contents: write     # commit + push
      actions: write      # nếu cần xoá artifact
```

---

## 8. Version & artifact

- **Release**: tag name (`v1.0.0`). **Dev**: `dev-<short-sha>`.
- **Naming**: `{ProjectName}-{Version}.zip`
- **Dev artifacts**: giữ 3 bản gần nhất
- **Release artifacts**: xoá artifact sau khi upload lên Release
- **README version table** (release only): tối đa 8 dòng

---

## 9. Build snippet theo stack

<details><summary>Xem snippet</summary>

```yaml
# .NET
- uses: actions/setup-dotnet@v4
  with: { dotnet-version: '8.0.x' }
- run: dotnet publish [PROJECT_PATH] -c Release -o ./publish

# Node.js + pnpm + Tauri
- uses: pnpm/action-setup@v3
  with: { version: latest }
- uses: actions/setup-node@v4
  with: { node-version: 20, cache: 'pnpm' }
- uses: dtolnay/rust-toolchain@stable
- run: pnpm install --frozen-lockfile && pnpm run tauri:build:debug

# PHP / Laravel
- uses: shivammathur/setup-php@v2
  with: { php-version: '8.3' }
- run: composer install --no-interaction --no-progress --prefer-dist

# Python
- uses: actions/setup-python@v5
  with: { python-version: '3.12' }
- run: pip install -r requirements.txt
```

</details>

---

## 10. Customization khi bê sang project mới

| Thay gì | Ở đâu |
|---|---|
| `PROJECT_NAME` | `env:` đầu file |
| Build command | §9 |
| Output path | step `Collect bundle outputs` |
| Runner OS | `runs-on:` |
| Throttle window | `vars.<X>_THRESHOLD_DAYS` |
| Paths filter | `on.push.paths` — lớp throttle rẻ nhất |
