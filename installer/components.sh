#!/usr/bin/env bash
# components.sh - Component manifest for linux_taskbar_window_count.
#
# install.sh deploys the extension core (install_window_count_extension)
# unconditionally so the window-count badge always works, then routes execution
# through component_main from the shared component runtime. Each component below
# writes one (or a few related) gsettings key(s) on the bundled schema, so every
# customizable behavior is selectable and fully editable without touching the
# extension source. All components are default-on: a plain install reproduces the
# extension's built-in behavior (badge in the bottom-right, shown at 2+ windows,
# counting the current workspace, white-on-transparent at 14px).
#
# Entry format: "id|label|default(on/off)|function". The functions are defined
# in lib/window_count_setup.sh, sourced by install.sh before this manifest.

ISC_REPO_NAME="linux_taskbar_window_count"
ISC_REPO_LABEL="Taskbar window-count badges"

ISC_COMPONENTS=(
  "badge_position|Badge corner on each app icon (default bottom-right)|on|wwc_configure_position"
  "count_threshold|Minimum window count to show the badge (default 2)|on|wwc_configure_threshold"
  "workspace_scope|Count current workspace only vs. all workspaces|on|wwc_configure_workspace_scope"
  "badge_appearance|Badge colors and font size|on|wwc_configure_appearance"
)
