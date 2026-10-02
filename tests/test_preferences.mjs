import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
import test from 'node:test';

// Run the shipped preferences entrypoint with GI substitutes; no GUI process
// or windows are opened. Each case builds fresh widgets and settings.
class Widget {
  constructor(properties = {}) {
    this.children = [];
    this.handlers = new Map();
    this.nextId = 1;
    this._selected = 0;
    Object.assign(this, properties);
  }

  add(child) {
    this.children.push(child);
  }

  connect(signal, callback) {
    const id = this.nextId++;
    this.handlers.set(id, {signal, callback});
    return id;
  }

  disconnect(id) {
    assert.equal(this.handlers.delete(id), true);
  }

  emit(signal, ...args) {
    for (const handler of [...this.handlers.values()]) {
      if (handler.signal === signal)
        handler.callback(this, ...args);
    }
  }

  get selected() {
    return this._selected;
  }

  set selected(value) {
    if (value !== this._selected) {
      this._selected = value;
      this.emit('notify::selected');
    }
  }
}

class Settings extends Widget {
  constructor(position) {
    super();
    this.values = new Map([['badge-position', position]]);
    this.writes = [];
    this.bindings = [];
  }

  get_string(key) {
    return this.values.get(key);
  }

  set_string(key, value) {
    this.writes.push([key, value]);
    if (this.values.get(key) !== value) {
      this.values.set(key, value);
      this.emit(`changed::${key}`, key);
    }
  }

  bind(key, row, property, flags) {
    this.bindings.push({key, row, property, flags});
  }
}

function buildPreferences(position = 'bottom-right') {
  const settings = new Settings(position);
  const window = new Widget();
  const source = fs.readFileSync(new URL(
    '../workspace-window-count@local/prefs.js', import.meta.url), 'utf8');
  const context = vm.createContext({
    Adw: Object.fromEntries(['PreferencesPage', 'PreferencesGroup', 'ComboRow',
      'SpinRow', 'SwitchRow', 'EntryRow'].map(name => [name, Widget])),
    Gtk: {Adjustment: Widget, StringList: {new: values => values}},
    Gio: {SettingsBindFlags: {DEFAULT: 0}},
    ExtensionPreferences: class { getSettings() { return settings; } },
    _: text => text,
  });
  const runnable = source.replace(/^import[\s\S]*?;\n/gm, '')
    .replace('export default class ', 'globalThis.Preferences = class ');
  vm.runInContext(runnable, context, {filename: 'prefs.js'});
  new context.Preferences().fillPreferencesWindow(window);
  const row = window.children[0].children[0].children[0];
  return {settings, window, row};
}

test('preferences initialize the corner and write the selected setting', () => {
  const {settings, row} = buildPreferences();
  assert.equal(row.selected, 3);
  row.selected = 1;
  assert.equal(settings.get_string('badge-position'), 'top-right');
  assert.deepEqual(settings.writes, [['badge-position', 'top-right']]);
  assert.equal(settings.bindings.length, 5);
});

test('preferences reflect external position changes without redundant writes', () => {
  const {settings, row} = buildPreferences('top-right');
  settings.set_string('badge-position', 'bottom-left');
  assert.equal(row.selected, 2);
  assert.deepEqual(settings.writes, [['badge-position', 'bottom-left']]);
});

test('destroying the corner row disconnects its settings observer', () => {
  const {settings, row} = buildPreferences();
  assert.equal(settings.handlers.size, 1);
  row.emit('destroy');
  assert.equal(settings.handlers.size, 0);
  settings.set_string('badge-position', 'top-left');
  assert.equal(row.selected, 3);
});
