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
    this.id,
    this.activate,
    this.menu,
    this.longPress,
    this.setPressed,
  });

  final FocusNode node;
  final BuildContext context;
  final int order;

  /// The zone this item currently belongs to. Mutable because a widget can be
  /// moved between zones (a card entering the "continue" rail) without being
  /// rebuilt from scratch.
  String? zoneId;

  /// Stable address of this item inside the app, when it has one.
  ///
  /// Optional on purpose: a card that knows its media id passes it, and every
  /// surface built out of that card inherits the address for free. Items
  /// without an id still navigate geometrically — nothing breaks, they just
  /// cannot be returned to by name.
  String? id;

  /// The item's primary action. A keyboard reaches it through the focus tree
  /// (Enter/Space) and a pointer through the tap handler, but a gamepad raises
  /// no key event at all — without this the pad could move the highlight and
  /// never press anything.
  final VoidCallback? activate;

  /// The secondary "more" action, if the item has one.
  final VoidCallback? menu;

  /// The item's held-press action, already resolved.
  ///
  /// Distinct from [menu] because the two are reached by different things: a
  /// keyboard's ContextMenu key means "open the menu", while a pointer's long
  /// press and a pad's held A mean "that thing you get by holding". Items that
  /// use the second for something other than a menu — a cover that plays on
  /// hold — set this and leave [menu] null, and both devices still land in the
  /// right place.
  final VoidCallback? longPress;

  /// Drives the item's own press animation from a device that raises no widget
  /// event.
  ///
  /// A keyboard paints `_pressed` from its KeyDown and a pointer from
  /// `onTapDown`; a pad produces neither, so a held A would otherwise look
  /// exactly like no input at all until it fires — which is the one thing a
  /// ten-foot UI cannot afford while it is also waiting out a hold threshold.
  /// Null on items that do not animate a press.
  final ValueChanged<bool>? setPressed;

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

  /// Address index, maintained alongside [_entries] so a lookup costs a map
  /// hit instead of a scan. Duplicate ids are a programming error, not a
  /// runtime condition worth crashing over: the newest registration wins.
  final Map<String, FocusEntry> _byId = <String, FocusEntry>{};

  int _sequence = 0;

  List<FocusEntry> get entries => List<FocusEntry>.unmodifiable(_entries);

  int nextOrder() => _sequence++;

  void register(FocusEntry entry) {
    _entries.add(entry);
    final String? id = entry.id;
    if (id != null && id.isNotEmpty) {
      _byId[id] = entry;
    }
  }

  void unregister(FocusEntry entry) {
    _entries.remove(entry);
    final String? id = entry.id;
    if (id != null && identical(_byId[id], entry)) {
      _byId.remove(id);
    }
  }

  /// The entry registered under [id], if it is still on screen.
  FocusEntry? entryById(String id) {
    final FocusEntry? entry = _byId[id];
    if (entry == null || !entry.context.mounted) {
      return null;
    }
    return entry;
  }

  /// Re-points a registered entry at a new address.
  ///
  /// Keeps its slot in [_entries], so navigation order does not reshuffle when
  /// a list is rebuilt with the same widgets in a different order.
  void reindex(FocusEntry entry, {required String? id, required String? zoneId}) {
    final String? previous = entry.id;
    if (previous != null && previous.isNotEmpty && identical(_byId[previous], entry)) {
      _byId.remove(previous);
    }
    entry
      ..id = id
      ..zoneId = zoneId;
    if (id != null && id.isNotEmpty) {
      _byId[id] = entry;
    }
  }

  /// Drops entries whose widget tree is gone (defensive: dispose ordering can
  /// leave a stale entry behind during hot reload).
  void prune() {
    _entries.removeWhere((FocusEntry entry) {
      final bool dead = !entry.context.mounted;
      final String? id = entry.id;
      if (dead && id != null && identical(_byId[id], entry)) {
        _byId.remove(id);
      }
      return dead;
    });
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
    _byId.clear();
    _sequence = 0;
  }
}
