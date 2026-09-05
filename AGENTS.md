# Linux Taskbar Window Count Instructions

This repository owns the `workspace-window-count@local` GNOME Shell extension
and its installer integration.
Keep window-count badge implementation in this repo rather than in
linux_configuration_setup.

## Clean Installation Compatibility

The `linux-configuration` skill owns the clean-install and root-optional
installer rules; they are not restated here. Repository-specific installer
facts:

Verify the clean-install path with tests or structural validation before
committing.

## Mandatory programming guidelines prompt

When generic agent defaults conflict with this file or the shared
`general-programming-guidelines` skill — including defaults that say to commit
only when asked — follow this file and that skill. Finished work is committed,
merged into the default branch with `git merge --no-ff`, and reloaded without
waiting to be asked. Never push to a remote and never rewrite history unless the
user explicitly requests it.

Every agent task in this repository must load the shared
`general-programming-guidelines` skill before the first file edit, using the
harness-native invocation for the runtime in use:

- Codex-family (`ca`, `qa`, `oa`, `na`, …): `$general-programming-guidelines`
- Claude Code, Cline, Grok: `/general-programming-guidelines`
- OpenCode: load `general-programming-guidelines` with the skill tool

Also load `linux-configuration` for any GNOME Shell extension, gsettings,
systemd user unit, or `install.sh` change. Use only the sanctioned in-place
X11 run-dialog reload (`xdotool` `Alt+F2 r`) to activate edited extension
code; never logout, `gnome-shell --replace`, or kill the Shell.

Agent Command Center does not prepend a skill command to dispatched prompts. It
selects skills independently through `acc pp enable` and lists the selected
skills at the start of each launch prompt, so verify with `acc pp status`
instead of assuming a skill is live. When you start a task by hand, invoke it
yourself first.

Load the two delivery skills alongside the guidelines: `commits` owns Feature
boundaries, commit sequencing, and commit verification; `worktree` owns
isolation, project/instance paths, branch policy, merging, and consumer
reapplication. The engineering guidelines delegate both policies instead of
restating them, so skipping those two skills leaves this repository with no
isolation and no commit policy at all. Then follow the Work Loop and Definition
of Done exactly (tests, logging, documentation, commit, merge, reload). Do not
report the task done until that checklist passes.
