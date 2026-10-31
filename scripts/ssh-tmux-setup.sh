#!/bin/bash
# SSH key + agent setup for remote-tmux-ssh-link skill
#
# Generates a no-passphrase ed25519 key, detects the correct SSH binary and agent,
# loads the key, and outputs structured blocks the calling agent can parse.
#
# Usage:
#   ./scripts/ssh-tmux-setup.sh [--host <hostname>] [--workspace <dir>]
#
# Outputs (structured, parseable):
#   ==== BEGIN SSH_BINARY ====
#   /path/to/ssh
#   ==== END SSH_BINARY ====
#   ==== BEGIN SCP_BINARY ====
#   /path/to/scp
#   ==== END SCP_BINARY ====
#   ==== BEGIN PUBKEY ====
#   ssh-ed25519 AAAA... comment
#   ==== END PUBKEY ====
#   ==== BEGIN KEY_PATH ====
#   /path/to/private_key
#   ==== END KEY_PATH ====
#   ==== BEGIN WORKSPACE ====
#   /path/to/workspace
#   ==== END WORKSPACE ====

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info()  { echo -e "${BLUE}[INFO]${NC} $1" >&2; }
log_ok()    { echo -e "${GREEN}[OK]${NC} $1" >&2; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $1" >&2; }
log_error() { echo -e "${RED}[ERROR]${NC} $1" >&2; }

HOST_LABEL=""
WORKSPACE=""

# ─── Args ────────────────────────────────────────────────────────────────────

while [[ $# -gt 0 ]]; do
    case "$1" in
        --host)      HOST_LABEL="$2"; shift 2 ;;
        --workspace) WORKSPACE="$2"; shift 2 ;;
        -h|--help)
            echo "Usage: ssh-tmux-setup.sh [--host <hostname>] [--workspace <dir>]"
            echo "  --host       Label for key comment (e.g. myserver.com)"
            echo "  --workspace  Root dir for session files (default: ~/tmux-sessions/<timestamp>)"
            exit 0 ;;
        *) log_error "Unknown: $1"; exit 1 ;;
    esac
done

# ─── Platform detection ─────────────────────────────────────────────────────

is_windows() {
    [[ "$OSTYPE" == "msys" || "$OSTYPE" == "cygwin" || "$OSTYPE" == "win32" ]] || [[ -n "${WINDIR:-}" ]]
}

# ─── Detect SSH binary ──────────────────────────────────────────────────────
# On Windows, multiple SSH installations compete:
#   1. Windows OpenSSH: C:\Windows\System32\OpenSSH\ssh.exe
#   2. Git for Windows:  C:\Program Files\Git\usr\bin\ssh.exe
#   3. Others (scoop, choco, msys2)
#
# We prefer Windows OpenSSH because it talks to the Windows ssh-agent service.
# Git's ssh uses its own agent protocol and can't see Windows ssh-agent keys.

detect_ssh_binary() {
    if is_windows; then
        local win_ssh="/c/Windows/System32/OpenSSH/ssh.exe"
        local git_ssh
        git_ssh="$(command -v ssh 2>/dev/null || true)"

        if [[ -x "$win_ssh" ]]; then
            log_info "Found Windows OpenSSH: $win_ssh"
            echo "$win_ssh"
            return 0
        fi

        # Try via PowerShell (handles non-standard paths)
        local ps_ssh
        ps_ssh=$(powershell.exe -NoProfile -Command \
            '(Get-Command ssh.exe -ErrorAction SilentlyContinue | Where-Object { $_.Source -like "*OpenSSH*" }).Source' \
            2>/dev/null | tr -d '\r') || true

        if [[ -n "$ps_ssh" ]]; then
            local unix_path
            unix_path=$(echo "$ps_ssh" | sed 's|\\|/|g; s|^\([A-Za-z]\):|/\L\1|')
            log_info "Found Windows OpenSSH via PS: $unix_path"
            echo "$unix_path"
            return 0
        fi

        # Fallback to whatever is in PATH
        if [[ -n "$git_ssh" ]]; then
            log_warn "Using Git SSH (Windows OpenSSH not found): $git_ssh"
            log_warn "Keys may not be visible to Windows ssh-agent service"
            echo "$git_ssh"
            return 0
        fi

        log_error "No ssh binary found"
        return 1
    else
        local ssh_bin
        ssh_bin=$(command -v ssh 2>/dev/null) || { log_error "ssh not found"; return 1; }
        echo "$ssh_bin"
    fi
}

detect_scp_binary() {
    local ssh_bin="$1"
    local scp_bin="${ssh_bin/ssh/scp}"

    if [[ -x "$scp_bin" ]]; then
        echo "$scp_bin"
    elif command -v scp &>/dev/null; then
        command -v scp
    else
        log_warn "scp not found alongside $ssh_bin"
        echo "scp"
    fi
}

# ─── Detect and start ssh-agent ─────────────────────────────────────────────

ensure_ssh_agent() {
    if is_windows; then
        # Check Windows OpenSSH agent service
        local status
        status=$(powershell.exe -NoProfile -Command \
            '(Get-Service ssh-agent -ErrorAction SilentlyContinue).Status' \
            2>/dev/null | tr -d '\r') || true

        if [[ "$status" != "Running" ]]; then
            log_info "Starting Windows ssh-agent service..."
            powershell.exe -NoProfile -Command \
                'Get-Service ssh-agent | Set-Service -StartupType Manual; Start-Service ssh-agent' \
                2>/dev/null || {
                log_warn "Could not start ssh-agent service (may need admin)"
                log_info "Falling back to ssh-agent subprocess..."
                eval "$(ssh-agent -s)" 2>/dev/null || true
                return 0
            }
        fi
        log_ok "Windows ssh-agent service running"
    else
        if [[ -z "${SSH_AUTH_SOCK:-}" ]]; then
            log_info "Starting ssh-agent..."
            eval "$(ssh-agent -s)" >/dev/null
        fi
        log_ok "ssh-agent available (SSH_AUTH_SOCK=$SSH_AUTH_SOCK)"
    fi
}

# ─── Generate key ───────────────────────────────────────────────────────────

generate_key() {
    local workspace="$1"
    local host_label="$2"

    local ts
    ts=$(date +%Y%m%d_%H%M%S)
    local key_name="id_tmux_skill_${ts}"
    local key_dir="$workspace/keys"
    local key_path="$key_dir/$key_name"

    mkdir -p "$key_dir"

    local comment="tmux-skill"
    [[ -n "$host_label" ]] && comment="tmux-skill@${host_label}"

    log_info "Generating ed25519 key: $key_path"
    ssh-keygen -t ed25519 -N "" -C "$comment" -f "$key_path" >/dev/null 2>&1

    if [[ ! -f "$key_path" ]]; then
        log_error "Key generation failed"
        return 1
    fi

    chmod 600 "$key_path"
    chmod 644 "${key_path}.pub"

    log_ok "Key generated: $key_path"
    echo "$key_path"
}

# ─── Add key to agent ───────────────────────────────────────────────────────

add_key_to_agent() {
    local key_path="$1"
    local ssh_bin="$2"

    # Derive ssh-add from same dir as ssh binary
    local ssh_add="${ssh_bin/ssh/ssh-add}"
    if [[ ! -x "$ssh_add" ]]; then
        ssh_add="ssh-add"
    fi

    log_info "Adding key to agent via: $ssh_add"

    if is_windows; then
        # Windows ssh-add needs Windows path
        local win_key_path
        win_key_path=$(cygpath -w "$key_path" 2>/dev/null || echo "$key_path")
        "$ssh_add" "$win_key_path" 2>/dev/null || "$ssh_add" "$key_path" 2>/dev/null || {
            log_error "Failed to add key to agent"
            return 1
        }
    else
        "$ssh_add" "$key_path" 2>/dev/null || {
            log_error "Failed to add key to agent"
            return 1
        }
    fi

    log_ok "Key loaded into ssh-agent"
}

# ─── Structured output ──────────────────────────────────────────────────────

emit_block() {
    local label="$1"
    local content="$2"
    echo "==== BEGIN ${label} ===="
    echo "$content"
    echo "==== END ${label} ===="
}

# ─── Main ────────────────────────────────────────────────────────────────────

main() {
    # Setup workspace
    if [[ -z "$WORKSPACE" ]]; then
        local ts
        ts=$(date +%Y%m%d_%H%M%S)
        local label="${HOST_LABEL:-session}"
        WORKSPACE="$HOME/tmux-sessions/${label}_${ts}"
    fi
    mkdir -p "$WORKSPACE"/{keys,scripts,logs}

    log_info "Workspace: $WORKSPACE"
    log_info "Detecting SSH environment..."

    # 1. Detect SSH binary
    local ssh_bin
    ssh_bin=$(detect_ssh_binary) || exit 1

    local scp_bin
    scp_bin=$(detect_scp_binary "$ssh_bin")

    # 2. Ensure ssh-agent running
    ensure_ssh_agent

    # 3. Generate key
    local key_path
    key_path=$(generate_key "$WORKSPACE" "$HOST_LABEL") || exit 1

    # 4. Add to agent
    add_key_to_agent "$key_path" "$ssh_bin" || exit 1

    # 5. Read pubkey
    local pubkey
    pubkey=$(cat "${key_path}.pub")

    # 6. Emit structured output
    echo ""
    emit_block "SSH_BINARY" "$ssh_bin"
    emit_block "SCP_BINARY" "$scp_bin"
    emit_block "PUBKEY" "$pubkey"
    emit_block "KEY_PATH" "$key_path"
    emit_block "WORKSPACE" "$WORKSPACE"

    echo "" >&2
    log_ok "Setup complete."
    log_info "Next: authorize the public key on the remote host"
    log_info "Workspace structure:"
    log_info "  $WORKSPACE/"
    log_info "  ├── keys/       — SSH keys for this session"
    log_info "  ├── scripts/    — Step scripts to ship to remote"
    log_info "  └── logs/       — Command logs and output"
}

main
