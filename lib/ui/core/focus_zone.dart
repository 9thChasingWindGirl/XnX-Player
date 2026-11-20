import 'package:flutter/widgets.dart';

/// A logical navigation group (a rail, an action row, the dock...).
///
/// Zones are only used as a soft hint for the geometric navigator: when two
/// candidates are equally good, the one inside the current zone wins.
class FocusZone extends InheritedWidget {
  const FocusZone({
    super.key,
    required this.id,
    this.axis = Axis.horizontal,
    required super.child,
  });

  final String id;
  final Axis axis;

  static String? idOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<FocusZone>()?.id;
  }

  @override
  bool updateShouldNotify(FocusZone oldWidget) {
    return oldWidget.id != id || oldWidget.axis != axis;
  }
}

/// A focusable node known to the navigator, with the context needed to read its
/// geometry and to reveal it inside a scrollable.
class FocusEntry {
  FocusEntry({
    required this.node,
    required this.context,
    required this.zoneId,
    required this.order,
    this.activate,
    this.menu,
  });

  final FocusNode node;
  final BuildContext context;
  final String? zoneId;
  final int order;

  /// The item's primary action. A keyboard reaches it through the focus tree
  /// (Enter/Space) and a pointer through the tap handler, but a gamepad raises
  /// no key event at all — without this the pad could move the highlight and
  /// never press anything.
  final VoidCallback? activate;

  /// The secondary "more" action, if the item has one.
  final VoidCallback? menu;

  bool get isMounted => context.mounted && node.context != null;

  Rect? get rect {
    final RenderObject? renderObject = context.findRenderObject();
    if (renderObject is! RenderBox) {
      return null;
    }
    if (!renderObject.attached || !renderObject.hasSize) {
      return null;
    }
    return renderObject.localToGlobal(Offset.zero) & renderObject.size;
  }
}

/// Flat registry of every focusable node currently on screen.
///
/// Flutter's own traversal policy cannot express "horizontal inside a rail,
/// vertical across rails, with memory per rail", which is exactly what a
/// ten-foot UI needs, so navigation is computed here from geometry instead.
class FocusRegistry {
  FocusRegistry._();

  static final FocusRegistry instance = FocusRegistry._();

  final List<FocusEntry> _entries = <FocusEntry>[];

  int _sequence = 0;

  List<FocusEntry> get entries => List<FocusEntry>.unmodifiable(_entries);

  int nextOrder() => _sequence++;

  void register(FocusEntry entry) {
    _entries.add(entry);
  }

  void unregister(FocusEntry entry) {
    _entries.remove(entry);
  }

  /// Drops entries whose widget tree is gone (defensive: dispose ordering can
  /// leave a stale entry behind during hot reload).
  void prune() {
    _entries.removeWhere((FocusEntry entry) => !entry.context.mounted);
  }

  FocusEntry? entryFor(FocusNode? node) {
    if (node == null) {
      return null;
    }
    for (final FocusEntry entry in _entries) {
      if (identical(entry.node, node)) {
        return entry;
      }
    }
    return null;
  }

  void reset() {
    _entries.clear();
    _sequence = 0;
  }
}
