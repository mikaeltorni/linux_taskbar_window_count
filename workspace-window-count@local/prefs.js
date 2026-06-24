import Adw from 'gi://Adw';
import Gtk from 'gi://Gtk';
import Gio from 'gi://Gio';
import {
  ExtensionPreferences,
  gettext as _,
} from 'resource:///org/gnome/Shell/Extensions/js/extensions/prefs.js';

// prefs.js — settings UI for workspace-window-count@local
//
// Renders the GNOME Extensions settings dialog and binds every control to the
// extension's GSettings schema. Each key the extension reads at runtime is
// editable here; changes apply live (no Shell reload). The dialog gracefully
// reflects the same defaults the extension falls back to when the schema is
// unavailable.
//
// Components:
//   - WorkspaceWindowCountPreferences  ExtensionPreferences subclass.
//   - POSITION_CHOICES                 Ordered enum nick/label pairs for the corner combo.

// Ordered to match the badge-position enum in the gschema; the index written
// back into the combo row maps to this list, so order is significant.
const POSITION_CHOICES = [
  ['top-left', 'Top left'],
  ['top-right', 'Top right'],
  ['bottom-left', 'Bottom left'],
  ['bottom-right', 'Bottom right'],
];

/**
 * Preferences dialog for the workspace window-count badge.
 *
 * Binds each control to a GSettings key on the extension's schema so edits are
 * persisted and observed live by the running extension.
 */
export default class WorkspaceWindowCountPreferences extends ExtensionPreferences {
  /**
   * Build and attach the preferences UI to the dialog window.
   *
   * @param {Adw.PreferencesWindow} window - The preferences window to populate.
   * @returns {void}
   */
  fillPreferencesWindow(window) {
    const settings = this.getSettings();

    const page = new Adw.PreferencesPage({
      title: _('Badge'),
      icon_name: 'preferences-system-symbolic',
    });
    window.add(page);

    page.add(this._buildBehaviorGroup(settings));
    page.add(this._buildAppearanceGroup(settings));
  }

  /**
   * Build the group controlling what the badge counts and when it appears.
   *
   * @param {Gio.Settings} settings - The extension's settings object.
   * @returns {Adw.PreferencesGroup} The populated behavior group.
   */
  _buildBehaviorGroup(settings) {
    const group = new Adw.PreferencesGroup({
      title: _('Counting'),
      description: _('What the badge counts and when it is shown.'),
    });

    const positionRow = new Adw.ComboRow({
      title: _('Badge position'),
      subtitle: _('Corner of each app icon the badge is drawn in.'),
      model: Gtk.StringList.new(POSITION_CHOICES.map(([, label]) => label)),
    });
    positionRow.selected = Math.max(
      0,
      POSITION_CHOICES.findIndex(
        ([nick]) => nick === settings.get_string('badge-position')
      )
    );
    positionRow.connect('notify::selected', row => {
      settings.set_string('badge-position', POSITION_CHOICES[row.selected][0]);
    });
    group.add(positionRow);

    const thresholdRow = new Adw.SpinRow({
      title: _('Minimum window count'),
      subtitle: _('Show the badge only at or above this many windows.'),
      adjustment: new Gtk.Adjustment({
        lower: 1,
        upper: 999,
        step_increment: 1,
      }),
    });
    settings.bind(
      'count-threshold',
      thresholdRow,
      'value',
      Gio.SettingsBindFlags.DEFAULT
    );
    group.add(thresholdRow);

    const scopeRow = new Adw.SwitchRow({
      title: _('Count all workspaces'),
      subtitle: _('Off counts only the current workspace.'),
    });
    settings.bind(
      'count-all-workspaces',
      scopeRow,
      'active',
      Gio.SettingsBindFlags.DEFAULT
    );
    group.add(scopeRow);

    return group;
  }

  /**
   * Build the group controlling badge colors and size.
   *
   * @param {Gio.Settings} settings - The extension's settings object.
   * @returns {Adw.PreferencesGroup} The populated appearance group.
   */
  _buildAppearanceGroup(settings) {
    const group = new Adw.PreferencesGroup({
      title: _('Appearance'),
      description: _('Badge colors and size. Use any CSS color value.'),
    });

    const textColorRow = new Adw.EntryRow({ title: _('Text color') });
    settings.bind(
      'badge-text-color',
      textColorRow,
      'text',
      Gio.SettingsBindFlags.DEFAULT
    );
    group.add(textColorRow);

    const backgroundColorRow = new Adw.EntryRow({
      title: _('Background color'),
    });
    settings.bind(
      'badge-background-color',
      backgroundColorRow,
      'text',
      Gio.SettingsBindFlags.DEFAULT
    );
    group.add(backgroundColorRow);

    const fontSizeRow = new Adw.SpinRow({
      title: _('Font size (px)'),
      adjustment: new Gtk.Adjustment({
        lower: 6,
        upper: 64,
        step_increment: 1,
      }),
    });
    settings.bind(
      'badge-font-size',
      fontSizeRow,
      'value',
      Gio.SettingsBindFlags.DEFAULT
    );
    group.add(fontSizeRow);

    return group;
  }
}
