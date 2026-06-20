/**
 * Badge actor creation, positioning, reuse, and teardown.
 */

const BADGE_KEY = '_wwcBadge';
const RIGHT_NUDGE_PX = 4;

/**
 * Return the badge for a delegate, creating, attaching, and positioning one
 * when necessary.
 *
 * The badge tracks its icon's size changes to stay anchored in the
 * bottom-right corner and self-destructs when the icon actor is destroyed.
 * Constructor dependencies are supplied by the extension so this module
 * remains testable outside a live GNOME Shell process.
 *
 * @param {object} delegate - App-icon delegate that owns the icon actor.
 * @param {Set<object>} badges - Registry of badges owned by the extension.
 * @param {Function} createLabel - Factory that creates an St.Label-compatible actor.
 * @param {Function} log - Extension logging function.
 * @returns {St.Label} The existing or newly created badge label.
 */
export function ensureBadge(delegate, badges, createLabel, log) {
  const existing = delegate[BADGE_KEY];
  if (existing && badges.has(existing)) {
    return existing;
  }

  const iconActor = delegate.icon;
  const badge = createLabel({
    style_class: 'wwc-badge',
    text: '',
    visible: false,
  });
  badge.clutter_text.set_line_wrap(false);
  iconActor.add_child(badge);

  // Nudge past the icon edge so the final glyph and shadow are not clipped.
  const reposition = () => {
    const width = iconActor.width;
    const height = iconActor.height;
    badge.set_position(
      Math.max(0, width - badge.width + RIGHT_NUDGE_PX),
      Math.max(0, height - badge.height)
    );
  };
  // Pair each handler id with the object it was connected on so teardown
  // disconnects from the correct source (icon size vs. badge size signals).
  const sizeSignals = [
    [iconActor, iconActor.connect('notify::width', reposition)],
    [iconActor, iconActor.connect('notify::height', reposition)],
    [badge, badge.connect('notify::width', reposition)],
    [badge, badge.connect('notify::height', reposition)],
  ];
  const destroyId = iconActor.connect('destroy', () => {
    destroyBadge(badge, log);
    badges.delete(badge);
  });

  badge._wwcIconActor = iconActor;
  badge._wwcDelegate = delegate;
  badge._wwcSignals = sizeSignals;
  badge._wwcDestroyId = destroyId;
  delegate[BADGE_KEY] = badge;
  badges.add(badge);
  reposition();
  log('verbose', `Created badge for ${delegate.app?.get_id?.() ?? 'unknown app'}`);
  return badge;
}

/**
 * Tear down a badge and clear its delegate back-reference.
 *
 * Safe to call regardless of whether the badge is still registered in the
 * extension's badge set. Callers remain responsible for removing it there.
 *
 * @param {St.Label} badge - Badge created by {@link ensureBadge}.
 * @param {Function} [log] - Optional extension logging function; when supplied,
 *   a verbose teardown line is emitted. Defaults to a no-op so the icon-destroy
 *   path and tests can call this without a logger.
 * @returns {void}
 */
export function destroyBadge(badge, log = () => {}) {
  for (const [target, id] of badge._wwcSignals || []) {
    target.disconnect(id);
  }
  const iconActor = badge._wwcIconActor;
  if (iconActor && badge._wwcDestroyId) {
    iconActor.disconnect(badge._wwcDestroyId);
  }
  const appId = badge._wwcDelegate?.app?.get_id?.() ?? 'unknown app';
  if (badge._wwcDelegate && badge._wwcDelegate[BADGE_KEY] === badge) {
    delete badge._wwcDelegate[BADGE_KEY];
  }
  badge.destroy();
  log('verbose', `Destroyed badge for ${appId}`);
}
