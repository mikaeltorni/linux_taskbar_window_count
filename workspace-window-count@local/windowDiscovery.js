/**
 * Window and actor discovery helpers for workspace window-count badges.
 *
 * Counting is per monitor: each taskbar icon's badge is the number of that
 * app's taskbar-visible windows on the same monitor as the icon, not the
 * combined total across every monitor of the workspace.
 */

/**
 * Meta.Display signals that must trigger a badge refresh. Monitor enter/leave
 * are required so a window dragged between monitors updates both badges
 * without a workspace change.
 */
export const DISPLAY_WINDOW_REFRESH_SIGNALS = Object.freeze([
  'window-created',
  'restacked',
  'window-entered-monitor',
  'window-left-monitor',
]);

/**
 * Return whether a window currently belongs on the given monitor.
 *
 * {@link Meta.Window.get_monitor} is `-1` during workspace-switch animations;
 * those windows are omitted rather than used as an index. When
 * {@link monitorIndex} is null or undefined the monitor filter is skipped so
 * callers that have not yet resolved an icon monitor keep workspace-only
 * counting.
 *
 * @param {Meta.Window} win - Window to test.
 * @param {number|null|undefined} monitorIndex - Target monitor, or omit to skip.
 * @returns {boolean} Whether the window should be included for that monitor.
 */
export function windowBelongsOnMonitor(win, monitorIndex) {
  if (monitorIndex === null || monitorIndex === undefined) {
    return true;
  }
  if (typeof monitorIndex !== 'number' || !Number.isInteger(monitorIndex) || monitorIndex < 0) {
    return false;
  }
  const monitor =
    typeof win.get_monitor === 'function' ? win.get_monitor() : -1;
  if (typeof monitor !== 'number' || !Number.isInteger(monitor) || monitor < 0) {
    return false;
  }
  return monitor === monitorIndex;
}

/**
 * Read a non-negative integer monitor index from a candidate value.
 *
 * @param {unknown} value - Raw index from a panel, delegate, or similar.
 * @returns {number|null} The index, or null when it is missing or invalid.
 */
function readNonNegativeInt(value) {
  if (typeof value !== 'number' || !Number.isInteger(value) || value < 0) {
    return null;
  }
  return value;
}

/**
 * Resolve which monitor a taskbar app-icon belongs to.
 *
 * Prefers Dash to Panel's stored panel monitor index, then a numeric
 * `monitorIndex` / `_monitorIndex` on the delegate (Ubuntu Dock and overview
 * clones). Falls back to comparing the icon actor's transformed position with
 * {@link Meta.Display.get_monitor_geometry}. Returns null when the monitor
 * cannot be determined; callers must not treat that as "every monitor".
 *
 * @param {object} delegate - App-icon delegate that owns the icon actor.
 * @param {Meta.Display} display - Display used for monitor geometry fallback.
 * @returns {number|null} Zero-based monitor index, or null when unresolved.
 */
export function resolveIconMonitorIndex(delegate, display) {
  const panelIndex = readNonNegativeInt(delegate?._dtpPanel?.monitor?.index);
  if (panelIndex !== null) {
    return panelIndex;
  }
  const namedIndex =
    readNonNegativeInt(delegate?.monitorIndex) ??
    readNonNegativeInt(delegate?._monitorIndex);
  if (namedIndex !== null) {
    return namedIndex;
  }
  return monitorIndexFromActorGeometry(delegate?.icon, display);
}

/**
 * Map an actor's stage position onto a display monitor.
 *
 * @param {Clutter.Actor|undefined} actor - Icon actor to locate.
 * @param {Meta.Display|undefined} display - Display providing monitor geometries.
 * @returns {number|null} Matching monitor index, or null when unknown.
 */
function monitorIndexFromActorGeometry(actor, display) {
  if (!actor || !display || typeof display.get_n_monitors !== 'function') {
    return null;
  }
  let x;
  let y;
  try {
    if (typeof actor.get_transformed_position !== 'function') {
      return null;
    }
    const position = actor.get_transformed_position();
    x = position?.[0];
    y = position?.[1];
  } catch {
    return null;
  }
  if (typeof x !== 'number' || typeof y !== 'number') {
    return null;
  }
  const nMonitors = display.get_n_monitors();
  if (typeof nMonitors !== 'number' || nMonitors <= 0) {
    return null;
  }
  for (let index = 0; index < nMonitors; index += 1) {
    const geom = display.get_monitor_geometry(index);
    if (
      geom &&
      typeof geom.x === 'number' &&
      typeof geom.y === 'number' &&
      typeof geom.width === 'number' &&
      typeof geom.height === 'number' &&
      x >= geom.x &&
      y >= geom.y &&
      x < geom.x + geom.width &&
      y < geom.y + geom.height
    ) {
      return index;
    }
  }
  return null;
}

/**
 * Count an application's taskbar-visible windows on a workspace and monitor.
 *
 * Sticky windows are counted because they are visible on every workspace, but
 * only when they also sit on {@link monitorIndex}. When {@link allWorkspaces}
 * is true the workspace filter is dropped; the monitor filter still applies.
 * Windows with {@link Meta.Window.get_monitor} equal to `-1` are omitted.
 *
 * @param {Shell.App} app - Application whose windows should be counted.
 * @param {Meta.Workspace} workspace - Workspace currently shown to the user.
 * @param {boolean} [allWorkspaces=false] - Count across all workspaces when true.
 * @param {number|null} [monitorIndex=null] - Limit to this monitor; omit to skip.
 * @returns {number} Number of visible application windows in scope.
 */
export function countWindowsOnWorkspace(
  app,
  workspace,
  allWorkspaces = false,
  monitorIndex = null
) {
  let count = 0;
  for (const win of app.get_windows()) {
    if (win.skip_taskbar) {
      continue;
    }
    if (
      !(
        allWorkspaces ||
        win.is_on_all_workspaces() ||
        win.get_workspace() === workspace
      )
    ) {
      continue;
    }
    if (!windowBelongsOnMonitor(win, monitorIndex)) {
      continue;
    }
    count += 1;
  }
  return count;
}

/**
 * Determine whether a value looks like a taskbar app-icon delegate.
 *
 * Constructor dependencies are supplied by the extension so this module remains
 * testable outside a live GNOME Shell process.
 *
 * @param {object} delegate - Candidate actor delegate.
 * @param {Function} appType - Shell.App constructor.
 * @param {Function} actorType - Clutter.Actor constructor.
 * @returns {boolean} Whether the delegate owns the expected app and icon types.
 */
export function isAppIconDelegate(delegate, appType, actorType) {
  return !!(
    delegate &&
    delegate.app instanceof appType &&
    delegate.icon instanceof actorType
  );
}

/**
 * Walk an actor subtree depth-first and yield matching app-icon delegates.
 *
 * @param {Clutter.Actor} actor - Root actor for the traversal.
 * @param {Function} isDelegate - Predicate used to recognize app-icon delegates.
 * @yields {object} Each matching actor delegate.
 * @returns {Generator<object>} Matching delegates in depth-first order.
 */
export function* iterAppIconDelegates(actor, isDelegate) {
  const delegate = actor._delegate;
  if (isDelegate(delegate)) {
    yield delegate;
  }
  for (const child of actor.get_children()) {
    yield* iterAppIconDelegates(child, isDelegate);
  }
}
