---
name: git-submodule-private-repo-access
description: Make `git submodule update --init` work everywhere when at least one submodule lives in a private repo — on dev machines with a credential helper, on CI runners, and on cloud/headless coding agents that have no git credentials at all. Use this skill whenever a repo has a private submodule; whenever submodule init fails with "could not read Username", "Permission denied (publickey)", "Authentication failed", "Failed to clone ... Retry scheduled", or "destination path already exists and is not an empty directory"; whenever someone asks how to give a build server, a deploy target, or an AI coding agent read or write access to a private dependency repo; and whenever deploy keys, `.gitmodules`, `url.insteadOf`, `GIT_SSH_COMMAND`, `core.sshCommand`, or "the agent can't fetch our rules repo" come up. Also use it when designing the bootstrap or SessionStart step of a repo that must behave identically for humans and for headless agents.
---

# Private submodule access

## The problem this solves

A repo has several submodules. Most are public, one is private. Every
environment runs the same `git submodule update --init --recursive`, but they
do not have the same credentials:

| Environment | What it has |
|---|---|
| Dev laptop | credential helper, personal SSH key, or both |
| CI runner | maybe a secret, maybe nothing |
| Deploy target | often nothing |
| Cloud / headless coding agent | almost always nothing |

The private submodule fails, and because `git submodule update` aborts the
whole run when a clone fails twice, **the public submodules never get checked
out either**. When one of those public submodules carries the repo's coding
rules or agent instructions, the agent then works blind and nobody notices.

The fix has two halves: make the public submodules independent of any
credential, and give the credential-less environments exactly one narrow way
in.

## Step 1: choose the credential mechanism

Ask what the trust boundary should be, then pick:

| Mechanism | Scope | Use when |
|---|---|---|
| **Deploy key** (SSH keypair registered on one repo) | exactly one repo, read or read+write | Default choice. Narrowest blast radius. |
| Fine-grained PAT | one account, one or more repos, expires | You need HTTPS specifically, or several private repos. |
| GitHub App installation token | org-scoped, short-lived | Real CI at org scale, with infra to mint tokens. |

Prefer the deploy key unless something rules it out. Its scope is a single
repo, so "whoever can read the parent repo can write the submodule" is a
statement you can actually reason about — unlike a PAT, whose scope is the
whole account.

Deploy keys are SSH-only and a given public key can be registered on only one
repo; GitHub rejects a duplicate. Write access is a checkbox at registration
time (*Allow write access*) and cannot be added later without re-registering.

Confirm the trust model out loud with the user before committing a key
anywhere: **reading the parent repo becomes equivalent to whatever access the
key grants.** If they are fine with that, say so in the docs and move on. If
they are not, use an env-var/secret delivery instead and keep the same script.

## Step 2: the four rules that keep this from breaking

These are the parts people get wrong. Each one has a cost attached.

**Keep `.gitmodules` on HTTPS.** It is committed and shared, so it must work
for the environment that has the most conventional setup — usually a developer
whose credential helper only knows HTTPS. Switching it to `git@github.com:`
to suit the headless case breaks every human on the team. Rewrite the URL at
runtime instead, per environment, with `url.<ssh>.insteadOf <https>`.

**Fetch the public submodules first, on their own line.** If the repo's rules
or agent instructions live in a public submodule, that fetch must not share a
failure path with the private one. One `git submodule update --init --force
<public-path>` before anything else costs nothing and removes the entire class
of "agent silently had no rules".

**Never let a check's failure mean "skip the work".** See the gotchas below;
this one has teeth.

**Say something on every run.** A bootstrap hook that prints nothing looks
identical whether it worked, did nothing, or died on line 3. Log one line per
decision to stderr. It is a handful of tokens and it is the difference between
a five-minute diagnosis and an afternoon.

## Step 3: the script

`scripts/submodule_access.sh` in this skill is a working template. Copy it
into the target repo, edit the CONFIG block at the top (repo slug, public
submodule path, key filename), and that is the whole integration.

Its shape, and why each piece is there:

```
chmod 600 the key           unconditional; git cannot store 0600, only the exec bit
init the public submodule   isolated so no credential can starve it
detect stale directory      git cannot self-heal this one, so name the fix
decide auth                 already checked out? -> skip probe
                            HTTPS works? -> configure nothing
                            else -> deploy key
init everything             GIT_SSH_COMMAND is inherited by child git processes
persist core.sshCommand     so a later plain `git push` still authenticates
exit 0                      always; a bootstrap hook must not block the session
```

Two details worth understanding rather than copying:

`GIT_SSH_COMMAND` is an environment variable, so every `git` subprocess that
clones a submodule inherits it — that is what removes the need for per-command
flags. But a `git push` the user runs an hour later is a fresh process that
inherits nothing, which is why the script also writes `core.sshCommand` into
the submodule's own config. The env var covers the clone; the config covers
everything after.

`url.<base>.insteadOf <prefix>` is applied by git at most once, choosing the
longest matching prefix. It does not recurse, so a repo-specific HTTPS→SSH
rewrite coexists safely with a global SSH→HTTPS rewrite (a common setup on
Windows machines using Credential Manager).

## Step 4: wire it into the bootstrap

For Claude Code, a `SessionStart` hook in `.claude/settings.json`:

```json
{
  "hooks": {
    "SessionStart": [
      {
        "matcher": "startup|resume",
        "hooks": [
          {
            "type": "command",
            "command": "bash \"${CLAUDE_PROJECT_DIR}/scripts/submodule_access.sh\"",
            "timeout": 300,
            "statusMessage": "Initializing submodules..."
          }
        ]
      }
    ]
  }
}
```

Notes that matter: hook `timeout` is in seconds (default 600). Hooks in one
matcher group run **in parallel**, so if another hook depends on submodules
being present, chain them in a single command rather than listing them as
siblings. Plain stdout is not injected into the model's context — only a
`{"systemMessage": "..."}` JSON payload is — so logging freely costs no tokens.
A non-zero exit from `SessionStart` does not block the session.

Merge into an existing `settings.json` rather than overwriting it.

Then update the repo's agent instructions (`CLAUDE.md` or equivalent) to stop
telling agents to run `git submodule` by hand, and point at the script as the
manual fallback instead.

For CI, call the same script and deliver the key through a secret:

```yaml
- run: bash scripts/submodule_access.sh
  env:
    DEPLOY_KEY_B64: ${{ secrets.SUBMODULE_DEPLOY_KEY_B64 }}
```

## Gotchas that cost real time

**`set -o pipefail` plus `grep -q` turns a failed check into a clean bill of
health.** This one shipped and broke a production deploy:

```bash
set -uo pipefail
if ! git submodule status --recursive 2>/dev/null | grep -q '^[-+]'; then
    exit 0   # "nothing to do"
fi
```

`grep -q` exits the moment it matches, the producer gets SIGPIPE and returns
141, `pipefail` promotes 141 to the pipeline's status, and `if !` reads that as
*the check found nothing*. The script exits 0 having done nothing, printing
nothing. Any non-zero from the producer — a `safe.directory` refusal, a repo
in a half-initialized state — does the same thing.

The general lesson is larger than the syntax: **an optimization guard that can
skip the script's entire purpose is not worth the second it saves.** If you
keep a guard, scope it to one narrow question whose worst-case cost is a
redundant network call, and make uncertainty fall towards doing the work.

**Verifying on a machine that is already in the target state proves nothing.**
The buggy guard passed every check on a dev laptop where all submodules were
already initialized, because both the correct and the broken code exit 0 there.
To test a bootstrap script, reconstruct the clean-environment state: `git
submodule deinit -f <path>`, or clone into a temp dir, or empty the submodule
directory.

**`destination path already exists and is not an empty directory`.** Deploy
targets frequently have files at the submodule path from before it became a
submodule — a built frontend, a previous rsync. No flag to `git submodule
update` fixes this; the directory must be removed. Detect it and print the
exact `rm -rf` command, because git's own message does not tell the user what
to do.

**Key file permissions.** git records only the executable bit, so a key
committed to a repo arrives as 0644 and ssh refuses it with `UNPROTECTED
PRIVATE KEY FILE`. `.gitattributes` cannot express 0600. `chmod 600` in the
script is the only mechanism, it belongs outside any conditional branch, and
it never dirties the work tree because 0600 and 0644 are both `100644` to git.

**`GIT_TERMINAL_PROMPT=0`.** Without it, a credential-less environment blocks
on an interactive username prompt instead of failing. In a hook, that is a
hang with no explanation.

**`IdentitiesOnly=yes`.** Without it ssh offers every key the agent holds
before the one you specified with `-i`, and GitHub answers as whichever repo
matches first — which produces a baffling "repository not found" for a repo
that plainly exists.

**Committing a private key.** Only with the user's explicit agreement, and
then: verify `git check-ignore` does not silently drop it, add
`<path> -text export-ignore` to `.gitattributes` so it stays out of `git
archive` and dist tarballs, add it to `.dockerignore`, and write the rotation
procedure down. Note plainly in the docs that it lives in git history forever
and that the repo going public means immediate rotation. Prefer an env-var
secret wherever the environment can supply one — the template supports both.

## Verification checklist

Do not report this as working until each row is actually exercised:

- [ ] Environment **with** credentials: script logs "credentials available",
      writes nothing to global git config, leaves the work tree clean
- [ ] Environment **without** credentials: private submodule clones via the key
- [ ] Public submodule initializes when the private one cannot
- [ ] `git push` from inside the private submodule succeeds afterwards
- [ ] Second run is a no-op and still logs
- [ ] Key file is 0600 after a fresh clone
- [ ] `git status` clean after a run

The first two rows need two different machines, or a deliberately broken
credential state. Testing only the one you are sitting at is how the guard bug
above survived review.
