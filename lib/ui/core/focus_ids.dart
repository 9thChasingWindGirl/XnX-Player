/// The only place focus addresses are spelled.
///
/// An address is `family:key`, where the family says what kind of thing owns
/// it and the key is already unique (a media id is `sourceId::nativeId`, see
/// `MediaItem.id`; a dock entry has its own short id). Keeping the prefix in
/// one file means a typo shows up as a compile-time constant, not as a focus
/// that silently goes nowhere.
///
/// Addresses are optional decoration, not a requirement: any item without one
/// still navigates geometrically. They exist for the two cases geometry cannot
/// solve — returning to the exact card after visiting a hub, and handing focus
/// back to the opener when an overlay closes.
class FocusIds {
  const FocusIds._();

  /// A media card anywhere it appears (home shelf, library wall, search grid,
  /// hub episode row, continue rail). The same title therefore keeps one
  /// address across every surface, which is what makes "come back to what I
  /// was looking at" work after a tab switch.
  static String media(String mediaId) => 'media:$mediaId';

  /// A control-centre dock icon.
  static String dock(String itemId) => 'dock:$itemId';

  /// A named button inside a page: `action:home.play`.
  static String action(String page, String name) => 'action:$page.$name';

  /// A row in a settings section, so a scroll position can be restored to the
  /// row the user was on rather than to the top of the list.
  static String setting(String key) => 'setting:$key';
}
