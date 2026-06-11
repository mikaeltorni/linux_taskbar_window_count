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

## Reloading GNOME Shell

When a change needs GNOME Shell to reload (extensions, themes, shell-side
configuration), reload it in place — never log the user out or terminate the
session.

- X11 session: run
  `busctl --user call org.gnome.Shell /org/gnome/Shell org.gnome.Shell Eval s 'Meta.restart("Restarting…")'`
  (equivalent to pressing Alt+F2 → `r`). This restarts GNOME Shell while
  preserving open windows and applications.
- Wayland session: there is no in-place reload. Ask the user to log out and back
  in themselves. Do NOT initiate it.

Never use any of the following to force changes through, regardless of session
type:

- `gnome-session-quit` / `--logout` / `--force`
- `loginctl terminate-session …` / `loginctl kill-user …`
- `systemctl --user stop gnome-session*` or similar unit stops
- `pkill -HUP gnome-shell`, `killall gnome-shell`, or any signal that ends the
  shell process on Wayland

Losing the user's open work is a worse outcome than waiting for them to reload
manually.
