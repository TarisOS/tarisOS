---
name: diagnose-crash
description: >
  Diagnose why a program crashed on this machine, from a systemd-coredump core dump.
  Use when a process has segfaulted, aborted, or otherwise dumped core, or when asked
  why an application crashed or disappeared. Triggers: crash, segfault, SIGSEGV, SIGABRT,
  core dump, coredumpctl, "why did X crash", "X keeps crashing", backtrace symbolization.
  Covers reporting a confirmed bug in this setup — see reporting.md.
---

# Diagnosing a Crash

Work from evidence. The goal is an honest account of what happened, not a
plausible-sounding story.

## Establish the facts

`coredumpctl info <pid>` is the starting point. Beyond the backtrace, note the
**command line** the process was started with — it usually reveals what the
program was working on when it died, which is often the whole answer.

`coredumpctl list` shows whether this crash is a one-off or a pattern. Repeated
crashes of the same program, or several programs dying together, point somewhere
different than a single failure does.

## Rule out the boring causes first

Check resource exhaustion before blaming the program: `free -h`, and the journal
for OOM kills. A process killed by the OOM killer is not a bug in that process.

## Correlate against the timeline

The crash timestamp is the most underused piece of evidence. Compare it against:

- **Filesystem mtimes.** A directory or file whose mtime lands on the same second
  as the crash strongly suggests what triggered it.
- **The journal** around that moment, for related warnings from the same or
  neighbouring processes.
- **Recent package updates** (`/var/log/pacman.log`). A crash that starts right after
  an update points at the update.

## Read the whole core, not just frame 0

Thread stacks other than the crashing one show what work was **in flight** —
thumbnailers, image loaders, IPC readers, GPU queues. That context often explains
the trigger even when the crashing frame itself cannot be symbolized.

Note any third-party code in the address space: file-manager or browser
extensions, plugins, out-of-tree drivers. In-process third-party code is a common
crash source and worth flagging — but do not pin blame on it without evidence
that it is actually implicated.

On Apple Silicon, also note the GPU driver (Mesa's Asahi driver) and the kernel's
own messages (`journalctl -k` around the crash): GPU and driver faults show up
there.

## Symbolize when you can

This is Arch Linux ARM (aarch64). Arch Linux's debuginfod server only serves Arch's
own x86_64 builds, so it cannot symbolize these packages. Use whatever symbols are
on the machine:

```bash
core=$(mktemp -t crash-XXXXXX.core)
trap 'rm -f "$core"' EXIT
coredumpctl dump <pid> --output="$core"
gdb -q <executable> "$core" -batch -ex 'set debuginfod enabled off' -ex 'thread apply all bt'
```

A core is a verbatim copy of the process's memory and can hold passwords, tokens,
and private documents. Write it to a fresh `mktemp` path rather than a predictable
shared one, and delete it when you are done — never leave it lying in `/tmp`.

For the shell (Quickshell, `/opt/quickshell-taris/bin/qs`), its debug symbols are in a package of
their own: `sudo pacman -Syu --needed quickshell-taris-debug` (from the TarisOS repository), then
symbolize again.

Most other packages here ship without debug symbols. When frames stay unresolved, say so —
never invent function names to fill the gap. An unsymbolized stack still has
shape: which library each frame belongs to, and whether the crash came from a
signal handler, a main loop, or a worker thread.

## Report

1. What crashed, and what it was doing at the time.
2. The most likely mechanism — separating clearly what the evidence **proves**
   from what you are **inferring**.
3. Whether any user data was lost, and where it can be recovered from. Check the
   trash before concluding anything is gone.
4. Whether it is likely to recur, and what would avoid or fix it.

Be straight about the limits of the evidence. If the cause is genuinely
ambiguous, say so rather than assembling confidence out of guesswork.

**Leave the system as you found it.** Diagnosis reads; it does not fix, tidy, or
reconfigure. The one thing to clean up is your own: delete the core you extracted
above, which is a copy of the crashed process's memory.

## If it is a bug in this setup

Most application crashes are upstream bugs in those applications. In the minority
of cases where the cause really does sit in this machine's setup (Taris, its
install scripts, the Hyprland config it ships) or in Apple Silicon support, read
[`reporting.md`](reporting.md) before offering to file anything.
