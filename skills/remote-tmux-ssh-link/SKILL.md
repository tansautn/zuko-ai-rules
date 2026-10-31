---
name: "remote-tmux-ssh-link"
description: "Connect to a remote Linux server over SSH (key via ssh-agent) and open or attach a shared tmux session so you and the user share one live terminal, verify the channel works, then hold for instructions. Use at the start of any co-work session on a remote box."
---

# Remote tmux + SSH link

Establish a **shared control channel** to a remote Linux server: you run commands, the user
watches the same terminal live and can type/veto. Once the channel is up and verified,
report ready and **wait for the next instruction** — this skill sets up the link, it does
not decide what work to do on the box.

Run this at the start of any session where the user wants to supervise remote work live
(server upgrades, risky maintenance, paired debugging). The sysadmin methodology that uses
this channel lives in the `system-administrator-cowork` skill.

## Why tmux + one-shot SSH (not plain SSH exec)

Claude Desktop background tasks only *show* output; they aren't interactive, so the user
can't type into them. A shared tmux session solves this:

- **The user** keeps a session attached and watches it in real time.
- **You** drive it with one-shot, no-TTY SSH calls that inject keystrokes and read the pane.
- **Crucially**: when a command restarts `sshd` (e.g. during an upgrade), your SSH drops
  but the work keeps running inside tmux, unaffected by the connection's SIGHUP.

## Session workspace

**ALL files** this skill creates or uses (keys, scripts, logs, investigation output) go
under **one root directory** — never scatter to `$HOME` or random temp paths.

The setup script creates this structure automatically:
```
~/tmux-sessions/<host>_<timestamp>/
├── keys/       — SSH keys generated for this session
├── scripts/    — Step scripts to ship to remote
└── logs/       — Command logs, pane captures, investigation output
```

When writing any file during the session (a script to scp, a captured log, a backup):
- **Local files** → `$WORKSPACE/scripts/` or `$WORKSPACE/logs/`
- **Remote files** → `/root/tmux-workspace/` (or equivalent home-relative path on remote)

## Setup sequence

### 1. Run the SSH setup script

**Do NOT manually search for SSH keys or fumble with ssh-agent.** Run the setup script:

```bash
bash scripts/ssh-tmux-setup.sh --host <hostname>
```

The script:
1. Generates a new `ed25519` key (no passphrase, named `id_tmux_skill_<timestamp>`)
2. Detects the correct SSH binary (Windows OpenSSH preferred over Git SSH)
3. Starts ssh-agent if needed and loads the key
4. Outputs structured blocks you parse for `SSH_BINARY`, `SCP_BINARY`, `PUBKEY`, `KEY_PATH`, `WORKSPACE`

Parse the output blocks:
```
==== BEGIN SSH_BINARY ====
/c/Windows/System32/OpenSSH/ssh.exe
==== END SSH_BINARY ====
```

Then **show the public key to the user** and ask them to authorize it on the remote host
(`~/.ssh/authorized_keys`). Wait for confirmation before proceeding.

Store the parsed values — use `$SSH_BIN`, `$SCP_BIN`, `$KEY_PATH`, `$WORKSPACE` throughout
the session. **Never hardcode paths.**

### 2. Verify connectivity and snapshot who/where you are
```bash
ssh -o BatchMode=yes -o ConnectTimeout=15 -o StrictHostKeyChecking=accept-new \
  -p <port> -i <key> root@<host> \
  "hostname; cat /etc/os-release | grep PRETTY_NAME; uname -r; id; which tmux; tmux ls 2>&1 | head"
```
If this fails, stop and report — don't start work on an unverified link.

### 3. Ensure a shared tmux session
Ask the user to open one and leave it attached, or create it yourself if they prefer:
```bash
apt install -y tmux        # or use screen -x if tmux is unavailable
tmux new -s <session>      # e.g. 'upgrade' or 'work'
```
Comfort for the user: enable mouse + scrollback once:
```bash
printf 'set -g mouse on\nset -g history-limit 50000\n' >> ~/.tmux.conf
tmux set -g mouse on; tmux set -g history-limit 50000
```
Scroll without mouse: `Ctrl-b [` → copy-mode (PgUp/arrows, `/` search, `q` quit).

### 4. Drive it — send keys, read the pane
```bash
ssh ... root@<host> "tmux send-keys -t <session> 'apt update' Enter"
ssh ... root@<host> "tmux capture-pane -p -t <session> -S -200"
```

## Running a script step (the stable pattern)

Inline commands are fragile. For anything non-trivial: write a script in `$WORKSPACE/scripts/`,
ship it, run it in tmux, poll for completion.
```bash
# Write script locally under workspace
cat > "$WORKSPACE/scripts/step-01.sh" << 'SCRIPT'
#!/bin/bash
set -euo pipefail
# ... step logic ...
SCRIPT

# Ship to remote workspace
$SSH_BIN ... root@<host> "mkdir -p /root/tmux-workspace"
$SCP_BIN -P <port> -i $KEY_PATH "$WORKSPACE/scripts/step-01.sh" root@<host>:/root/tmux-workspace/step-01.sh
$SSH_BIN ... root@<host> "sed -i 's/\r$//' /root/tmux-workspace/step-01.sh; chmod +x /root/tmux-workspace/step-01.sh; \
  tmux send-keys -t <session> 'clear; bash /root/tmux-workspace/step-01.sh 2>&1 | tee /root/tmux-workspace/step-01.log' Enter"
```
`sed -i 's/\r$//'` strips CRLF — scripts authored on Windows carry `\r` that breaks bash.

### ⚠️ PowerShell eats `$`
When the SSH client runs under PowerShell, `$` inside a double-quoted string is interpolated
**before** bash sees it: `awk '{print $2}'` silently becomes `awk '{print }'` — empty
output, **no error**. Don't fight it with escaping. From the second non-trivial command on,
**put the logic in a `.sh` file and `scp` it**; never inline `awk`/`grep`/`for` with `$`.

## Monitoring a long step

Piping through `tail` buffers output, so the pane can look frozen while work proceeds.
Check real state instead of trusting the pane:
```bash
pgrep -c apt-get                       # still running?
wc -l < /var/log/dpkg.log              # advancing?
tmux capture-pane -p -t <session> | tail -4
ps -eo pid,stat,etime,cmd | grep -E 'apt-get|dpkg|debconf|ucf'
```
For a phase the user should watch, run it **without** the `tail` pipe so the pane streams.

## Reboot kills the session

A reboot destroys the tmux session (and drops your SSH). After any reboot: probe until the
box answers, recreate the session, and tell the user to `tmux attach -t <session>` again.

## Secrets hygiene on the channel

- Create credential files via **direct** SSH, not `tmux send-keys`, so passwords never
  land in the pane's scrollback.
- Never `echo` a password or token. If a service unit leaks a token in its `ExecStart` and
  it surfaces in your output, tell the user it's now in the transcript and to rotate it.
- Prefer the user creating `~/.my.cnf` (chmod 600) on the box over pasting a DB password
  into chat.

## When the link is up

Report: host, OS/kernel, tmux session name + attach state, disk/RAM headroom. Then **stop
and wait for the user's instruction** on what to do next.

## End session protocol

When the objective is achieved or the user asks to end the session:

1. **Remote cleanup report** — list all files/dirs created on the remote:
   ```
   Remote files created during this session:
     /root/tmux-workspace/step-01-backup.sh
     /root/tmux-workspace/step-01-backup.log
     /root/step.sh  (if any leaked outside workspace — flag it)
   ```

2. **Local workspace report**:
   ```
   Local session workspace: ~/tmux-sessions/myhost_20261031_143000/
     keys/id_tmux_skill_20261031_143000      — private key (revoke from agent)
     keys/id_tmux_skill_20261031_143000.pub  — public key (remove from remote authorized_keys)
     scripts/step-01-backup.sh               — shipped to remote
     logs/baseline-snapshot.txt              — pre-work baseline
     logs/pane-capture-final.txt             — last pane state
   ```

3. **Key revocation reminder**: tell user to remove the pubkey from remote `authorized_keys`
   and optionally `ssh-add -d <key_path>` locally.

4. **Do NOT delete** the workspace — the user may need logs/scripts later. Just report the
   path and let them decide.