---
name: "system-administrator-cowork"
description: "Co-drive a risky sysadmin operation on a live Linux server with the user watching — a Debian release dist-upgrade (bullseye→bookworm→trixie) or any high-stakes change you run while they keep veto. Covers safety nets, phased gating, and the landmines that only surface mid-upgrade. Pairs with remote-tmux-ssh-link for the connection."
---

# System Administrator — Cowork mode

You and the user operate **one live server together**. You drive (compose and run the
commands), they watch a shared terminal in real time and keep veto power. This is not
"run a script and report back" — it is paired, human-in-the-loop system administration
where a wrong move can take the box down. Default to caution, narrate decisions, and never
cross an irreversible line without an explicit go.

Use this skill for: a Debian/Ubuntu release upgrade, or any operation on a production-like
host (purging packages, DB major-version moves, kernel/init changes, network/firewall
edits) that the user wants to supervise live.

**Prerequisite — the control channel.** This skill assumes a shared tmux + SSH link is
already up. Establish it first with the `remote-tmux-ssh-link` skill (ssh-agent key, shared
tmux session, script-ship pattern, the PowerShell `$` trap, monitoring, secrets hygiene).
Everything below is *what* to do over that channel.

### Workspace discipline

All session artifacts live under the workspace created by `ssh-tmux-setup.sh`:
- **Local**: `$WORKSPACE/scripts/`, `$WORKSPACE/logs/` — step scripts, captured output, baselines
- **Remote**: `/root/tmux-workspace/` — shipped scripts, step logs, backups

Never write files outside these directories. If a command produces output you need to keep,
pipe it to `$WORKSPACE/logs/<descriptive-name>.txt` (local) or
`/root/tmux-workspace/<name>.log` (remote).

---

## 1. Non-negotiable safety architecture

### Escape hatch — a second way in, proven
Before touching anything that can lock you out (sshd, firewall, dist-upgrade), stand up a
**second sshd on an alternate port** and **verify a login actually succeeds** on it — an
unverified escape hatch is not an escape hatch. The new port's host key isn't trusted yet:
use `-o StrictHostKeyChecking=accept-new`.

### Safety net before crossing any release boundary
- **Logical dumps while services run**: `mysqldump --single-transaction` (Aria/CSV tables
  are non-transactional — note the caveat), `pg_dumpall`, redis `BGSAVE` + copy `dump.rdb`.
  Verify each ends with its completion marker (`-- Dump completed`, `... cluster dump
  complete`); a truncated dump is worse than none.
- Cold backup (stop → `tar /var/lib/mysql`) only when forced to stop the DB; logical dump
  is the default because it restores cleanly.
- Snapshot `/etc`, mask `unattended-upgrades` so apt doesn't fire under you.
- Capture the **baseline before stopping anything**: `ss -tulpn`, enabled services, vhost
  HTTP status codes, `dpkg -l`, `sources.list`, held packages, kernel — you compare against
  this at the end.

### Human-in-the-loop
- Ask before anything irreversible or touching **live traffic**, even on a clone, even when
  "it's just the two of us." Prepare the work, lay out the decision, stop.
- When the user says "keep X" / "delete Y", read it back before acting — they may reverse
  themselves ("delete tor" then "keep them running" meant the DBs, not tor).
- Never "fix" something that looks like an accident without asking; they may have removed
  it on purpose (the cloudflared reinstall mistake).

---

## 2. Debian release dist-upgrade playbook

**Never skip a release.** 11→12→13 is 11→12, reboot, verify, then 12→13 — each leg a full
`apt full-upgrade` + reboot. Clone the server first and work on the clone.

Governing principle: **defuse landmines on the old stable, before crossing.** Apache
breaking on bullseye is cheap to debug; Apache breaking mid-dist-upgrade is not.

### Phase order
0. **Snapshot** baseline (above). Audit third-party repos.
1. **Reclaim disk** — purge `rc` packages (`dpkg -l | grep '^rc'`), vacuum `/var/log`,
   clean apt cache. Dist-upgrade needs headroom.
2. **Consolidate PHP / app stacks** — resolve multi-version sprawl *now*. Verify what
   actually serves traffic before purging (`conf-enabled` load order decides the global FPM
   handler; a later-loaded `phpX.Y-fpm.conf` wins). `apache2ctl configtest` + compare vhost
   status codes before/after. Purge only after the config is already valid without the
   version you're dropping.
3. **De-fork third-party-pinned packages** — a box pinned to e.g. mariadb.org's
   `12.rolling` will drag the server to 12.x on any `apt upgrade`. Pin the candidate back
   to the distro version and `apt-mark hold` the DB packages across the crossover.
4. **Reach a clean old-stable** — gate: `dpkg --audit` empty, holds only what you intended.
   Audit **manually-installed foreign packages** (installed version higher than any repo
   offers — `apt-cache policy` shows priority with no repo line): someone may have
   hand-installed a newer glibc/toolchain. Know this before crossing; it changes the plan.
5. **Retarget sources** to the new release (and every third-party repo's new suite). Verify
   `apt update` resolves with **zero errors**; confirm key packages' target versions
   (`libc6`, the DB, PHP) are what you expect.
6. **Cross over — two steps, both gated**:
   ```bash
   apt-get -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold \
     upgrade --without-new-pkgs -y        # STEP 1: no removals; safe if interrupted
   # GATE: abort on non-zero exit
   apt-get -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold \
     full-upgrade -y                       # STEP 2: new packages + removals
   # GATE: abort on non-zero exit
   ```
   `--force-confdef --force-confold`: keep configs you edited (critically `sshd_config`
   with your alternate port), take maintainer's for untouched ones, never hang the pane on
   a conffile prompt.
7. **Verify + reboot** into the new kernel, then re-verify against baseline.

### Gating correctness (two real bugs to avoid)
- `grep -vE '^ii'` as a "clean" check is **wrong** — it flags `hi` (hold+installed), i.e.
  your intentionally-held DB packages. Use `grep -vE '^(ii|hi)'`.
- **Gate BOTH upgrade steps.** A script that gates step 1 but not step 2 prints "REBOOT
  REQUIRED" even when step 2 died mid-transaction — and the user, trusting the banner,
  reboots into a half-upgraded box. Print the success banner only when *both* exits are 0;
  on any failure, stop and print the recovery command.

### Simulate before crossing
`apt-get -s full-upgrade`, read the removal list line by line. Distinguish:
- **False alarms**: `Remv cron` immediately followed by `Inst cron` + `Inst
  cron-daemon-common` = package split, remove-and-reinstall in one transaction, cron
  survives. Soname bumps (`libfoo1→libfoo2`) and transitionals are fine.
- **Real losses**: a service package removed with no replacement → stop and investigate.

### Recovery from an interrupted full-upgrade
A reboot/kill mid-`full-upgrade` leaves packages "unpacked but not configured." Recoverable
**because step 1 (`--without-new-pkgs`, exit 0) left the core — libc, systemd, dpkg, bash —
coherent, so the box still boots.**
```bash
dpkg --configure -a
apt-get -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold -f install -y
# then re-run full-upgrade to finish
```
The two-step split is the *reason* the box survives — not an accident.

### Post-upgrade verify
Against the baseline: vhost status codes (match or improve), every service active,
listening ports, `dpkg --audit` clean, 0 upgradable, holds as intended. Then re-check
socket-activation exposure (below).

### autoremove — never blind
Orphan-matching is pattern-based and bites: `mariadb-server` matches the
`mariadb-server-10.5` **transitional dummy** (which you *do* want gone) — confirm it's
transitional (`apt-cache show ... | grep -i transitional`) before trusting it, and ensure
the real metapackage stays. Guard autoremove and eyeball its list — it's how `cloudflared`
got removed out from under a running tunnel.

---

## 3. Landmine catalogue (what actually bites)

- **`mariadb.socket` / socket activation (bookworm+)**: systemd binds `*:3306` and hands
  the fd to mariadbd, **silently overriding `bind-address = 127.0.0.1`** — the DB is now on
  every interface, public IP, with a root password you both just typed. Fix:
  `systemctl disable --now mariadb.socket; systemctl restart mariadb`, confirm
  `ss -tlpn | grep 3306` is `127.0.0.1` only. Re-check after *every* crossover. Same
  mechanism exposes `dnscrypt-proxy.socket` on `0.0.0.0:53` (open resolver).
- **glibc collation version change** (e.g. 2.37→2.41): PostgreSQL stored the collation
  version at index-build time; a glibc bump breaks it. Symptom: `WARNING: database has a
  collation version mismatch`. **Silent** consequence — text indexes may sort wrong and
  **UNIQUE text constraints can let duplicates through**, no crash, no log. Fix after the
  final reboot: `reindexdb --all` then per-DB `ALTER DATABASE <db> REFRESH COLLATION
  VERSION;` (use `--concurrently` with live traffic). MariaDB is immune — its collations
  don't depend on glibc.
- **`t64` transition (bookworm→trixie)**: the 64-bit `time_t` / Y2038 fix renamed ~every
  lib package (`libssl3`→`libssl3t64`) to force an ABI break even on amd64 (already 64-bit
  — pure rename there). The new package `Provides:` the old name, so deps stay satisfied
  and apt swaps during full-upgrade. Dozens of renames; noisy, not a problem.
- **PostgreSQL major version**: a distro's `postgresql` metapackage pulls the new major,
  needing manual `pg_upgrade`. But if only the **versioned** package is installed
  (`postgresql-16`, no metapackage) and PGDG ships that version for the new release, the
  cluster stays on its major and is merely rebuilt — no migration. Check which is installed
  before assuming a `pg_upgrade`.
- **Hand-installed files blocking dpkg** (symlink switch): e.g. phpMyAdmin's maintscript
  wants to turn a dir into a symlink but it holds files dpkg doesn't own (a hand-installed
  theme). dpkg refuses, correctly, and blocks all apt. Fix: `tar` the custom content aside,
  remove the obstructing dir, let dpkg proceed.
- **Orphaned process from a deleted inode**: a binary removed by autoremove while its
  process runs (`/proc/<pid>/exe -> ... (deleted)`) keeps working until it restarts, then
  can't. Reinstall the package and confirm the unit's `ExecStart` path matches the restored
  binary before restarting.
- **Packages the new release drops**: e.g. `haveged` (gone in bookworm), `chrony` removed
  in a transaction — plan to reinstall from the *new* release's repo after crossing, not
  the old version then re-upgrade.

---

## 4. Working stance (from how these sessions actually went)

- **Push back when an instruction collides with observed reality.** "Purge everything ≤8.2"
  but 8.1 is the live global FPM handler → stop, show the evidence, get a corrected call.
  "Realign glibc now" → argue for *after* the crossover so you touch glibc once, not twice
  (downgrading glibc on a running box is a classic way to lose it).
- **Own mistakes precisely** — name the exact bug (the un-gated step 2, the reinstalled
  cloudflared), don't grovel, fix it.
- **Report exposure you caused or discovered** (a leaked token, a newly public port) even
  when inconvenient.
- Keep a visible task list; after each phase give a tight status table (done / pending /
  disk + RAM headroom) rather than narrating every command.
- RAM is often the real constraint on small VPSs, not disk — stop heavy services (tor/danted
  swarms, redis after BGSAVE) before a full-upgrade to free headroom.

---

## 5. End session — reporting and cleanup

When the objective is complete or the user ends the session:

### Report to user

Produce a structured summary:

```
═══ SESSION COMPLETE ═══

Objective: <what was done>
Result: <success/partial/failed>

Remote files (on <host>):
  /root/tmux-workspace/step-01-backup.sh
  /root/tmux-workspace/step-01-backup.log
  /root/tmux-workspace/baseline.txt
  /root/mysql-backup-20261031.sql.gz       ← backup outside workspace (flagged)

Local workspace: ~/tmux-sessions/<host>_<timestamp>/
  keys/       — SSH key pair (revoke pubkey from remote)
  scripts/    — Step scripts shipped to remote
  logs/       — Baselines, pane captures, investigation notes

Action needed:
  • Remove pubkey from remote ~/.ssh/authorized_keys
  • Optionally: ssh-add -d <key_path>
  • Review remote /root/tmux-workspace/ — keep or clean up
```

### Rules
- **Never auto-delete** remote workspace or backups — user decides
- **Flag any files** that ended up outside the designated workspace dirs (both local and remote)
- If backups were created (DB dumps, /etc snapshots), explicitly list their paths and sizes
- If services were stopped for the operation, confirm they were restarted