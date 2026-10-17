# Reporting a Bug Upstream

Read this only after concluding that a crash, or any other problem, is genuinely a bug in this
setup or in Apple Silicon support.

## Whose bug is it?

Be strict here. A crash or bug inside a third-party application — a file manager, a browser, a
GNOME or Qt library — is almost always an upstream bug in **that** project.

- **TarisOS** (https://github.com/TarisOS/tarisOS): the Taris shell, its
  `taris-qs` Quickshell build, the greeter and setup screen, the Hyprland config, and every
  package from the `taris` repository (`pacman -Sl taris` lists them).
- **Asahi Linux** (https://github.com/AsahiLinux): the kernel, GPU driver and other Apple
  Silicon hardware support.
- **Arch Linux ARM** (https://archlinuxarm.org/): how a repository package was built.

A crash or bug in a program this setup merely installs is **not** its bug unless the way it is
built or configured here is implicated.

If it belongs to none of these, say so and stop. Suggesting the right upstream project is
useful; filing there yourself is not part of this.

## Three conditions, all required

1. **It is a verified bug**, established on evidence. Issues are for verified bugs only.
2. **The user has explicitly agreed.** Show them the exact title and body you propose,
   and wait for a yes. Never file unprompted.
3. **The machine can file it** — `gh auth status` must succeed. If `gh` is missing or
   unauthenticated, do not install or authenticate it. Say so, and hand the user the
   finished text to submit themselves.

## Search before filing

A duplicate issue costs the project more time than no report at all.

```bash
gh search issues --repo <owner/repo> "<program> crash"
gh issue list --repo <owner/repo> --state all --search "<signal> <program>"
```

Search on the program, and for a crash the signal and distinctive symbols from the backtrace;
for another bug, its error messages and what it does wrong.
`gh search issues` accepts only `open` or `closed` for `--state`; leaving it off searches
both. Include **closed** issues: a matching issue closed as fixed, when the problem still
reproduces, is a regression worth reporting.

## Adding to an existing report

Read a plausible match properly first (`gh issue view <number> --repo <owner/repo> --comments`)
and confirm it is genuinely the same failure. If it is, add to it — but only with something
the thread does not already contain: a different reproduction, a symbolized stack, a narrower
trigger, a version where it regressed. A comment that only says it happens to you too is noise.

## Filing a new issue

Only when the search turns up nothing that matches:

```bash
gh issue create --repo <owner/repo> --title "..." --body "..."
```

Include what happened, what was expected, steps to reproduce, and system details:
`uname -r`, `hyprctl version`, `pacman -Q hyprland taris-shell quickshell-taris taris-cli`,
the Mac model, and for a crash the relevant `coredumpctl info` output. `gh` cannot attach media:
save a screenshot and give the user the path to drag into the web form.

## Signing

End the issue or comment with a line naming the model and agent harness that produced it:

> Filed by \<model name\> via \<agent harness\>.

Use your actual model and harness names. If you are not certain of them, say so plainly
rather than inventing a version string.
