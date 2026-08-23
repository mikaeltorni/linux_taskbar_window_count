# Linux Taskbar Window Count

> Part of [installation_scripts](https://github.com/mikaeltorni/installation_scripts) — the master installer that orchestrates a productivity-focused Ubuntu 24.04 desktop setup (workspaces, hotkeys, window tiling, programming tools, and more). Tested on Ubuntu 24.04.4 LTS.

**Phase 3 of 8** — GNOME taskbar app-icon window-count badges.

This repository owns the `workspace-window-count@local` GNOME Shell extension,
which draws a bottom-right badge on each taskbar app icon showing how many
windows for that app are open on the current workspace.

## Repository dependencies

This repository installs and runs **standalone**. Its only dependency is a
**soft, build-time** one on the shared installer component framework
(`linux_installation_scripts_functions`): the installer resolves it from a
sibling checkout when present and otherwise downloads `component_loader.sh` on
demand, so a fresh checkout installs without any sibling present. The extension
itself has no runtime dependency on any other repository.

See the full cross-repository map in
[installation_scripts/DEPENDENCIES.md](https://github.com/mikaeltorni/installation_scripts/blob/master/DEPENDENCIES.md).

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
bash install.sh                   # interactive component menu (TTY), else defaults
bash install.sh --default         # core + every default-on component, no prompts
bash install.sh --all             # core + every component, no prompts
bash install.sh --select count_threshold,badge_position
bash install.sh --list-components # machine-readable component list (no deploy)
```

## Installable components

The installer follows the shared component framework, so the master installer's
menu shows this repository with a per-feature submenu. The **core deploy**
(copying the extension, compiling its GSettings schema, and enabling it) always
runs first, so the window-count badge works no matter which components are
selected. Each component below then writes one part of the configuration; all
are **default-on**, so a plain install reproduces the built-in behavior.

| Component id | What it configures | Default | Env override |
|---|---|---|---|
| `badge_position` | Corner the badge sits in | `bottom-right` | `WWC_BADGE_POSITION` |
| `count_threshold` | Minimum window count to show the badge | `2` | `WWC_COUNT_THRESHOLD` |
| `workspace_scope` | Count current workspace only vs. all workspaces | current only (`false`) | `WWC_COUNT_ALL_WORKSPACES` |
| `badge_appearance` | Badge text/background color and font size | `#ffffff` / `transparent` / `14` | `WWC_BADGE_TEXT_COLOR`, `WWC_BADGE_BACKGROUND_COLOR`, `WWC_BADGE_FONT_SIZE` |

## Customization at runtime

Every component setting is also editable live — open the extension's settings in
the GNOME Extensions app (backed by `prefs.js`), or set a key directly, e.g.:

```bash
gsettings set org.gnome.shell.extensions.workspace-window-count badge-position 'top-right'
gsettings set org.gnome.shell.extensions.workspace-window-count count-threshold 1
```

Settings apply **live** with no Shell reload. If the GSettings schema is not
available (e.g. it failed to compile), the extension falls back to its built-in
defaults so the badge still works.

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

- `extension.js` owns the GNOME Shell lifecycle, signal connections, refresh
  scheduling, and reads the GSettings schema (with a built-in default fallback)
  to apply position, threshold, scope, and appearance live.
- `badgeLifecycle.js` creates, anchors (any corner), restyles, reuses, and
  destroys badge actors.
- `windowDiscovery.js` counts application windows (current workspace or all) and
  discovers app-icon delegates in the Shell actor tree.
- `stylesheet.css` defines the default badge presentation; runtime color/size
  settings are applied as an inline style on top of it.
- `prefs.js` renders the GNOME Extensions settings dialog bound to the schema.
- `schemas/org.gnome.shell.extensions.workspace-window-count.gschema.xml`
  declares the customizable keys; the installer compiles it on deploy.
- `installer/components.sh` is the component manifest; `lib/window_count_setup.sh`
  holds the core deploy plus the per-component configuration functions.
- `lib/logging.sh` centralizes Bash installer logging to `.log/install.log`.
- `wwc-tools` (Rust, `src/`) parses, de-duplicates, and serializes GSettings
  string-array values for `install.sh`, logging each run to
  `.log/gsettings_strv.log`. The installer builds it via
  `scripts/build_wwc_tools.sh` and invokes it through `lib/wwc_bin.sh`.

## Logging

- The extension emits prefixed, level-tagged lines to the GNOME Shell journal
  (`journalctl --user -o cat /usr/bin/gnome-shell`); verbose/debug output is
  suppressed below the active level so normal runs stay quiet.
- Bash and Rust helpers write timestamped logs under the repository-root
  `.log/` directory (git-ignored runtime artifacts), routed through
  `lib/logging.sh` and `src/logging.rs`.

## Tests

```bash
node --experimental-default-type=module --test tests/*.mjs
cargo test
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

This repo expects `linux_installations_setup` to provide GNOME Shell, `cargo`
(or Docker/Podman as a fallback so `scripts/build_wwc_tools.sh` can compile
`wwc-tools`),
`glib-compile-schemas` (package `libglib2.0-bin`, used to compile the bundled
settings schema), and the target user's session bus before child installers run.
If `glib-compile-schemas` is missing the core deploy still completes and the
extension falls back to its built-in defaults. The extension metadata declares
support for GNOME Shell versions 45 through 50.

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

## Detect, reconfigure, and uninstall

This installer tracks what it has installed and can re-apply or remove it, so you
can refresh configuration after a repo update or cleanly back a feature out.

```bash
bash install.sh --detect            # show each component as installed|absent
bash install.sh --reconfigure a,b   # re-apply (idempotent) these component ids
bash install.sh --uninstall a,b     # uninstall these component ids
```

In the interactive menu (run `bash install.sh` on a terminal, or via the master
installer), already-installed components show a green `✓`. Select one with
**space** to **reconfigure** it (`~`), press **`u`** to mark it for **uninstall**
(`✗`), or press **`r`** to reconfigure every installed component at once. Detection
uses a live check where deterministic and otherwise an install receipt under
`${XDG_STATE_HOME:-~/.local/state}/isc/receipts/`; a component without a reversal
step simply clears that receipt on uninstall.

Every knob here uses the receipt rather than a live check on purpose. Each one
writes a settings value that is often identical to the schema default the
extension already ships, so no live probe can tell "the installer applied this
knob" from "the extension shipped that value" — and a probe for the schema
itself would report all four as installed the moment the always-installed
extension core deploys it, which made non-interactive runs skip every knob.
Uninstalling a knob resets its key(s) to the schema default; the extension core
is never removed by a knob's uninstall.

## Disclaimer

This software is provided under the MIT License on an **“as is”** basis, without warranties of any kind. To the maximum extent permitted by applicable law, the authors and copyright holders shall not be liable for any claims, damages, losses, or other liability arising from the use of this software.

You are solely responsible for determining whether this software is suitable, safe, lawful, and appropriate for your intended use. Unless explicitly stated otherwise, this project is general-purpose software and is not designed, tested, certified, or approved for safety-critical, medical, automotive, aviation, industrial-control, life-support, cybersecurity-critical, financial-critical, or other high-risk use cases.

The authors and copyright holders make no guarantees regarding security, reliability, availability, correctness, compliance, non-infringement, or fitness for any particular purpose.

This notice is intended to clarify the nature of the project and does not impose additional restrictions beyond the MIT License.
