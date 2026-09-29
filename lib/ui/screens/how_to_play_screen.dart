import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../engine/engine.dart';
import '../app_scope.dart';
import '../board/board_options.dart';
import '../board/board_view.dart';
import '../content/rules_text.dart';
import '../theme/palette.dart';
import '../widgets/screen_header.dart';
import '../widgets/segmented_tabs.dart';

/// How to play's two tabs.
enum HowToTab { pieces, rules }

/// The widest screen the design's sizes scale up to.
const howToScaleCapWidth = 480.0;

/// How to play: how each piece moves, the rules that matter here and the
/// gestures, in two tabs. It opens on [initialTab] and does not remember
/// the tab between visits.
class HowToPlayScreen extends StatefulWidget {
  const HowToPlayScreen({super.key, this.initialTab = HowToTab.pieces});

  final HowToTab initialTab;

  @override
  State<HowToPlayScreen> createState() => _HowToPlayScreenState();
}

class _HowToPlayScreenState extends State<HowToPlayScreen> {
  late HowToTab _tab = widget.initialTab;
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _show(HowToTab tab) {
    setState(() => _tab = tab);
    // A tab starts at its top, as the design's re-rendered scroll does.
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  @override
  Widget build(BuildContext context) {
    final board = AppScope.of(context).settings.board;
    return Scaffold(
      backgroundColor: Palette.screenBg,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final s =
                math.min(constraints.maxWidth, howToScaleCapWidth) /
                designWidth;
            final pillGap = 13 * s - SegmentedTabs.overhang(s);
            return SingleChildScrollView(
              key: const Key('howto-scroll'),
              controller: _scroll,
              // The design's 56 dp top padding, less its 44 dp status bar
              // (SafeArea's here).
              padding: EdgeInsets.fromLTRB(20 * s, 12, 20 * s, 30 * s),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const ScreenHeader(title: howToTitle, keyPrefix: 'howto'),
                  SizedBox(height: pillGap),
                  SegmentedTabs<HowToTab>(
                    values: HowToTab.values,
                    labelOf: (t) => switch (t) {
                      HowToTab.pieces => piecesTabLabel,
                      HowToTab.rules => rulesTabLabel,
                    },
                    selected: _tab,
                    onChanged: _show,
                    keyPrefix: 'howto',
                    scale: s,
                  ),
                  SizedBox(height: pillGap),
                  switch (_tab) {
                    HowToTab.pieces => ValueListenableBuilder<BoardOptions>(
                      valueListenable: board,
                      builder: (_, options, _) =>
                          _PieceCards(options: options, scale: s),
                    ),
                    HowToTab.rules => _RuleCards(scale: s),
                  },
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

/// A CSS `font: <weight> <size>/<line-height>` at [scale], with CSS's
/// half-leading so the line boxes match the design's.
TextStyle _font(
  String family,
  FontWeight weight,
  double size,
  double lineHeight,
  Color colour,
  double scale, {
  double letterSpacingEm = 0,
}) => TextStyle(
  fontFamily: family,
  fontWeight: weight,
  fontSize: size * scale,
  height: lineHeight,
  leadingDistribution: TextLeadingDistribution.even,
  letterSpacing: letterSpacingEm * size * scale,
  color: colour,
);

class _PieceCards extends StatelessWidget {
  const _PieceCards({required this.options, required this.scale});

  final BoardOptions options;
  final double scale;

  @override
  Widget build(BuildContext context) {
    final s = scale;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (i, MapEntry(key: kind, value: text))
            in pieceRules.entries.indexed) ...[
          if (i > 0) SizedBox(height: 9 * s),
          MergeSemantics(
            child: Container(
              key: Key('howto-piece-${kind.name}'),
              padding: EdgeInsets.symmetric(
                vertical: 13 * s,
                horizontal: 14 * s,
              ),
              decoration: BoxDecoration(
                color: Palette.cardFill,
                borderRadius: BorderRadius.circular(13 * s),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    key: Key('howto-piece-square-${kind.name}'),
                    width: 34 * s,
                    height: 34 * s,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: i.isOdd
                          ? options.theme.light
                          : Palette.pieceCardSquare,
                      borderRadius: BorderRadius.circular(9 * s),
                    ),
                    child: PieceGlyph(
                      piece: Piece.of(Colour.black, kind),
                      style: options.pieceStyle,
                      fontSize: 21 * s,
                      colour: Palette.pieceBlack,
                      shadows: const [],
                      textKey: Key('howto-piece-glyph-${kind.name}'),
                    ),
                  ),
                  SizedBox(width: 12 * s),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          text.name,
                          style: _font(
                            Fonts.outfit,
                            FontWeight.w600,
                            13,
                            1,
                            const Color(0xFFFFFFFF),
                            s,
                          ),
                        ),
                        SizedBox(height: 6 * s),
                        Text(
                          text.body,
                          style: _font(
                            Fonts.outfit,
                            FontWeight.w400,
                            11.5,
                            1.5,
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

/// The key suffix for a card's [tag]: lower case, spaces as hyphens.
String _slug(String tag) => tag.toLowerCase().replaceAll(' ', '-');

class _RuleCards extends StatelessWidget {
  const _RuleCards({required this.scale});

  final double scale;

  @override
  Widget build(BuildContext context) {
    final s = scale;
    final radius = BorderRadius.circular(13 * s);
    final padding = EdgeInsets.symmetric(vertical: 14 * s, horizontal: 15 * s);
    TextStyle kicker(Color colour) => _font(
      Fonts.plexMono,
      FontWeight.w500,
      9,
      1,
      colour,
      s,
      letterSpacingEm: .16,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (i, rule) in ruleCards.indexed) ...[
          Container(
            key: Key('howto-rule-${_slug(rule.tag)}'),
            padding: padding,
            decoration: BoxDecoration(
              color: i == 0 ? Palette.tealTint : Palette.cardFill,
              borderRadius: radius,
            ),
            // The design's inset ring takes no room, so it is drawn over
            // the card rather than as a border inside it.
            foregroundDecoration: i == 0
                ? BoxDecoration(
                    borderRadius: radius,
                    border: Border.all(color: Palette.tealRing),
                  )
                : null,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Semantics(
                  header: true,
                  child: Text(
                    rule.tag,
                    style: kicker(i == 0 ? Palette.teal : Palette.kicker),
                  ),
                ),
                SizedBox(height: 9 * s),
                Text(
                  rule.body,
                  style: _font(
                    Fonts.outfit,
                    FontWeight.w400,
                    12.5,
                    1.6,
                    Palette.textPale,
                    s,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: 11 * s),
        ],
        Container(
          key: const Key('howto-gestures'),
          padding: padding,
          decoration: BoxDecoration(
            color: Palette.cardFill,
            borderRadius: radius,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(
                header: true,
                child: Text(gesturesKicker, style: kicker(Palette.kicker)),
              ),
              for (final (i, gesture) in gestures.indexed) ...[
                SizedBox(height: i == 0 ? 11 * s : 8 * s),
                MergeSemantics(
                  child: Row(
                    key: Key('howto-gesture-${_slug(gesture.tag)}'),
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Container(
                        padding: EdgeInsets.symmetric(
                          vertical: 5 * s,
                          horizontal: 8 * s,
                        ),
                        decoration: BoxDecoration(
                          color: Palette.tealFillSelected,
                          borderRadius: BorderRadius.circular(7 * s),
                        ),
                        child: Text(
                          gesture.tag,
                          style: _font(
                            Fonts.plexMono,
                            FontWeight.w500,
                            9.5,
                            1,
                            Palette.teal,
                            s,
                          ),
                        ),
                      ),
                      SizedBox(width: 10 * s),
                      Expanded(
                        child: Text(
                          gesture.body,
                          style: _font(
                            Fonts.outfit,
                            FontWeight.w400,
                            11.5,
                            1.45,
                            Palette.textLead,
                            s,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
