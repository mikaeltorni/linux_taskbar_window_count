import assert from 'node:assert/strict';
import fs from 'node:fs';
import test from 'node:test';
import { fileURLToPath } from 'node:url';

import {
  DISPLAY_WINDOW_REFRESH_SIGNALS,
  countWindowsOnWorkspace,
  isAppIconDelegate,
  iterAppIconDelegates,
  resolveIconMonitorIndex,
  windowBelongsOnMonitor,
} from '../workspace-window-count@local/windowDiscovery.js';

class App {}
class Actor {
  constructor(delegate = null, children = []) {
    this._delegate = delegate;
    this._children = children;
  }

  get_children() {
    return this._children;
  }
}

function createWindow({
  workspace,
  skipTaskbar = false,
  sticky = false,
  monitor = 0,
}) {
  return {
    skip_taskbar: skipTaskbar,
    get_workspace: () => workspace,
    is_on_all_workspaces: () => sticky,
    get_monitor: () => monitor,
  };
}

function createDualMonitorDisplay() {
  return {
    get_n_monitors: () => 2,
    get_monitor_geometry: index =>
      index === 0
        ? { x: 0, y: 0, width: 1920, height: 1080 }
        : { x: 1920, y: 0, width: 1920, height: 1080 },
  };
}

test('countWindowsOnWorkspace counts visible windows on the selected workspace', () => {
  const activeWorkspace = {};
  const otherWorkspace = {};
  const app = {
    get_windows: () => [
      createWindow({ workspace: activeWorkspace }),
      createWindow({ workspace: activeWorkspace, sticky: true }),
      createWindow({ workspace: otherWorkspace }),
      createWindow({ workspace: activeWorkspace, skipTaskbar: true }),
    ],
  };

  assert.equal(countWindowsOnWorkspace(app, activeWorkspace), 2);
});

test('countWindowsOnWorkspace counts across all workspaces when requested', () => {
  const activeWorkspace = {};
  const otherWorkspace = {};
  const app = {
    get_windows: () => [
      createWindow({ workspace: activeWorkspace }),
      createWindow({ workspace: otherWorkspace }),
      createWindow({ workspace: otherWorkspace }),
      createWindow({ workspace: otherWorkspace, skipTaskbar: true }),
    ],
  };

  assert.equal(countWindowsOnWorkspace(app, activeWorkspace, false), 1);
  assert.equal(countWindowsOnWorkspace(app, activeWorkspace, true), 3);
});

test('countWindowsOnWorkspace handles apps without windows', () => {
  assert.equal(countWindowsOnWorkspace({ get_windows: () => [] }, {}), 0);
});

test('isAppIconDelegate requires matching app and actor instances', () => {
  assert.equal(
    isAppIconDelegate({ app: new App(), icon: new Actor() }, App, Actor),
    true
  );
  assert.equal(isAppIconDelegate(null, App, Actor), false);
  assert.equal(isAppIconDelegate({ app: {}, icon: new Actor() }, App, Actor), false);
  assert.equal(isAppIconDelegate({ app: new App(), icon: {} }, App, Actor), false);
});

test('iterAppIconDelegates walks nested actors depth-first', () => {
  const first = { app: new App(), icon: new Actor() };
  const second = { app: new App(), icon: new Actor() };
  const ignored = { app: {}, icon: new Actor() };
  const root = new Actor(null, [
    new Actor(first, [new Actor(ignored), new Actor(second)]),
  ]);

  assert.deepEqual(
    [...iterAppIconDelegates(root, delegate =>
      isAppIconDelegate(delegate, App, Actor)
    )],
    [first, second]
  );
});

test('countWindowsOnWorkspace counts only that app’s windows on the requested monitor', () => {
  const workspace = {};
  const app = {
    get_windows: () => [
      createWindow({ workspace, monitor: 0 }),
      createWindow({ workspace, monitor: 0 }),
      createWindow({ workspace, monitor: 1 }),
    ],
  };

  assert.equal(countWindowsOnWorkspace(app, workspace, false, 0), 2);
  assert.equal(countWindowsOnWorkspace(app, workspace, false, 1), 1);
});

test('countWindowsOnWorkspace omits skip_taskbar windows even on the counted monitor', () => {
  const workspace = {};
  const app = {
    get_windows: () => [
      createWindow({ workspace, monitor: 0 }),
      createWindow({ workspace, monitor: 0, skipTaskbar: true }),
      createWindow({ workspace, monitor: 1 }),
    ],
  };

  assert.equal(countWindowsOnWorkspace(app, workspace, false, 0), 1);
});

test('countWindowsOnWorkspace includes sticky windows only when they sit on that monitor', () => {
  const workspace = {};
  const otherWorkspace = {};
  const app = {
    get_windows: () => [
      createWindow({ workspace: otherWorkspace, monitor: 0, sticky: true }),
      createWindow({ workspace: otherWorkspace, monitor: 1, sticky: true }),
    ],
  };

  assert.equal(countWindowsOnWorkspace(app, workspace, false, 0), 1);
  assert.equal(countWindowsOnWorkspace(app, workspace, false, 1), 1);
});

test('countWindowsOnWorkspace excludes other-workspace windows unless all-workspaces is requested', () => {
  const workspace = {};
  const otherWorkspace = {};
  const app = {
    get_windows: () => [
      createWindow({ workspace, monitor: 0 }),
      createWindow({ workspace: otherWorkspace, monitor: 0 }),
      createWindow({ workspace: otherWorkspace, monitor: 1 }),
    ],
  };

  assert.equal(countWindowsOnWorkspace(app, workspace, false, 0), 1);
  assert.equal(countWindowsOnWorkspace(app, workspace, true, 0), 2);
  assert.equal(countWindowsOnWorkspace(app, workspace, true, 1), 1);
});

test('countWindowsOnWorkspace skips windows whose get_monitor() is -1', () => {
  const workspace = {};
  const app = {
    get_windows: () => [
      createWindow({ workspace, monitor: 0 }),
      createWindow({ workspace, monitor: -1 }),
    ],
  };

  assert.equal(countWindowsOnWorkspace(app, workspace, false, 0), 1);
  assert.equal(countWindowsOnWorkspace(app, workspace, false, -1), 0);
});

test('countWindowsOnWorkspace reflects a window moving to another monitor', () => {
  const workspace = {};
  const moving = createWindow({ workspace, monitor: 0 });
  const app = {
    get_windows: () => [
      createWindow({ workspace, monitor: 0 }),
      moving,
    ],
  };

  assert.equal(countWindowsOnWorkspace(app, workspace, false, 0), 2);
  assert.equal(countWindowsOnWorkspace(app, workspace, false, 1), 0);

  moving.get_monitor = () => 1;

  assert.equal(countWindowsOnWorkspace(app, workspace, false, 0), 1);
  assert.equal(countWindowsOnWorkspace(app, workspace, false, 1), 1);
});

test('windowBelongsOnMonitor matches only a non-negative window monitor', () => {
  const onZero = createWindow({ workspace: {}, monitor: 0 });
  const onOne = createWindow({ workspace: {}, monitor: 1 });
  const animating = createWindow({ workspace: {}, monitor: -1 });

  assert.equal(windowBelongsOnMonitor(onZero, 0), true);
  assert.equal(windowBelongsOnMonitor(onOne, 0), false);
  assert.equal(windowBelongsOnMonitor(animating, 0), false);
  assert.equal(windowBelongsOnMonitor(onZero, null), true);
});

test('resolveIconMonitorIndex prefers the Dash to Panel panel monitor index', () => {
  const delegate = {
    _dtpPanel: { monitor: { index: 1 } },
    monitorIndex: 0,
    icon: { get_transformed_position: () => [10, 10] },
  };

  assert.equal(resolveIconMonitorIndex(delegate, createDualMonitorDisplay()), 1);
});

test('resolveIconMonitorIndex uses the owning panel even when its icon is offscreen', () => {
  const delegate = {
    dtpPanel: { monitor: { index: 1 } },
    monitorIndex: 0,
    icon: { get_transformed_position: () => [-100, 40] },
  };
  assert.equal(resolveIconMonitorIndex(delegate, createDualMonitorDisplay()), 1);
});

test('resolveIconMonitorIndex preserves the legacy panel and geometry fallbacks', () => {
  const delegate = {
    dtpPanel: { monitor: { index: -1 } },
    _dtpPanel: { monitor: { index: 1 } },
    icon: { get_transformed_position: () => [10, 40] },
  };
  assert.equal(resolveIconMonitorIndex(delegate, createDualMonitorDisplay()), 1);
  delete delegate._dtpPanel;
  assert.equal(resolveIconMonitorIndex(delegate, createDualMonitorDisplay()), 0);
});

test('resolveIconMonitorIndex falls back to actor geometry vs display monitors', () => {
  const delegate = {
    icon: { get_transformed_position: () => [2000, 40] },
  };

  assert.equal(resolveIconMonitorIndex(delegate, createDualMonitorDisplay()), 1);
});

test('resolveIconMonitorIndex returns null when the monitor cannot be determined', () => {
  const delegate = { icon: {} };
  const display = {
    get_n_monitors: () => 0,
    get_monitor_geometry: () => ({ x: 0, y: 0, width: 0, height: 0 }),
  };

  assert.equal(resolveIconMonitorIndex(delegate, display), null);
});

test('DISPLAY_WINDOW_REFRESH_SIGNALS includes monitor enter and leave', () => {
  assert.equal(
    DISPLAY_WINDOW_REFRESH_SIGNALS.includes('window-entered-monitor'),
    true
  );
  assert.equal(
    DISPLAY_WINDOW_REFRESH_SIGNALS.includes('window-left-monitor'),
    true
  );
});

test('counting helpers are loaded from the extension source tree', () => {
  const source = import.meta.resolve(
    '../workspace-window-count@local/windowDiscovery.js'
  );
  assert.match(source, /workspace-window-count@local\/windowDiscovery\.js$/);
});

test('extension refresh path uses the shipped monitor counting helpers', () => {
  const extensionPath = fileURLToPath(
    new URL('../workspace-window-count@local/extension.js', import.meta.url)
  );
  const source = fs.readFileSync(extensionPath, 'utf8');
  assert.match(source, /DISPLAY_WINDOW_REFRESH_SIGNALS/);
  assert.match(source, /resolveIconMonitorIndex/);
  assert.match(source, /monitorIndex \?\? -1/);
});
