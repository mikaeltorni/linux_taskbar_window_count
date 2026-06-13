import assert from 'node:assert/strict';
import test from 'node:test';

import {
  countWindowsOnWorkspace,
  isAppIconDelegate,
  iterAppIconDelegates,
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

function createWindow({ workspace, skipTaskbar = false, sticky = false }) {
  return {
    skip_taskbar: skipTaskbar,
    get_workspace: () => workspace,
    is_on_all_workspaces: () => sticky,
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
