import 'package:flutter/foundation.dart';

/// Global flag saying "a text field owns the keyboard".
///
/// The shell installs a global key handler for D-pad navigation; without this
/// flag, typing a server address would be impossible because arrows would move
/// focus instead of the caret.
abstract final class TextEntry {
  static final ValueNotifier<bool> active = ValueNotifier<bool>(false);
}
