import St from 'gi://St';
import GLib from 'gi://GLib';
import Shell from 'gi://Shell';
import Clutter from 'gi://Clutter';
import { Extension } from 'resource:///org/gnome/shell/extensions/extension.js';

// extension.js — workspace-window-count@local
//
// Draws a small badge in the BOTTOM-RIGHT corner of every taskbar app icon
// (e.g. Dash to Panel) showing how many windows of that app are open on the
// CURRENT workspace. Bottom-right is deliberately chosen so the badge never
// overlaps notification counters, which live in the top-right corner.
//
// Components:
//   - log()                          Centralized, level-aware logging helper.
//   - countWindowsOnActiveWorkspace  Counts an app's windows on the active workspace.
//   - isAppIconDelegate              Duck-types a taskbar app-icon delegate.
//   - iterAppIconDelegates           Walks the actor tree yielding app-icon delegates.
//   - WorkspaceWindowCountExtension  Extension lifecycle + badge management.

const BADGE_KEY = '_wwcBadge';
const REFRESH_DEBOUNCE_MS = 120;
const LOG_PREFIX = '[workspace-window-count]';

// Ordered log levels. Everything at or above ACTIVE_LOG_LEVEL is emitted; lower
// (more verbose) levels are suppressed so production logs stay quiet by default.
const LOG_LEVELS = { verbose: 0, debug: 1, info: 2, warn: 3, error: 4 };
const ACTIVE_LOG_LEVEL = LOG_LEVELS.info;

/**
 * Centralized logging helper for the extension.
 *
 * Emits a single, prefixed, level-tagged line to the GNOME Shell journal
 * (viewable via `journalctl --user -o cat /usr/bin/gnome-shell`). Messages below
 * ACTIVE_LOG_LEVEL are dropped so verbose/debug output can be left in the code
 * without spamming the journal in normal use.
 *
 * @param {('verbose'|'debug'|'info'|'warn'|'error')} level - Severity of the message.
 * @param {string} message - Human-readable, searchable log message.
 * @returns {void} Nothing; performs a side-effecting write to the journal.
 */
function log(level, message) {
  const levelValue = LOG_LEVELS[level] ?? LOG_LEVELS.info;
  if (levelValue < ACTIVE_LOG_LEVEL) {
    return;
  }
  const line = `${LOG_PREFIX} [${level}] ${message}`;
  if (level === 'error') {
    console.error(line);
  } else if (level === 'warn') {
    console.warn(line);
  } else {
    console.log(line);
  }
}

/**
 * Count windows of `app` that live on the active workspace.
 *
 * Windows that are sticky / on all workspaces are counted on every workspace
 * (get_workspace() returns the active one for them). skip_taskbar windows are
 * ignored so the badge matches what the taskbar actually represents.
 *
 * @param {Shell.App} app - The taskbar application whose windows are counted.
 * @returns {number} The number of taskbar-visible windows of `app` on the
 *   currently active workspace.
 */
function countWindowsOnActiveWorkspace(app) {
  const activeWs = global.workspace_manager.get_active_workspace();
  let count = 0;
  for (const win of app.get_windows()) {
    if (win.skip_taskbar) {
      continue;
    }
    if (win.is_on_all_workspaces() || win.get_workspace() === activeWs) {
      count += 1;
    }
  }
  return count;
}

/**
 * Determine whether an actor's delegate is a taskbar app-icon delegate.
 *
 * A taskbar app icon delegate exposes a Shell.App via `.app` and a host actor
 * via `.icon`. We use these duck-typed properties so the extension works with
 * Dash to Panel, the stock dash, and any taskbar built on the same primitives.
 *
 * @param {object} delegate - Candidate `actor._delegate` object (may be null/undefined).
 * @returns {boolean} True if `delegate` looks like an app-icon delegate.
 */
function isAppIconDelegate(delegate) {
  return !!(
    delegate &&
    delegate.app instanceof Shell.App &&
    delegate.icon instanceof Clutter.Actor
  );
}

/**
 * Recursively walk an actor subtree yielding every app-icon delegate found.
 *
 * @param {Clutter.Actor} actor - Root actor to start the depth-first walk from.
 * @yields {object} Each `actor._delegate` that passes {@link isAppIconDelegate}.
 * @returns {Generator<object>} A generator over the matching delegates.
 */
function* iterAppIconDelegates(actor) {
  const delegate = actor._delegate;
  if (isAppIconDelegate(delegate)) {
    yield delegate;
  }
  for (const child of actor.get_children()) {
    yield* iterAppIconDelegates(child);
  }
}

/**
 * GNOME Shell extension that renders per-app, per-workspace window-count badges
 * on taskbar icons. Owns all signal connections, the debounce timer, and the
 * lifecycle of every badge actor it creates.
 */
export default class WorkspaceWindowCountExtension extends Extension {
  /**
   * Activate the extension: initialize state, subscribe to workspace/window
   * signals, begin tracking existing windows, and schedule the first refresh.
   *
   * @returns {void}
   */
  enable() {
    log('info', 'Enabling extension');
    this._badges = new Set();
    this._signals = [];
    this._windowSignals = new Map();
    this._refreshTimeout = 0;

    const wm = global.workspace_manager;
    const display = global.display;

    this._connect(wm, 'active-workspace-changed', () => this._queueRefresh());
    this._connect(wm, 'workspace-added', () => this._queueRefresh());
    this._connect(wm, 'workspace-removed', () => this._queueRefresh());
    this._connect(display, 'window-created', (_d, win) => {
      this._trackWindow(win);
      this._queueRefresh();
    });
    this._connect(display, 'restacked', () => this._queueRefresh());

    let tracked = 0;
    for (const actor of global.get_window_actors()) {
      if (actor.meta_window) {
        this._trackWindow(actor.meta_window);
        tracked += 1;
      }
    }
    log('debug', `Tracking ${tracked} pre-existing window(s)`);

    this._queueRefresh();
    log('info', 'Extension enabled');
  }

  /**
   * Deactivate the extension: cancel pending work, disconnect every signal, and
   * destroy all badges so no actors or handlers leak after disable.
   *
   * @returns {void}
   */
  disable() {
    log('info', 'Disabling extension');
    if (this._refreshTimeout) {
      GLib.source_remove(this._refreshTimeout);
      this._refreshTimeout = 0;
    }
    for (const [obj, id] of this._signals) {
      obj.disconnect(id);
    }
    this._signals = [];
    for (const [win, ids] of this._windowSignals) {
      for (const id of ids) {
        win.disconnect(id);
      }
    }
    this._windowSignals.clear();
    const badgeCount = this._badges.size;
    for (const badge of this._badges) {
      this._destroyBadge(badge);
    }
    this._badges.clear();
    log('debug', `Destroyed ${badgeCount} badge(s) during disable`);
    log('info', 'Extension disabled');
  }

  /**
   * Connect a signal handler and record it for cleanup in {@link disable}.
   *
   * @param {GObject.Object} obj - The object emitting the signal.
   * @param {string} signal - Signal name to connect to.
   * @param {Function} cb - Callback invoked when the signal fires.
   * @returns {void}
   */
  _connect(obj, signal, cb) {
    this._signals.push([obj, obj.connect(signal, cb)]);
  }

  /**
   * Start tracking a window so workspace moves and closing trigger a refresh.
   *
   * No-op if the window is already tracked. On `unmanaged` the window's own
   * handlers are disconnected and it is removed from the tracking map.
   *
   * @param {Meta.Window} win - The window to observe.
   * @returns {void}
   */
  _trackWindow(win) {
    if (this._windowSignals.has(win)) {
      return;
    }
    const ids = [
      win.connect('workspace-changed', () => this._queueRefresh()),
      win.connect('unmanaged', () => {
        const stored = this._windowSignals.get(win);
        if (stored) {
          for (const id of stored) {
            win.disconnect(id);
          }
          this._windowSignals.delete(win);
        }
        this._queueRefresh();
      }),
    ];
    this._windowSignals.set(win, ids);
  }

  /**
   * Coalesce rapid events into a single deferred {@link _refresh}.
   *
   * If a refresh is already scheduled this is a no-op, so bursts of signals
   * (e.g. during workspace switches) result in just one badge update after
   * REFRESH_DEBOUNCE_MS.
   *
   * @returns {void}
   */
  _queueRefresh() {
    if (this._refreshTimeout) {
      return;
    }
    this._refreshTimeout = GLib.timeout_add(
      GLib.PRIORITY_DEFAULT,
      REFRESH_DEBOUNCE_MS,
      () => {
        this._refreshTimeout = 0;
        this._refresh();
        return GLib.SOURCE_REMOVE;
      }
    );
  }

  /**
   * Recompute and apply badge text/visibility for every taskbar app icon, then
   * destroy badges whose host icons have disappeared (taskbar rebuilt the actor).
   *
   * Wrapped in try/catch because it runs from a GLib timeout where an uncaught
   * exception would otherwise be swallowed and stop future refreshes silently.
   *
   * @returns {void}
   */
  _refresh() {
    try {
      const seen = new Set();
      for (const delegate of iterAppIconDelegates(global.stage)) {
        const badge = this._ensureBadge(delegate);
        if (!badge) {
          continue;
        }
        seen.add(badge);
        const count = countWindowsOnActiveWorkspace(delegate.app);
        badge.text = count > 1 ? String(count) : '';
        badge.visible = count > 1;
      }
      // Drop badges whose icons disappeared (taskbar rebuilt the actor).
      for (const badge of [...this._badges]) {
        if (!seen.has(badge)) {
          this._destroyBadge(badge);
          this._badges.delete(badge);
        }
      }
    } catch (e) {
      log('error', `Refresh failed: ${e}`);
    }
  }

  /**
   * Return the badge for a delegate, creating, attaching, and positioning a new
   * St.Label badge on the delegate's icon actor if one does not already exist.
   *
   * The badge tracks its icon's size changes to stay anchored in the bottom-right
   * corner and self-destructs when the icon actor is destroyed.
   *
   * @param {object} delegate - An app-icon delegate (see {@link isAppIconDelegate}).
   * @returns {St.Label} The existing or newly created badge label.
   */
  _ensureBadge(delegate) {
    const existing = delegate[BADGE_KEY];
    if (existing && this._badges.has(existing)) {
      return existing;
    }

    const iconActor = delegate.icon;
    const badge = new St.Label({
      style_class: 'wwc-badge',
      text: '',
      visible: false,
    });
    badge.clutter_text.set_line_wrap(false);
    iconActor.add_child(badge);

    // Nudge a few pixels past the icon's right edge so the trailing digit's
    // glyph + drop shadow don't get clipped by the icon actor's bounds.
    const RIGHT_NUDGE_PX = 4;
    const reposition = () => {
      const w = iconActor.width;
      const h = iconActor.height;
      badge.set_position(
        Math.max(0, w - badge.width + RIGHT_NUDGE_PX),
        Math.max(0, h - badge.height)
      );
    };
    const sizeSignals = [
      iconActor.connect('notify::width', reposition),
      iconActor.connect('notify::height', reposition),
      badge.connect('notify::width', reposition),
      badge.connect('notify::height', reposition),
    ];
    const destroyId = iconActor.connect('destroy', () => {
      this._destroyBadge(badge);
      this._badges.delete(badge);
    });

    badge._wwcIconActor = iconActor;
    badge._wwcDelegate = delegate;
    badge._wwcSignals = sizeSignals;
    badge._wwcDestroyId = destroyId;
    delegate[BADGE_KEY] = badge;
    this._badges.add(badge);
    reposition();
    log('verbose', `Created badge for ${delegate.app?.get_id?.() ?? 'unknown app'}`);
    return badge;
  }

  /**
   * Tear down a badge: disconnect its size/destroy handlers, clear the back-
   * reference on its delegate, and destroy the underlying actor.
   *
   * Safe to call regardless of whether the badge is still registered in
   * `this._badges`; callers are responsible for removing it from that set.
   *
   * @param {St.Label} badge - The badge created by {@link _ensureBadge}.
   * @returns {void}
   */
  _destroyBadge(badge) {
    const iconActor = badge._wwcIconActor;
    if (iconActor) {
      for (const id of badge._wwcSignals || []) {
        iconActor.disconnect(id);
      }
      if (badge._wwcDestroyId) {
        iconActor.disconnect(badge._wwcDestroyId);
      }
    }
    if (badge._wwcDelegate && badge._wwcDelegate[BADGE_KEY] === badge) {
      delete badge._wwcDelegate[BADGE_KEY];
    }
    badge.destroy();
  }
}
