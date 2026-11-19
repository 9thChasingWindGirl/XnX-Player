import 'package:flutter/material.dart';

import '../../data/models/media_item.dart';
import '../../design/ps_tokens.dart';
import '../../ui/core/focus_zone.dart';
import 'home_tile.dart';
import 'tile_sources.dart';

/// One horizontal shelf. The row is a focus zone so the navigator prefers
/// staying inside it before jumping to a neighbouring row.
class HomeRail extends StatelessWidget {
  const HomeRail({
    super.key,
    required this.row,
    this.autofocusFirst = false,
    this.onSelect,
  });

  final HomeRow row;
  final bool autofocusFirst;
  final ValueChanged<MediaItem>? onSelect;

  @override
  Widget build(BuildContext context) {
    final double size = row.itemSize;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.only(
            left: PsSpace.safeX,
            bottom: PsSpace.railTitleGap,
          ),
          child: Text(row.title, style: PsType.section),
        ),
        SizedBox(
          height: size * 1.18,
          child: FocusZone(
            id: row.id,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: PsSpace.safeX),
              clipBehavior: Clip.none,
              itemCount: row.items.length,
              separatorBuilder: (BuildContext context, int index) {
                return const SizedBox(width: PsSpace.railGap);
              },
              itemBuilder: (BuildContext context, int index) {
                final MediaItem item = row.items[index];
                return Center(
                  child: HomeTile(
                    item: item,
                    size: size,
                    autofocus: autofocusFirst && index == 0,
                    onSelect: () => onSelect?.call(item),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}
