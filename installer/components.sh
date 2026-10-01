#!/usr/bin/env bash
# components.sh - Component manifest for linux_taskbar_window_count.
#
# install.sh deploys the extension core (install_window_count_extension)
# unconditionally so the window-count badge always works, then routes execution
# through component_main from this repository's local runtime. Each component below
# writes one (or a few related) gsettings key(s) on the bundled schema, so every
# customizable behavior is selectable and fully editable without touching the
# extension source. All components are default-on: a plain install reproduces the
# extension's built-in behavior (badge in the bottom-right, shown at 2+ windows,
# counting the current workspace, white-on-transparent at 18px).
#
# Entry format: "id|label|default(on/off)|function[|detect_fn[|uninstall_fn]]".
# The functions are defined in lib/window_count_setup.sh, sourced by install.sh
# before this manifest. The knobs deliberately declare no detect function: each
# one writes a settings value (often equal to the schema default), so there is
# no live probe that can tell "this installer applied the knob" from "the
# extension shipped that default". The runtime therefore falls back to the
# install receipt, which answers exactly that question — and, unlike a
# schema-presence probe, does not report every knob as installed the moment the
# always-installed extension core deploys its schema (which silently skipped all
# four knobs on every non-interactive run). uninstall_* resets the knob's key(s)
# to the schema default.

ISC_REPO_NAME="linux_taskbar_window_count"
ISC_REPO_LABEL="Taskbar window-count badges"

ISC_COMPONENTS=(
  "badge_position|Badge corner on each app icon (default bottom-right)|on|wwc_configure_position||uninstall_wwc_position"
  "count_threshold|Minimum window count to show the badge (default 2)|on|wwc_configure_threshold||uninstall_wwc_threshold"
  "workspace_scope|Count current workspace only vs. all workspaces|on|wwc_configure_workspace_scope||uninstall_wwc_workspace_scope"
  "badge_appearance|Badge colors and font size|on|wwc_configure_appearance||uninstall_wwc_appearance"
)
