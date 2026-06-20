# Linux Taskbar Window Count

> Part of [installation_scripts](https://github.com/mikaeltorni/installation_scripts) — the master installer that orchestrates a productivity-focused Ubuntu 24.04 desktop setup (workspaces, hotkeys, window tiling, programming tools, and more). Tested on Ubuntu 24.04.4 LTS.

**Phase 3 of 8** — GNOME taskbar app-icon window-count badges.

This repository owns the `workspace-window-count@local` GNOME Shell extension,
which draws a bottom-right badge on each taskbar app icon showing how many
windows for that app are open on the current workspace.

## Installation

Run the main setup installer:

```bash
sudo bash install.sh
```

The master installer in `installation_scripts/install.sh` clones this repository,
runs its `install.sh`, copies the extension into the target user's GNOME
extensions directory, and enables it idempotently through GSettings.
The old `linux_configuration_setup` deployment path is now delegated to this repo.

You can also deploy this repo directly while testing from its checkout:

```bash
sudo bash install.sh
```

## Deployment

The installer deploys extension files from `workspace-window-count@local/` to:

```text
$TARGET_HOME/.local/share/gnome-shell/extensions/workspace-window-count@local
```

It then appends `workspace-window-count@local` to:

```text
org.gnome.shell enabled-extensions
```

## Extension structure

- `extension.js` owns the GNOME Shell lifecycle, signal connections, and
  refresh scheduling.
- `badgeLifecycle.js` creates, positions, reuses, and destroys badge actors.
- `windowDiscovery.js` counts application windows and discovers app-icon
  delegates in the Shell actor tree.
- `stylesheet.css` defines the badge presentation.
- `lib/gsettings_strv.py` parses, de-duplicates, and serializes GSettings
  string-array values for `install.sh`, logging each run to
  `.log/gsettings_strv.log`.

## Logging

- The installer helper writes timestamped logs under the repository-root
  `.log/` directory (git-ignored runtime artifacts).

## Tests

```bash
node --experimental-default-type=module --test tests/*.mjs
python3 -m pytest tests/test_gsettings_strv.py
bash tests/test_install.sh
```

The installer test uses an isolated home directory and mocked session commands
to verify complete, repeatable deployment without changing the live desktop.

## Idempotency

- Existing extension files are overwritten by the same source files.
- GSettings append logic de-duplicates entries and preserves already-enabled
  extensions.
- Missing source directories produce a warning and skip only this feature.

## Dependencies

This repo expects `linux_installations_setup` to provide GNOME Shell, `python3`,
and the target user's session bus before child installers run. The extension
metadata declares support for GNOME Shell versions 45 through 50.

## GNOME Shell reload

A reload is only needed when this extension's **code** changes; the running
Shell caches each extension's JS for its process lifetime, so the new code is
not picked up otherwise. (Changing the extension's own GSettings keys, by
contrast, applies live with no reload.) There is no non-disruptive
command-line hot-reload for edited extension source — `gnome-extensions
disable/enable` re-runs only the cached module, and the `Eval` /
`Meta.restart()` D-Bus path is locked down on GNOME 45+.

- X11 session: restart GNOME Shell in place with `Alt+F2` → type `r` → Enter
  (windows and applications are preserved).
- Wayland session: there is no in-place reload. Ask the user to log out and back
  in themselves; do not terminate GNOME Shell or the desktop session.

## Disclaimer

This software is provided under the MIT License on an **“as is”** basis, without warranties of any kind. To the maximum extent permitted by applicable law, the authors and copyright holders shall not be liable for any claims, damages, losses, or other liability arising from the use of this software.

You are solely responsible for determining whether this software is suitable, safe, lawful, and appropriate for your intended use. Unless explicitly stated otherwise, this project is general-purpose software and is not designed, tested, certified, or approved for safety-critical, medical, automotive, aviation, industrial-control, life-support, cybersecurity-critical, financial-critical, or other high-risk use cases.

The authors and copyright holders make no guarantees regarding security, reliability, availability, correctness, compliance, non-infringement, or fitness for any particular purpose.

This notice is intended to clarify the nature of the project and does not impose additional restrictions beyond the MIT License.
