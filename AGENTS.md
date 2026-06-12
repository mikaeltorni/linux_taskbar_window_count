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
