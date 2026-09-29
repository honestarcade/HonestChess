import 'package:flutter/widgets.dart';

import '../theme/palette.dart';
import 'section_card.dart';

/// A setup screen's card: its [title] (a header to assistive technology),
/// an optional [intro] line under it, and the card's [child] below.
class TitledSection extends StatelessWidget {
  const TitledSection({
    super.key,
    required this.title,
    this.intro,
    required this.child,
  });

  final String title;
  final String? intro;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final intro = this.intro;
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            container: true,
            header: true,
            headingLevel: 2,
            child: Text(
              title,
              style: const TextStyle(
                fontFamily: Fonts.outfit,
                fontWeight: FontWeight.w600,
                fontSize: 13.5,
                height: 1,
                color: Color(0xFFFFFFFF),
              ),
            ),
          ),
          if (intro != null) ...[
            const SizedBox(height: 6),
            // Its own node, so a screen reader reads it after the
            // heading (#147).
            Semantics(
              container: true,
              child: Text(
                intro,
                style: const TextStyle(
                  fontFamily: Fonts.outfit,
                  fontWeight: FontWeight.w400,
                  fontSize: 11,
                  height: 1.4,
                  color: Palette.textMuted,
                ),
              ),
            ),
          ],
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}
