import St from 'gi://St';
import GLib from 'gi://GLib';
import Shell from 'gi://Shell';
import Clutter from 'gi://Clutter';
import { Extension } from 'resource:///org/gnome/shell/extensions/extension.js';

// workspace-window-count@local
//
// Draws a small badge in the BOTTOM-RIGHT corner of every taskbar app icon
// (e.g. Dash to Panel) showing how many windows of that app are open on the
// CURRENT workspace. Bottom-right is deliberately chosen so the badge never
// overlaps notification counters, which live in the top-right corner.

const BADGE_KEY = '_wwcBadge';
const REFRESH_DEBOUNCE_MS = 120;

// Count windows of `app` that live on the active workspace. Windows that are
// sticky / on all workspaces are counted on every workspace (get_workspace()
// returns the active one for them). skip_taskbar windows are ignored so the
// badge matches what the taskbar actually represents.
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

// A taskbar app icon delegate exposes a Shell.App via `.app` and a host actor
// via `.icon`. We use these duck-typed properties so the extension works with
// Dash to Panel, the stock dash, and any taskbar built on the same primitives.
function isAppIconDelegate(delegate) {
  return !!(
    delegate &&
    delegate.app instanceof Shell.App &&
    delegate.icon instanceof Clutter.Actor
  );
}

function* iterAppIconDelegates(actor) {
  const delegate = actor._delegate;
  if (isAppIconDelegate(delegate)) {
    yield delegate;
  }
  for (const child of actor.get_children()) {
    yield* iterAppIconDelegates(child);
  }
}

export default class WorkspaceWindowCountExtension extends Extension {
  enable() {
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

    for (const actor of global.get_window_actors()) {
      if (actor.meta_window) {
        this._trackWindow(actor.meta_window);
      }
    }

    this._queueRefresh();
  }

  disable() {
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
    for (const badge of this._badges) {
      this._destroyBadge(badge);
    }
    this._badges.clear();
  }

  _connect(obj, signal, cb) {
    this._signals.push([obj, obj.connect(signal, cb)]);
  }

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

  _refresh() {
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
  }

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
    return badge;
  }

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
