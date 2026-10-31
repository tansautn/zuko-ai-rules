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

## Setup sequence

### 1. Load the SSH key into ssh-agent (once)
One-shot SSH has no TTY, so a passphrase prompt fails. Load the key into the agent instead
of generating a weak nopassphrase key. On Windows:
```powershell
Get-Service ssh-agent | Set-Service -StartupType Automatic
Start-Service ssh-agent
ssh-add $env:USERPROFILE\.ssh\id_ed25519   # passphrase entered once
ssh-add -l                                  # verify loaded
```
Revoke when done: `ssh-add -d` / `Stop-Service ssh-agent`. Windows OpenSSH has no
`ControlMaster`, so each command is a fresh TCP handshake — slower, harmless.

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

Inline commands are fragile. For anything non-trivial: write a script, ship it, run it in
tmux, poll for completion.
```bash
scp -P <port> -i <key> step.sh root@<host>:/root/step.sh
ssh ... root@<host> "sed -i 's/\r$//' /root/step.sh; chmod +x /root/step.sh; \
  tmux send-keys -t <session> 'clear; bash /root/step.sh 2>&1 | tee /root/step.log' Enter"
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