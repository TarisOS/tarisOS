# TarisOS Development Machine

Read this before any work on a TarisOS development machine: one with `/etc/taris/dev-machine`
(installed by the `taris-dev` package). taris-dev also installs this file as
`/usr/share/taris/agent-rules-dev.md`, which the rules for users' agents
(`/usr/share/taris/agent-rules.md`) send every agent to. These rules take precedence over those
rules and over the end-user skills (`/usr/share/taris/agent-skills/`) wherever they disagree. The
skills still describe where things live and how the system works; these rules decide where the
work goes.

## The checkout

The first line of `/etc/taris/dev-machine` that isn't empty or a comment is the path of the
TarisOS checkout. Read its `AGENTS.md` and the task guide that matches the work
(`agents/skills/`) before starting, wherever the session started: they are binding. When the file
names no checkout, ask for it.

## Drafts first

- Every change starts as a draft, outside the checkout: code, packaging and configuration alike.
  Drafts go in `~/.cache/taris-drafts/<task>/`, laid out as the repository is
  (`<task>/shell/...`, `<task>/packaging/...`), so each file's place is clear. Never in `/tmp`,
  which is RAM and is lost at the next restart.
- The checkout changes only on explicit approval: the maintainer saying to put it in the
  repository, that it's approved, or to commit it. A request worded as a change ("add X", "fix Y",
  "let's change Z") is a request for a draft, not that approval.
- Once approved, copy the draft into the checkout as it was tested, then run the checks the task
  guide lists. Keep the draft until the maintainer says it can go.

## Testing on this machine

- To try a draft on the installed system, write a `test-install.sh` in the draft's folder (run as
  root): it copies each drafted file over the installed one, keeping the installed one in
  `<task>/backup/` first (once, so a second run doesn't overwrite the original). Write a
  `test-revert.sh` that puts the backups back. Hand both over with their exact commands; the
  maintainer runs them.
- The shell doesn't reload replaced files: after a test install, the shell has to be restarted
  (`taris shell -k && taris shell -d`). Say so, and before drawing any conclusion confirm from the
  shell's log (`taris shell -l`) that the new code is what ran.
- Probe shell code without touching the session: a copy of the drafted shell tree, a probe
  `ShellRoot` that touches the singletons it needs when it starts (they are only created when first
  used) and logs what it finds, run with `taris-qs -p`, with `XDG_CONFIG_HOME`, `XDG_STATE_HOME` and
  `XDG_CACHE_HOME` pointed at copies of the account's folders and a stand-in `hyprctl` first on
  `PATH`, so nothing reaches the running Hyprland or the real configuration.
- No UI testing by the agent: no screenshots, recordings or moving the pointer. The maintainer
  tests what shows on screen; work from the code and the logs.
- A regression is the change's to fix: compare with the installed code and bring back the old
  behaviour rather than looking for causes in the setup.

## Handing over

Say what changed (file by file), how to install and revert it, what was verified and how, and what
wasn't. Never claim a test that didn't run.
