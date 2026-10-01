import assert from 'node:assert/strict';
import { beforeEach, test } from 'node:test';

import {
  applyBadgeStyle,
  destroyBadge,
  ensureBadge,
  resolveBadgePosition,
} from '../workspace-window-count@local/badgeLifecycle.js';

let nextSignalId = 1;

beforeEach(() => {
  nextSignalId = 1;
});

class SignalTarget {
  constructor() {
    this._handlers = new Map();
    this.disconnected = [];
  }

  connect(signal, callback) {
    const id = nextSignalId;
    nextSignalId += 1;
    this._handlers.set(signal, { callback, id });
    return id;
  }

  disconnect(id) {
    this.disconnected.push(id);
  }

  emit(signal) {
    this._handlers.get(signal)?.callback();
  }
}

class IconActor extends SignalTarget {
  constructor({ width = 40, height = 32 } = {}) {
    super();
    this.width = width;
    this.height = height;
    this.children = [];
  }

  add_child(child) {
    this.children.push(child);
  }
}

class Badge extends SignalTarget {
  constructor(properties, { width = 12, height = 10 } = {}) {
    super();
    Object.assign(this, properties);
    this.width = width;
    this.height = height;
    this.destroyed = false;
    this.positions = [];
    this.clutter_text = {
      set_line_wrap: value => {
        this.lineWrap = value;
      },
    };
  }

  set_position(x, y) {
    this.positions.push([x, y]);
  }

  destroy() {
    this.destroyed = true;
  }
}

function createFixture(options = {}) {
  const icon = new IconActor(options.icon);
  const delegate = {
    app: { get_id: () => 'example.desktop' },
    icon,
  };
  const badges = new Set();
  const logMessages = [];
  const createLabel = properties => new Badge(properties, options.badge);

  return { badges, createLabel, delegate, icon, logMessages };
}

test('ensureBadge creates, attaches, positions, and reuses a badge', () => {
  const fixture = createFixture();
  const log = (level, message) => fixture.logMessages.push([level, message]);

  const badge = ensureBadge(
    fixture.delegate,
    fixture.badges,
    fixture.createLabel,
    log
  );

  assert.equal(badge.style_class, 'wwc-badge');
  assert.equal(badge.text, '');
  assert.equal(badge.visible, false);
  assert.equal(badge.lineWrap, false);
  assert.deepEqual(fixture.icon.children, [badge]);
  assert.deepEqual(badge.positions, [[32, 22]]);
  assert.equal(fixture.badges.has(badge), true);
  assert.deepEqual(fixture.logMessages, [
    ['verbose', 'Created badge for example.desktop'],
  ]);
  assert.equal(
    ensureBadge(fixture.delegate, fixture.badges, fixture.createLabel, log),
    badge
  );
  assert.equal(fixture.icon.children.length, 1);
});

test('ensureBadge repositions for icon and badge size changes', () => {
  const fixture = createFixture();
  const badge = ensureBadge(
    fixture.delegate,
    fixture.badges,
    fixture.createLabel,
    () => {}
  );

  fixture.icon.width = 50;
  fixture.icon.emit('notify::width');
  badge.height = 14;
  badge.emit('notify::height');

  assert.deepEqual(badge.positions, [
    [32, 22],
    [42, 22],
    [42, 18],
  ]);
});

test('ensureBadge anchors to the configured corner and re-anchors live', () => {
  // icon 40x32, badge 12x10, RIGHT_NUDGE_PX 4.
  const fixture = createFixture();
  const badge = ensureBadge(
    fixture.delegate,
    fixture.badges,
    fixture.createLabel,
    () => {},
    () => 'top-left'
  );

  // top-left -> x=0, y=0.
  assert.deepEqual(badge.positions, [[0, 0]]);

  // Re-anchoring uses the live getter, so the stored reposition reflects the
  // new corner without recreating the actor.
  fixture.delegate._wwcPosition = 'top-right';
  const movableBadge = ensureBadge(
    { app: { get_id: () => 'two.desktop' }, icon: fixture.icon },
    fixture.badges,
    fixture.createLabel,
    () => {},
    () => 'top-right'
  );
  // top-right -> x = 40-12+4 = 32, y = 0.
  assert.deepEqual(movableBadge.positions, [[32, 0]]);
  movableBadge._wwcReposition();
  assert.deepEqual(movableBadge.positions, [
    [32, 0],
    [32, 0],
  ]);
});

test('vertical panels use bottom-left while horizontal and custom positions stay unchanged', () => {
  const verticalDelegate = {
    dtpPanel: { getOrientation: () => 'VERTICAL' },
  };
  const horizontalDelegate = {
    dtpPanel: { getOrientation: () => 'HORIZONTAL' },
  };

  assert.equal(
    resolveBadgePosition('bottom-right', verticalDelegate),
    'bottom-left'
  );
  assert.equal(
    resolveBadgePosition('bottom-right', horizontalDelegate),
    'bottom-right'
  );
  assert.equal(
    resolveBadgePosition('top-right', verticalDelegate),
    'top-right'
  );

  const fixture = createFixture();
  fixture.delegate.dtpPanel = verticalDelegate.dtpPanel;
  const badge = ensureBadge(
    fixture.delegate,
    fixture.badges,
    fixture.createLabel,
    () => {},
    () => resolveBadgePosition('bottom-right', fixture.delegate)
  );
  assert.deepEqual(badge.positions, [[0, 22]]);
});

test('Ubuntu Dock uses the enclosing dash orientation and reads it live', () => {
  const fixture = createFixture();
  const dash = { _isHorizontal: false };
  const dashBox = { _delegate: dash, get_parent: () => null };
  const item = { get_parent: () => dashBox };
  fixture.icon.get_parent = () => item;

  const badge = ensureBadge(
    fixture.delegate,
    fixture.badges,
    fixture.createLabel,
    () => {},
    () => resolveBadgePosition('bottom-right', fixture.delegate)
  );
  assert.deepEqual(badge.positions, [[0, 22]]);
  assert.equal(resolveBadgePosition('top-right', fixture.delegate), 'top-right');

  dash._isHorizontal = true;
  badge._wwcReposition();
  assert.deepEqual(badge.positions.at(-1), [32, 22]);

  delete dash._isHorizontal;
  assert.equal(resolveBadgePosition('bottom-right', fixture.delegate), 'bottom-right');
});

test('badge overlays keep their height when the base icon uses a box layout', () => {
  const fixture = createFixture();
  const container = new IconActor();
  fixture.delegate._iconContainer = container;
  fixture.icon.add_child = child => {
    // Ubuntu Dock's base icon allocates its whole height to the app artwork,
    // leaving a second stacked child with no room for its numeral.
    child.height = 0;
    fixture.icon.children.push(child);
  };
  let overlay;
  const badge = ensureBadge(
    fixture.delegate,
    fixture.badges,
    fixture.createLabel,
    () => {},
    () => 'bottom-left',
    source => {
      assert.equal(source, fixture.icon);
      overlay = new IconActor();
      overlay.destroy = () => { overlay.destroyed = true; };
      return overlay;
    }
  );

  assert.equal(badge.height, 10);
  assert.deepEqual(badge.positions, [[0, 22]]);
  assert.deepEqual(fixture.icon.children, []);
  assert.deepEqual(container.children, [overlay]);
  assert.deepEqual(overlay.children, [badge]);

  fixture.icon.emit('destroy');
  assert.equal(badge.destroyed, true);
  assert.equal(overlay.destroyed, true);
  assert.equal(fixture.badges.size, 0);
});

test('applyBadgeStyle sets an inline style from the config', () => {
  const fixture = createFixture();
  const badge = ensureBadge(
    fixture.delegate,
    fixture.badges,
    fixture.createLabel,
    () => {}
  );

  applyBadgeStyle(badge, {
    backgroundColor: 'rgba(0,0,0,0.5)',
    textColor: '#00ff00',
    fontSize: 18,
  });

  assert.equal(
    badge.style,
    'background-color: rgba(0,0,0,0.5); color: #00ff00; font-size: 18px;'
  );
});

test('ensureBadge clamps positions when a badge is larger than its icon', () => {
  const fixture = createFixture({
    icon: { width: 8, height: 6 },
    badge: { width: 20, height: 12 },
  });

  const badge = ensureBadge(
    fixture.delegate,
    fixture.badges,
    fixture.createLabel,
    () => {}
  );

  assert.deepEqual(badge.positions, [[0, 0]]);
});

test('destroyBadge disconnects handlers, clears the delegate, and destroys', () => {
  const fixture = createFixture();
  const badge = ensureBadge(
    fixture.delegate,
    fixture.badges,
    fixture.createLabel,
    () => {}
  );

  destroyBadge(badge);

  assert.equal(fixture.delegate._wwcBadge, undefined);
  assert.equal(badge.destroyed, true);
  // Icon owns its two size signals plus the destroy handler; the badge owns its
  // own two size signals. Each must be disconnected from the object it was
  // connected on, never cross-disconnected.
  assert.equal(fixture.icon.disconnected.length, 3);
  assert.equal(badge.disconnected.length, 2);
});

test('destroyBadge emits a verbose teardown log when a logger is supplied', () => {
  const fixture = createFixture();
  const log = (level, message) => fixture.logMessages.push([level, message]);
  const badge = ensureBadge(
    fixture.delegate,
    fixture.badges,
    fixture.createLabel,
    () => {}
  );

  destroyBadge(badge, log);

  assert.deepEqual(fixture.logMessages, [
    ['verbose', 'Destroyed badge for example.desktop'],
  ]);
});

test('destroying an icon tears down and unregisters its badge', () => {
  const fixture = createFixture();
  const badge = ensureBadge(
    fixture.delegate,
    fixture.badges,
    fixture.createLabel,
    () => {}
  );

  fixture.icon.emit('destroy');

  assert.equal(badge.destroyed, true);
  assert.equal(fixture.badges.has(badge), false);
  assert.equal(fixture.delegate._wwcBadge, undefined);
});

test('ensureBadge leaves registry unchanged when label creation fails', () => {
  const fixture = createFixture();
  const expectedError = new Error('label creation failed');

  assert.throws(
    () =>
      ensureBadge(
        fixture.delegate,
        fixture.badges,
        () => {
          throw expectedError;
        },
        () => {}
      ),
    expectedError
  );
  assert.equal(fixture.badges.size, 0);
  assert.equal(fixture.delegate._wwcBadge, undefined);
});
