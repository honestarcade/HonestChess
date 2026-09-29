import 'package:flutter/widgets.dart';

import '../theme/palette.dart';

/// The design's plain rounded box a screen groups things in: Settings'
/// cards, the notes, the setup screens' sections. Titles and captions stay
/// with each screen.
class SectionCard extends StatelessWidget {
  const SectionCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.symmetric(vertical: 14, horizontal: 15),
    this.radius = 14,
    this.fill = Palette.cardFill,
  });

  final Widget child;
  final EdgeInsets padding;
  final double radius;
  final Color fill;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(radius),
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}
