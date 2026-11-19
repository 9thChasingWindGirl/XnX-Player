import 'package:material_ui/material_ui.dart';

import '../../data/models/media_item.dart';
import '../../design/ps_tokens.dart';
import '../../ui/widgets/ps_button.dart';
import 'home_rail.dart';
import 'tile_sources.dart';

/// PS5 welcome hub: a dark stage lit by the current title's key art, a hero
/// block on the left, then shelves of square tiles.
class HomePage extends StatelessWidget {
  const HomePage({super.key, required this.onPlay, this.onOpenFile});

  final ValueChanged<MediaItem> onPlay;
  final VoidCallback? onOpenFile;

  @override
  Widget build(BuildContext context) {
    final List<HomeRow> rows = DemoLibrary.rows();

    return Stack(
      children: <Widget>[
        const Positioned.fill(child: _Backdrop()),
        ListView(
          padding: EdgeInsets.zero,
          children: <Widget>[
            const SizedBox(height: PsSpace.topBarHeight + 40),
            _Hero(
              item: DemoLibrary.hero,
              onPlay: () => onPlay(DemoLibrary.hero),
              onMore: onOpenFile,
            ),
            const SizedBox(height: PsSpace.huge),
            for (int i = 0; i < rows.length; i++)
              Padding(
                padding: EdgeInsets.only(bottom: i == rows.length - 1 ? 160 : 44),
                child: HomeRail(
                  row: rows[i],
                  autofocusFirst: i == 0,
                  onSelect: onPlay,
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _Backdrop extends StatelessWidget {
  const _Backdrop();

  @override
  Widget build(BuildContext context) {
    // One const tree: three layered gradients (stage wash + two corner glows +
    // a left-to-right scrim that keeps hero text legible over bright key art).
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[Color(0xFF141C2C), PsColor.bgDeep, Color(0xFF04050A)],
          stops: <double>[0.0, 0.55, 1.0],
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          Positioned(
            top: -320,
            right: -180,
            width: 1400,
            height: 1100,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  radius: 0.62,
                  colors: <Color>[Color(0x3D4A6EA8), Color(0x00000000)],
                ),
              ),
            ),
          ),
          Positioned(
            left: -400,
            bottom: -500,
            width: 1200,
            height: 1200,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  radius: 0.6,
                  colors: <Color>[Color(0x1F2C4A6E), Color(0x00000000)],
                ),
              ),
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: <Color>[
                  Color(0xB3000000),
                  Color(0x1A000000),
                  Color(0x00000000),
                ],
                stops: <double>[0.0, 0.45, 0.75],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({required this.item, required this.onPlay, this.onMore});

  final MediaItem item;
  final VoidCallback onPlay;
  final VoidCallback? onMore;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: PsSpace.safeX, right: 720),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (item.badge != null) ...<Widget>[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(PsRadius.pill),
                border: Border.all(color: const Color(0x4DFFFFFF)),
              ),
              child: Text(
                item.badge!,
                style: PsType.micro.copyWith(color: PsColor.text, letterSpacing: 1.2),
              ),
            ),
            const SizedBox(height: PsSpace.lg),
          ],
          Text(item.title, style: PsType.hero, maxLines: 1, overflow: TextOverflow.ellipsis),
          if (item.subtitle != null) ...<Widget>[
            const SizedBox(height: PsSpace.sm),
            Text(item.subtitle!, style: PsType.card.copyWith(color: PsColor.textDim)),
          ],
          if (item.meta != null) ...<Widget>[
            const SizedBox(height: PsSpace.xs),
            Text(item.meta!, style: PsType.micro.copyWith(letterSpacing: 0.4)),
          ],
          if (item.overview != null) ...<Widget>[
            const SizedBox(height: PsSpace.md),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 780),
              child: Text(
                item.overview!,
                style: PsType.body,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
          if (item.progress > 0) ...<Widget>[
            const SizedBox(height: PsSpace.lg),
            Row(
              children: <Widget>[
                SizedBox(
                  width: 280,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: LinearProgressIndicator(
                      value: item.progress,
                      minHeight: 4,
                      backgroundColor: const Color(0x33FFFFFF),
                      valueColor: const AlwaysStoppedAnimation<Color>(PsColor.text),
                    ),
                  ),
                ),
                const SizedBox(width: PsSpace.md),
                Text(
                  '已观看 ${(item.progress * 100).round()}%',
                  style: PsType.micro,
                ),
              ],
            ),
          ],
          const SizedBox(height: PsSpace.xl),
          Row(
            children: <Widget>[
              PsButton(
                label: item.progress > 0 ? '继续播放' : '播放',
                icon: Icons.play_arrow_rounded,
                primary: true,
                onTap: onPlay,
              ),
              const SizedBox(width: PsSpace.md),
              if (onMore != null)
                PsButton(
                  label: '打开文件',
                  icon: Icons.folder_open_rounded,
                  onTap: onMore,
                ),
            ],
          ),
        ],
      ),
    );
  }
}
