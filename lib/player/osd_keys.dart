/// Maps Flutter key identities onto the key names the Lua OSD understands.
///
/// The OSD (`assets/mpv/xnx_osd.lua`) parses strings like `space`, `shift+left`
/// and `alt+n`. Flutter identifies keys with a stable `debugName` such as
/// `Key A`, `Arrow Left` or `Bracket Left`, so this is the only place that knows
/// both vocabularies. Kept free of Flutter imports so it can be unit-tested.
library;

abstract final class OsdKeys {
  const OsdKeys._();

  static const Map<String, String> _named = <String, String>{
    'Space': 'space',
    'Arrow Left': 'left',
    'Arrow Right': 'right',
    'Arrow Up': 'up',
    'Arrow Down': 'down',
    'Escape': 'esc',
    'Enter': 'enter',
    'Numpad Enter': 'enter',
    'Tab': 'tab',
    'Backspace': 'bs',
    'Page Up': 'pageup',
    'Page Down': 'pagedown',
    'Bracket Left': '[',
    'Bracket Right': ']',
    'Comma': 'comma',
    'Period': 'period',
    'Minus': '-',
    'Equal': '=',
  };

  /// The OSD name for one physical key, ignoring modifiers.
  ///
  /// Returns null for keys the OSD has no opinion about, which makes the caller
  /// leave the event untouched for the rest of the app.
  static String? base(String? debugName) {
    if (debugName == null) {
      return null;
    }
    final String? fixed = _named[debugName];
    if (fixed != null) {
      return fixed;
    }
    if (debugName.startsWith('Key ') && debugName.length == 5) {
      return debugName.substring(4).toLowerCase();
    }
    if (debugName.startsWith('Digit ') && debugName.length == 7) {
      return debugName.substring(6);
    }
    if (debugName.length >= 2 && debugName.length <= 3 && debugName.startsWith('F')) {
      final int? number = int.tryParse(debugName.substring(1));
      if (number != null && number >= 1 && number <= 12) {
        return 'f$number';
      }
    }
    return null;
  }

  /// `shift+left`, `alt+n`, `space` — exactly what the Lua handler parses.
  static String? compose(String? debugName, {bool shift = false, bool alt = false}) {
    final String? name = base(debugName);
    if (name == null) {
      return null;
    }
    if (!shift && !alt) {
      return name;
    }
    final StringBuffer buffer = StringBuffer();
    if (alt) {
      buffer.write('alt+');
    }
    if (shift) {
      buffer.write('shift+');
    }
    buffer.write(name);
    return buffer.toString();
  }
}
