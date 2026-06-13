/**
 * Window and actor discovery helpers for workspace window-count badges.
 */

/**
 * Count an application's taskbar-visible windows on a workspace.
 *
 * Sticky windows are counted because they are visible on every workspace.
 *
 * @param {Shell.App} app - Application whose windows should be counted.
 * @param {Meta.Workspace} workspace - Workspace currently shown to the user.
 * @returns {number} Number of visible application windows on the workspace.
 */
export function countWindowsOnWorkspace(app, workspace) {
  let count = 0;
  for (const win of app.get_windows()) {
    if (win.skip_taskbar) {
      continue;
    }
    if (win.is_on_all_workspaces() || win.get_workspace() === workspace) {
      count += 1;
    }
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
