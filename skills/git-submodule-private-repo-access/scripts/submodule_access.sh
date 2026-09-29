#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Give the current environment access to every submodule of this repository,
# including private ones, then initialize them.
#
#   1. Private submodule already checked out -> skip the network probe.
#   2. HTTPS already works (credential helper, cached PAT, App token)
#      -> configure nothing, the existing credentials do the job.
#   3. Otherwise use the deploy key: rewrite the HTTPS remote to SSH for that
#      one repo and pin the key to it.
#   4. No credentials and no key -> initialize the public submodules only.
#
# Idempotent and never exits non-zero, so a bootstrap hook can run it every
# time. Deliberately not silent: a hook that prints nothing looks the same
# whether it worked, did nothing, or died on line 3.
#
# `pipefail` is intentionally absent. With it, `producer | grep -q ...` returns
# 141 when grep exits early and SIGPIPEs the producer, so a guard written as
# `if ! producer | grep -q ...` reads a *failed check* as *nothing to do* and
# skips the real work in silence. Checks must fail towards doing the work.
# ---------------------------------------------------------------------------
set -u

# =============================== CONFIG ====================================
# The private repo, as owner/name on the git host.
PRIVATE_SLUG="OWNER/PRIVATE-REPO"

# Submodule paths that must initialize even with zero credentials — typically
# whatever carries the coding rules or agent instructions. Space separated,
# may be empty.
PUBLIC_FIRST=".agents"

# Deploy key filename, resolved relative to this script's directory.
KEY_NAME=".private-submodule.deploy.key"

# Optional: base64 of the private key, overriding the committed file.
KEY_ENV_VAR="DEPLOY_KEY_B64"

GIT_HOST="github.com"
# ===========================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
KEY="$SCRIPT_DIR/$KEY_NAME"

PRIVATE_HTTPS="https://$GIT_HOST/$PRIVATE_SLUG"
PRIVATE_SSH="git@$GIT_HOST:$PRIVATE_SLUG.git"
PRIVATE_BASENAME="${PRIVATE_SLUG##*/}"

# Fail fast instead of blocking forever on an interactive credential prompt.
export GIT_TERMINAL_PROMPT=0

log()  { printf '[submodule-access] %s\n' "$*" >&2; }
warn() { printf '[submodule-access] WARN: %s\n' "$*" >&2; }

# Resolve the private submodule's path from .gitmodules, so moving it in the
# tree does not silently turn this script into a no-op.
private_name="$(git -C "$REPO_DIR" config -f .gitmodules --get-regexp '\.url$' 2>/dev/null \
    | awk -v pat="$PRIVATE_BASENAME" '$0 ~ pat {print $1}' | sed 's/^submodule\.//;s/\.url$//')"
private_path="$(git -C "$REPO_DIR" config -f .gitmodules --get "submodule.$private_name.path" 2>/dev/null || true)"

# --- 0. Key permissions ----------------------------------------------------
# git stores only the executable bit, so a committed key arrives as 0644 and
# ssh refuses it ("UNPROTECTED PRIVATE KEY FILE"). Unconditional, and it never
# dirties the work tree: 0600 and 0644 are both 100644 to git.
[ -f "$KEY" ] && chmod 600 "$KEY" 2>/dev/null

# --- 1. Public submodules first --------------------------------------------
# On their own line so no credential failure can starve them.
for sub in $PUBLIC_FIRST; do
    [ -n "$sub" ] || continue
    if ! err="$(git -C "$REPO_DIR" submodule update --init --force "$sub" 2>&1)"; then
        warn "could not initialize $sub"
        printf '%s\n' "$err" >&2
    fi
done

# --- 2. A stale directory blocks the clone, and git cannot self-heal it -----
if [ -n "$private_path" ] \
   && [ -d "$REPO_DIR/$private_path" ] \
   && [ ! -e "$REPO_DIR/$private_path/.git" ] \
   && [ -n "$(ls -A "$REPO_DIR/$private_path" 2>/dev/null)" ]; then
    warn "$private_path exists, is not empty, and is not a git checkout."
    warn "git cannot clone into it. Remove it first:  rm -rf '$REPO_DIR/$private_path'"
fi

# --- 3. Decide how to reach the private submodule --------------------------
# The guard below is narrow on purpose: its worst case is one redundant
# network round trip, never skipping the initialization that follows.
if [ -n "$private_path" ] && [ -e "$REPO_DIR/$private_path/.git" ]; then
    log "$private_path already checked out"
elif git ls-remote "$PRIVATE_HTTPS.git" HEAD >/dev/null 2>&1; then
    log "HTTPS credentials already available, no deploy key needed"
else
    # An env var beats the committed file so the key can be rotated without a
    # commit. Written outside the repo to keep the work tree clean.
    key_b64="$(eval "printf '%s' \"\${$KEY_ENV_VAR:-}\"")"
    if [ -n "$key_b64" ]; then
        KEY="$HOME/$KEY_NAME"
        printf '%s' "$key_b64" | base64 -d > "$KEY"
        chmod 600 "$KEY" 2>/dev/null
    fi

    if [ -s "$KEY" ]; then
        # IdentitiesOnly stops ssh offering other keys first, which would make
        # the host answer as the wrong repo ("repository not found").
        export GIT_SSH_COMMAND="ssh -i '$KEY' -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new"

        # .gitmodules keeps its HTTPS url so credential-helper setups elsewhere
        # keep working. The rewrite happens only here, per environment.
        git config --global --replace-all "url.$PRIVATE_SSH.insteadOf" "$PRIVATE_HTTPS"
        git config --global --add         "url.$PRIVATE_SSH.insteadOf" "$PRIVATE_HTTPS.git"

        log "using deploy key $KEY"
    else
        warn "no credentials and no deploy key, private submodules will be skipped"
    fi
fi

# --- 4. Initialize everything ----------------------------------------------
# GIT_SSH_COMMAND is inherited by the child git processes that clone each
# submodule, so no per-submodule flag is needed.
if ! err="$(git -C "$REPO_DIR" submodule update --init --recursive 2>&1)"; then
    warn "some submodules were skipped"
    printf '%s\n' "$err" >&2
fi

# --- 5. Persist the key inside the submodule -------------------------------
# A later plain `git push` from within the submodule is a fresh process that
# inherits no environment, so store the key in that repo's own config too.
if [ -n "${GIT_SSH_COMMAND:-}" ] && [ -n "$private_path" ] && [ -e "$REPO_DIR/$private_path/.git" ]; then
    git -C "$REPO_DIR/$private_path" config core.sshCommand "$GIT_SSH_COMMAND"
    log "pinned deploy key to $private_path for push access"
fi

exit 0
