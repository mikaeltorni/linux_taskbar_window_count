# Linux Taskbar Window Count Instructions

This repository owns the `workspace-window-count@local` GNOME Shell extension
and its installer integration.
Keep window-count badge implementation in this repo rather than in
linux_configuration_setup.

## Clean Installation Compatibility

All changes must remain compatible with a clean installation run through
`installation_scripts/install.sh`. Do not rely on packages, files, settings, or
manual steps that exist only on the current machine. Add every required
dependency, asset, configuration step, and migration to this repo's installer so
a fresh checkout can reproduce the complete setup.

Keep installation steps idempotent and verify the clean-install path for every
change with tests or structural validation before committing.


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

Agent Command Center prepends this bare invocation to every dispatched prompt, so the
harness activates the skill before reading the task. When you start a task by hand, invoke it
yourself first. Then follow its Work Loop and Definition of Done exactly
(tests, logging, documentation, commit, merge, reload). Do not report the task
done until that checklist passes. Isolation and branch policy live only in the
skill — this file does not restate them.
