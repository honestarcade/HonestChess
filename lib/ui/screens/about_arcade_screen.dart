import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../board/board_view.dart' show designWidth;
import '../brand/honest_mark.dart';
import '../brand/links.dart';
import '../content/about_content.dart';
import '../theme/palette.dart';
import '../widgets/external_link.dart';
import '../widgets/screen_background.dart';
import '../widgets/screen_header.dart';

/// The widest screen the design's sizes scale up to.
const aboutScaleCapWidth = 480.0;

/// The design's side of the large mark, before scaling.
const aboutMarkSide = 120.0;

/// The smallest height a tappable takes.
const _minTouch = 48.0;

/// About Honest Arcade: who makes the app and what they promise, with
/// links that open in the phone's browser.
class AboutArcadeScreen extends StatelessWidget {
  const AboutArcadeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // Screen text ignores the system text scale, as the board does, until
    // M5's accessibility work.
    return MediaQuery.withNoTextScaling(
      child: Scaffold(
        backgroundColor: Palette.screenBg,
        resizeToAvoidBottomInset: false,
        body: ScreenBackground(
          gradient: ScreenGradient.aboutStudio,
          child: SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final s =
                    math.min(constraints.maxWidth, aboutScaleCapWidth) /
                    designWidth;
                final gap = 15 * s;
                // The links' 48 dp touch height is centred on their line
                // (9.5 × 1.7), eating into the gap above and the padding
                // below so the drawn spacing stays the design's.
                final linkLine = 9.5 * 1.7 * s;
                final linkSpill = math.max(0.0, (_minTouch - linkLine) / 2);
                return SingleChildScrollView(
                  key: const Key('aboutstudio-scroll'),
                  // The design's 56 dp top padding, less its 44 dp status
                  // bar (SafeArea's here).
                  padding: EdgeInsets.fromLTRB(
                    20 * s,
                    12,
                    20 * s,
                    math.max(0.0, 30 * s - linkSpill),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const ScreenHeader(
                        title: aboutStudioTitle,
                        keyPrefix: 'aboutstudio',
                      ),
                      SizedBox(height: gap),
                      Padding(
                        padding: EdgeInsets.only(top: 6 * s, bottom: 2 * s),
                        child: Center(
                          child: HonestMark.arcade(
                            aboutMarkSide * s,
                            key: const Key('aboutstudio-mark'),
                          ),
                        ),
                      ),
                      SizedBox(height: gap),
                      Text(
                        aboutStudioLead,
                        key: const Key('aboutstudio-lead'),
                        style: _font(
                          Fonts.outfit,
                          FontWeight.w400,
                          14,
                          1.65,
                          Palette.textBright,
                          s,
                        ),
                      ),
                      SizedBox(height: gap),
                      Text(
                        aboutStudioSecond,
                        key: const Key('aboutstudio-second'),
                        style: _font(
                          Fonts.outfit,
                          FontWeight.w400,
                          14,
                          1.65,
                          Palette.textDim,
                          s,
                        ),
                      ),
                      SizedBox(height: gap),
                      _SupportCard(scale: s),
                      SizedBox(height: gap),
                      _Promises(scale: s),
                      SizedBox(height: gap),
                      _Chips(scale: s),
                      SizedBox(height: math.max(0.0, gap - linkSpill)),
                      _Links(scale: s, height: linkLine + 2 * linkSpill),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// A CSS `font: <weight> <size>/<line-height>` at [scale], with CSS's
/// half-leading so the line boxes match the design's; a null [lineHeight]
/// is the font's own content height.
TextStyle _font(
  String family,
  FontWeight weight,
  double size,
  double? lineHeight,
  Color colour,
  double scale, {
  double letterSpacingEm = 0,
}) => TextStyle(
  fontFamily: family,
  fontWeight: weight,
  fontSize: size * scale,
  height: lineHeight,
  leadingDistribution: lineHeight == null ? null : TextLeadingDistribution.even,
  letterSpacing: letterSpacingEm * size * scale,
  color: colour,
);

class _SupportCard extends StatelessWidget {
  const _SupportCard({required this.scale});

  final double scale;

  @override
  Widget build(BuildContext context) {
    final s = scale;
    return ExternalLink(
      key: const Key('aboutstudio-support'),
      url: Links.contribute,
      semanticsLabel: '$supportKicker\n$supportText\n$supportLinkText',
      builder: (context, pressed) => Container(
        key: const Key('aboutstudio-support-card'),
        padding: EdgeInsets.symmetric(vertical: 14 * s, horizontal: 15 * s),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14 * s),
          border: Border.all(
            color: pressed ? Palette.teal : Palette.supportBorder,
          ),
          gradient: const LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            // CSS's 135°: towards the bottom right.
            transform: GradientRotation(math.pi / 4),
            colors: [Palette.supportWashStart, Palette.supportWashEnd],
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              supportKicker,
              style: _font(
                Fonts.plexMono,
                FontWeight.w500,
                9.5,
                1,
                Palette.teal,
                s,
                letterSpacingEm: .16,
              ),
            ),
            SizedBox(height: 6 * s),
            Text(
              supportText,
              style: _font(
                Fonts.outfit,
                FontWeight.w400,
                12.5,
                1.55,
                Palette.textBright,
                s,
              ),
            ),
            SizedBox(height: 6 * s),
            Text(
              '$supportLinkText →',
              key: const Key('aboutstudio-support-link'),
              style: _font(
                Fonts.outfit,
                FontWeight.w600,
                11.5,
                1,
                const Color(0xFFFFFFFF),
                s,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Promises extends StatelessWidget {
  const _Promises({required this.scale});

  final double scale;

  static Color tickColour(PromiseTick tick) => switch (tick) {
    PromiseTick.teal => Palette.teal,
    PromiseTick.blue => Palette.skyBlue,
    PromiseTick.violet => Palette.violetText,
  };

  @override
  Widget build(BuildContext context) {
    final s = scale;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          header: true,
          child: Text(
            promisesKicker,
            key: const Key('aboutstudio-promises-kicker'),
            style: _font(
              Fonts.plexMono,
              FontWeight.w500,
              9.5,
              1,
              Palette.kicker,
              s,
              letterSpacingEm: .16,
            ),
          ),
        ),
        for (final (i, promise) in promises.indexed) ...[
          SizedBox(height: 8 * s),
          MergeSemantics(
            child: Container(
              key: Key('aboutstudio-promise-$i'),
              padding: EdgeInsets.symmetric(
                vertical: 12 * s,
                horizontal: 14 * s,
              ),
              decoration: BoxDecoration(
                color: Palette.cardFill,
                borderRadius: BorderRadius.circular(12 * s),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ExcludeSemantics(
                    child: Text(
                      '✓',
                      key: Key('aboutstudio-tick-$i'),
                      style: _font(
                        Fonts.outfit,
                        FontWeight.w600,
                        12,
                        1.2,
                        tickColour(promise.tick),
                        s,
                      ),
                    ),
                  ),
                  SizedBox(width: 11 * s),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          promise.title,
                          key: Key('aboutstudio-promise-title-$i'),
                          style: _font(
                            Fonts.outfit,
                            FontWeight.w600,
                            12.5,
                            1,
                            const Color(0xFFFFFFFF),
                            s,
                          ),
                        ),
                        SizedBox(height: 5 * s),
                        Text(
                          promise.body,
                          key: Key('aboutstudio-promise-body-$i'),
                          style: _font(
                            Fonts.outfit,
                            FontWeight.w400,
                            11,
                            1.45,
                            Palette.textBody,
                            s,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _Chips extends StatelessWidget {
  const _Chips({required this.scale});

  final double scale;

  @override
  Widget build(BuildContext context) {
    final s = scale;
    const looks = [
      (Palette.tealFillSelected, Palette.tealOnTint),
      (Palette.blueFillChip, Palette.skyBlue),
      (Palette.violetFillSelected, Palette.violetText),
    ];
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 8 * s,
      runSpacing: 8 * s,
      children: [
        for (final (i, label) in promiseChips.indexed)
          Container(
            key: Key('aboutstudio-chip-$i'),
            padding: EdgeInsets.symmetric(vertical: 7 * s, horizontal: 12 * s),
            decoration: BoxDecoration(
              color: looks[i].$1,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              label,
              style: _font(
                Fonts.plexMono,
                FontWeight.w500,
                10.5,
                1,
                looks[i].$2,
                s,
              ),
            ),
          ),
      ],
    );
  }
}

class _Links extends StatelessWidget {
  const _Links({required this.scale, required this.height});

  final double scale;

  /// The row's touch height, the design's line centred in it.
  final double height;

  @override
  Widget build(BuildContext context) {
    final s = scale;
    TextStyle style(Color colour) => _font(
      Fonts.plexMono,
      FontWeight.w500,
      9.5,
      null,
      colour,
      s,
      letterSpacingEm: .12,
    );
    Widget link(String key, String url, String text) => ExternalLink(
      key: Key('aboutstudio-link-$key'),
      url: url,
      semanticsLabel: '$text, opens in browser',
      builder: (context, pressed) => SizedBox(
        height: height,
        child: Center(
          child: DecoratedBox(
            key: Key('aboutstudio-link-$key-underline'),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Palette.linkUnderline)),
            ),
            child: Text(
              '$text ↗',
              key: Key('aboutstudio-link-$key-text'),
              style: style(pressed ? Palette.teal : Palette.textDim),
            ),
          ),
        ),
      ),
    );
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        link('site', Links.site, siteLinkText),
        SizedBox(width: 8 * s),
        ExcludeSemantics(child: Text('·', style: style(Palette.textFaint))),
        SizedBox(width: 8 * s),
        link('github', Links.github, githubLinkText),
      ],
    );
  }
}
