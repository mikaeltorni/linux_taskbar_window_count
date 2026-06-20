import St from 'gi://St';
import GLib from 'gi://GLib';
import Shell from 'gi://Shell';
import Clutter from 'gi://Clutter';
import { Extension } from 'resource:///org/gnome/shell/extensions/extension.js';
import {
  countWindowsOnWorkspace,
  isAppIconDelegate,
  iterAppIconDelegates,
} from './windowDiscovery.js';
import { destroyBadge, ensureBadge } from './badgeLifecycle.js';

// extension.js — workspace-window-count@local
//
// Draws a small badge in the BOTTOM-RIGHT corner of every taskbar app icon
// (e.g. Dash to Panel) showing how many windows of that app are open on the
// CURRENT workspace. Bottom-right is deliberately chosen so the badge never
// overlaps notification counters, which live in the top-right corner.
//
// Components:
//   - log()                          Centralized, level-aware logging helper.
//   - badgeLifecycle.js              Creates, positions, and destroys badge actors.
//   - windowDiscovery.js             Counts windows and discovers app-icon delegates.
//   - WorkspaceWindowCountExtension  Extension lifecycle + badge management.

const REFRESH_DEBOUNCE_MS = 120;
const LOG_PREFIX = '[workspace-window-count]';

// Ordered log levels. Everything at or above ACTIVE_LOG_LEVEL is emitted; lower
// (more verbose) levels are suppressed so production logs stay quiet by default.
const LOG_LEVELS = { verbose: 0, debug: 1, info: 2, warn: 3, error: 4 };
const ACTIVE_LOG_LEVEL = LOG_LEVELS.info;
const createBadgeLabel = properties => new St.Label(properties);

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
      destroyBadge(badge, log);
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
      const isDelegate = delegate =>
        isAppIconDelegate(delegate, Shell.App, Clutter.Actor);
      for (const delegate of iterAppIconDelegates(global.stage, isDelegate)) {
        const badge = ensureBadge(
          delegate,
          this._badges,
          createBadgeLabel,
          log
        );
        if (!badge) {
          continue;
        }
        seen.add(badge);
        const activeWorkspace = global.workspace_manager.get_active_workspace();
        const count = countWindowsOnWorkspace(delegate.app, activeWorkspace);
        badge.text = count > 1 ? String(count) : '';
        badge.visible = count > 1;
        log(
          'verbose',
          `${delegate.app?.get_id?.() ?? 'unknown app'}: ${count} window(s) on active workspace`
        );
      }
      // Drop badges whose icons disappeared (taskbar rebuilt the actor).
      let dropped = 0;
      for (const badge of [...this._badges]) {
        if (!seen.has(badge)) {
          destroyBadge(badge, log);
          this._badges.delete(badge);
          dropped += 1;
        }
      }
      log('debug', `Refresh complete: ${seen.size} badge(s) shown, ${dropped} dropped`);
    } catch (e) {
      log('error', `Refresh failed: ${e}`);
    }
  }

}
