import 'package:flutter/widgets.dart';

import '../core/focus_highlight.dart';
import 'ps_backdrop.dart';

/// A full-screen page with the two layers every screen needs: the drifting
/// backdrop, then content above it inside its own gliding-focus stage.
///
/// Pushed routes use this because they sit above the shell's stage; the shell's
/// tabs are already inside one.
class PsPage extends StatelessWidget {
  const PsPage({
    super.key,
    required this.child,
    this.palette,
    this.dim = 0,
  });

  final Widget child;
  final List<Color>? palette;
  final double dim;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        PsBackdrop(palette: palette, dim: dim),
        GlideFocusStage(child: child),
      ],
    );
  }
}
