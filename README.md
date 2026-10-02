# Linux Taskbar Window Count

GNOME Shell extension that shows per-app window counts on taskbar icons for the current workspace by default, scoped to each icon's monitor.

The default badge uses 18px text and sits at bottom-right on horizontal panels
and bottom-left on vertical panels. It works with Ubuntu Dock and Dash to Panel.
The extension metadata declares GNOME Shell 45–50 support; runtime testing was
performed on Ubuntu 24.04.5 LTS with GNOME Shell 46 on X11.

[![Tested on Ubuntu 24.04](https://img.shields.io/badge/tested%20on-Ubuntu%2024.04-E95420?logo=ubuntu&logoColor=white)](https://ubuntu.com/about/release-cycle)
[![GNOME Shell 45–50](https://img.shields.io/badge/GNOME%20Shell-45%E2%80%9350-4A86CF?logo=gnome&logoColor=white)](https://www.gnome.org/)
[![MIT license](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE.md)

## Contents

- [Repository dependencies](#repository-dependencies)
- [Install the extension](#install-the-gnome-shell-window-count-extension)
- [Window-count badge components](#window-count-badge-components)
- [Customize window-count badges at runtime](#customize-window-count-badges-at-runtime)
- [GNOME Shell extension deployment](#gnome-shell-extension-deployment)
- [Extension structure](#extension-structure)
- [Logging](#logging)
- [Tests](#tests)
- [Idempotency](#idempotency)
- [Dependencies](#dependencies)
- [GNOME Shell reload](#gnome-shell-reload)
- [Detect, reconfigure, and uninstall](#detect-reconfigure-and-uninstall)
- [Frequently asked questions](#frequently-asked-questions)
- [License and disclaimer](#license-and-disclaimer)

## Repository dependencies

The extension and installer are self-contained. Component selection, command
handling, and install receipts use the bundled `lib/component_runtime.sh`.
A standalone checkout installs without downloading another repository or
requiring access to a private installer framework.

## Install the GNOME Shell window-count extension

Run this repository's installer from the checkout as the desktop user, with a
running GNOME session. On Ubuntu, install any missing build dependencies first:

```bash
sudo apt install -y -o Dpkg::Options::="--force-confold" cargo python3 libglib2.0-bin
```

The user-level installer itself runs without `sudo`:

```bash
bash install.sh
```

With a terminal, the installer opens a component menu. Without a terminal, it
deploys the extension and all default-on components. To install all default-on
components without prompts, use `bash install.sh --default`.

The broader Ubuntu desktop setup is coordinated by
[installation_scripts](https://github.com/mikaeltorni/installation_scripts),
which invokes this installer for the selected desktop user.

| Command | Behavior |
| --- | --- |
| `bash install.sh` | Open the component menu in a terminal; without a TTY, use default-on components. |
| `bash install.sh --default` | Deploy the extension core and all default-on components without prompts. |
| `bash install.sh --all` | Deploy the extension core and every component without prompts. |
| `bash install.sh --select count_threshold,badge_position` | Deploy the core and only the named components. |
| `bash install.sh --select ""` | Deploy the core while preserving existing badge settings. |
| `bash install.sh --config NAME` | Load the named file from `installation_configs/` for the selection. |
| `bash install.sh --reconfigure badge_position,count_threshold` | Re-apply the named components' configuration. |
| `bash install.sh --uninstall badge_position,count_threshold` | Uninstall the named components. |
| `bash install.sh --auth` | Accept the setup chain's authentication flag; this installer performs no Git downloads. |
| `bash install.sh --list-components` | Print component IDs and labels without deploying. |
| `bash install.sh --list-configurable-components` | Print nested configuration components; empty in this repository. |
| `bash install.sh --list-select-configure-components` | Print configure-on-selection components; empty in this repository. |
| `bash install.sh --list-component-config-values` | Print nested configuration values; empty in this repository. |
| `bash install.sh --configure-component ID` | Report that no nested configuration screen exists, with exit status 2. |
| `bash install.sh --detect` | Print each component's installed or absent state. |
| `bash install.sh --export-selection` | Print the resolved component selection as JSON without deploying or changing settings. |
| `bash install.sh --help` | Show the complete installer usage. |

## Window-count badge components

The installer exposes a component manifest for the desktop setup chain and
provides its own component selection in a standalone checkout. The **core deploy**
(copying the extension, compiling its GSettings schema, and enabling it) always
runs first, so the window-count badge works no matter which components are
selected. Each component below then writes one part of the configuration; all
are **default-on**, so a plain install reproduces the built-in behavior.

| Component id | What it configures | Default | Env override |
|---|---|---|---|
| `badge_position` | Corner the badge sits in | `bottom-right` (bottom-left on vertical panels) | `WWC_BADGE_POSITION` |
| `count_threshold` | Minimum window count to show the badge | `2` | `WWC_COUNT_THRESHOLD` |
| `workspace_scope` | Count current workspace only vs. all workspaces | current only (`false`) | `WWC_COUNT_ALL_WORKSPACES` |
| `badge_appearance` | Badge text/background color and font size | `#ffffff` / `transparent` / `18` | `WWC_BADGE_TEXT_COLOR`, `WWC_BADGE_BACKGROUND_COLOR`, `WWC_BADGE_FONT_SIZE` |

The `bottom-right` setting adapts to the orientation of Dash to Panel, Ubuntu
Dock, and Dash to Dock. Other corner choices retain their literal placement.
The default size increased from 14px to 18px, rounding a 25% increase to the
nearest whole pixel. Font sizes remain configurable from 6px through 64px.

## Customize window-count badges at runtime

Every component setting is also editable live — open the extension's settings in
the GNOME Extensions app (backed by `prefs.js`), or use:

```bash
gnome-extensions prefs workspace-window-count@local
```

For command-line settings, point GSettings at the installed extension's schema:

```bash
WWC_SCHEMA_DIR="$HOME/.local/share/gnome-shell/extensions/workspace-window-count@local/schemas"
gsettings --schemadir "$WWC_SCHEMA_DIR" set org.gnome.shell.extensions.workspace-window-count badge-position 'top-right'
gsettings --schemadir "$WWC_SCHEMA_DIR" set org.gnome.shell.extensions.workspace-window-count count-threshold 1
gsettings --schemadir "$WWC_SCHEMA_DIR" set org.gnome.shell.extensions.workspace-window-count count-all-workspaces true
gsettings --schemadir "$WWC_SCHEMA_DIR" set org.gnome.shell.extensions.workspace-window-count badge-font-size 24
```

Settings apply **live** with no Shell reload. If the GSettings schema is not
available (e.g. it failed to compile), the extension falls back to its built-in
defaults so the badge still works.

## GNOME Shell extension deployment

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
- `badgeLifecycle.js` creates, anchors, restyles, reuses, and destroys badge
  actors. It resolves panel orientation and uses an overlay layer to prevent
  the icon's box layout from collapsing the label.
- `windowDiscovery.js` counts application windows on the icon's monitor
  (current workspace or all workspaces) and discovers app-icon delegates in
  the Shell actor tree.
- `stylesheet.css` defines the default badge presentation; runtime color/size
  settings are applied as an inline style on top of it.
- `prefs.js` renders the GNOME Extensions settings dialog bound to the schema.
- `schemas/org.gnome.shell.extensions.workspace-window-count.gschema.xml`
  declares the customizable keys; the installer compiles it on deploy.
- `installer/components.sh` is the component manifest; `lib/window_count_setup.sh`
  holds the core deploy plus the per-component configuration functions.
- `lib/logging.sh` centralizes Bash installer logging to `.log/install.log`.
- `lib/component_runtime.sh` handles standalone component selection, saved
  configurations, receipt tracking, reconfiguration, and uninstall commands.
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
node --test tests/*.mjs
cargo test --locked
bash tests/test_install.sh
```

The installer test uses an isolated home directory and mocked session commands
to verify complete, repeatable deployment without changing the live desktop.
JavaScript regression tests cover window discovery, monitor and workspace
scope, badge positioning, resizing, and overlay cleanup. Installer checks also
verify the compiled schema's default font size and custom size overrides.

On a fresh Ubuntu 24.04.5 VM, installation and repeated installation succeeded
with the packaged Cargo 1.75. The VM passed 30 JavaScript tests, 8 Rust tests,
and 82 installer checks. Screenshots confirmed 18px badges in both orientations
on Ubuntu Dock and Dash to Panel 74, correct current/all-workspace counts,
threshold changes, and the preferences dialog. Runtime testing used GNOME 46
on X11; other declared Shell versions and Wayland were not exercised in that VM.

## Idempotency

- Existing extension files are overwritten by the same source files.
- GSettings append logic de-duplicates entries and preserves already-enabled
  extensions.
- `--default` reapplies default component settings; use `--select ""` to update
  the extension files while keeping custom settings.
- Missing source directories produce a warning and skip only this feature.

## Dependencies

Installation requires a running GNOME Shell desktop and the target user's
session bus, `gsettings`, Python 3 for configuration and selection JSON, and
Cargo 1.75 or newer to build the bundled Rust helper. `glib-compile-schemas`
(package `libglib2.0-bin`) enables live settings and the preferences dialog.
`Cargo.lock` uses format 3 so Ubuntu 24.04's packaged Cargo 1.75 can read it.
Docker/Podman can build `wwc-tools` when Cargo is unavailable; an existing fresh
helper binary also works without a toolchain. JavaScript tests require Node.js
18 or newer; Node.js is not needed to run the extension.

If `glib-compile-schemas` is missing, the core deploy still completes and the
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
bash install.sh --reconfigure badge_position,count_threshold
bash install.sh --uninstall badge_position,count_threshold
```

The standalone terminal menu lists component IDs and asks which to install or
reconfigure, followed by which to uninstall. Enter accepts the default install
selection or an empty uninstall selection; `q` cancels component selection.
Use comma-separated or space-separated IDs. Detection uses a live check where
deterministic and otherwise an install receipt under
`${XDG_STATE_HOME:-~/.local/state}/isc/receipts/linux_taskbar_window_count/`.

Every knob here uses the receipt rather than a live check on purpose. Each one
writes a settings value that is often identical to the schema default the
extension already ships, so no live probe can tell "the installer applied this
knob" from "the extension shipped that value" — and a probe for the schema
itself would report all four as installed the moment the always-installed
extension core deploys it, which made non-interactive runs skip every knob.
Uninstalling a knob resets its key(s) to the schema default; the extension core
is never removed by a knob's uninstall.

## Frequently asked questions

### Why is the badge hidden when an app has one window?

The default count threshold is two windows. Set `count-threshold` to `1` in the
extension settings to show a badge for a single window.

### Are window counts separated by monitor?

Yes. Each taskbar icon counts that app's windows on the monitor associated with
that icon.

### Can the extension count windows on every workspace?

Yes. Enable **Count all workspaces** in the extension settings, or set
`count-all-workspaces` to `true` with GSettings.

### Which GNOME Shell versions does the extension support?

The extension metadata lists GNOME Shell versions 45 through 50. The project is
tested on Ubuntu 24.04.5 LTS with GNOME Shell 46 on X11.

## License and disclaimer

The project uses the [MIT License](LICENSE.md).

This software is provided under the MIT License on an **“as is”** basis, without warranties of any kind. To the maximum extent permitted by applicable law, the authors and copyright holders shall not be liable for any claims, damages, losses, or other liability arising from the use of this software.

You are solely responsible for determining whether this software is suitable, safe, lawful, and appropriate for your intended use. Unless explicitly stated otherwise, this project is general-purpose software and is not designed, tested, certified, or approved for safety-critical, medical, automotive, aviation, industrial-control, life-support, cybersecurity-critical, financial-critical, or other high-risk use cases.

The authors and copyright holders make no guarantees regarding security, reliability, availability, correctness, compliance, non-infringement, or fitness for any particular purpose.

This notice is intended to clarify the nature of the project and does not impose additional restrictions beyond the MIT License.
