import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../data/app_store.dart';
import '../../data/game_saves.dart';
import '../app_scope.dart';
import '../board/board_view.dart' show designWidth;
import '../brand/honest_mark.dart';
import '../game/labels.dart';
import '../navigation.dart';
import '../theme/palette.dart';
import '../widgets/screen_background.dart';

/// The menu's texts, as the design writes them.
const menuKickerText = 'BY HONEST ARCADE · NO ADS';
const computerCardTitle = 'vs Computer';
const computerCardSubtitle = 'Five strength steps · pick your colour';
const twoCardTitle = 'Two players';
const twoCardSubtitle = 'One phone, pass it across';
const aboutArcadeBarTitle = 'About Honest Arcade';
const aboutArcadeBarSubtitle = 'No ads, no tracking, open source.';
const damagedDataText =
    "Some saved data couldn't be read. The app started fresh for it.";
const dismissText = 'Dismiss';

/// The menu scales by the width over the design's 390, the width capped here.
const menuScaleCapWidth = 480.0;

/// The smallest height a tappable takes.
const _minTouch = 48.0;

/// Continue's label for [offered]: "Continue vs Club", or "Continue
/// two-player".
String continueLabel(OfferedGame offered) => switch (offered.step) {
  final step? => 'Continue vs ${step.label}',
  null => 'Continue two-player',
};

/// Continue's meta line: the fullmove number and the side to move,
/// "MOVE 12 · WHITE".
String continueMeta(OfferedGame offered) =>
    'MOVE ${offered.fullmove} · ${offered.sideToMove.label.toUpperCase()}';

/// How far a tappable drawn [drawn] high reaches past its drawn box, above
/// and below, to be [_minTouch] to touch.
double _spill(double drawn) => math.max(0, (_minTouch - drawn) / 2);

/// A CSS `font: <weight> <size>/<line-height>` at [scale], with CSS's
/// half-leading.
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

/// The main menu, the app's first route: Continue for the saved game in
/// progress, the two ways to start a game, and every other screen one tap
/// away. It has no `PopScope`: back here is the navigator's own pop, which
/// leaves the app.
class MenuScreen extends StatelessWidget {
  const MenuScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    // Screen text ignores the system text scale, as the board does, until
    // M5's accessibility work.
    return MediaQuery.withNoTextScaling(
      child: Scaffold(
        backgroundColor: Palette.screenBg,
        resizeToAvoidBottomInset: false,
        body: ScreenBackground(
          gradient: ScreenGradient.menu,
          child: SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final s =
                    math.min(constraints.maxWidth, menuScaleCapWidth) /
                    designWidth;
                return ListenableBuilder(
                  listenable: Listenable.merge([
                    scope.saves,
                    scope.store.corruptionNotices,
                  ]),
                  builder: (context, _) => _MenuBody(
                    scale: s,
                    offered: scope.saves.offered,
                    notices: scope.store.corruptionNotices.value,
                    store: scope.store,
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

class _MenuBody extends StatelessWidget {
  const _MenuBody({
    required this.scale,
    required this.offered,
    required this.notices,
    required this.store,
  });

  final double scale;
  final OfferedGame? offered;
  final Set<StoreDoc> notices;
  final AppStore store;

  @override
  Widget build(BuildContext context) {
    final s = scale;
    final gap = 16 * s;
    final offered = this.offered;
    // Each part with how far its touch area reaches past its drawn box;
    // the gap around it gives up that much, so the drawn spacing stays the
    // design's.
    final parts = <(Widget, double)>[
      (_Header(scale: s), 0),
      if (notices.isNotEmpty)
        (_Banner(scale: s, onDismiss: store.dismissNotices), _Banner.spill(s)),
      if (offered != null)
        (
          _ContinueButton(scale: s, offered: offered),
          _spill(_ContinueButton.drawnHeight(s)),
        ),
      (_ModeCards(scale: s), 0),
      (_ScreenButtons(scale: s), _spill(_ScreenButtons.drawnHeight(s))),
    ];
    final bar = _AboutArcadeBar(scale: s);
    final barSpill = _spill(_AboutArcadeBar.drawnHeight(s));
    final children = <Widget>[];
    for (var i = 0; i < parts.length; i++) {
      final (part, spill) = parts[i];
      if (i > 0) {
        children.add(
          SizedBox(height: math.max(0.0, gap - parts[i - 1].$2 - spill)),
        );
      }
      children.add(part);
    }
    return CustomScrollView(
      key: const Key('menu-scroll'),
      slivers: [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Padding(
            // The design's 64 dp top padding, less its 44 dp status bar
            // (SafeArea's here); 24 dp above the bottom inset.
            padding: EdgeInsets.fromLTRB(22 * s, 20, 22 * s, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ...children,
                // The design's `margin-top: auto`: the bar sits at the
                // bottom when everything fits and follows the content when
                // it scrolls.
                SizedBox(height: math.max(0.0, gap - parts.last.$2 - barSpill)),
                const Spacer(),
                bar,
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.scale});

  final double scale;

  @override
  Widget build(BuildContext context) {
    final s = scale;
    final wordmark = _font(
      Fonts.outfit,
      FontWeight.w700,
      27,
      1,
      const Color(0xFFFFFFFF),
      s,
      letterSpacingEm: -.03,
    );
    return Row(
      children: [
        HonestMark.chess(52 * s, key: const Key('menu-mark')),
        SizedBox(width: 14 * s),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(
                header: true,
                label: 'Honest Chess',
                excludeSemantics: true,
                child: Text.rich(
                  key: const Key('menu-wordmark'),
                  TextSpan(
                    text: 'Honest',
                    style: wordmark,
                    children: [
                      TextSpan(
                        text: 'Chess',
                        style: wordmark.copyWith(color: Palette.teal),
                      ),
                    ],
                  ),
                ),
              ),
              SizedBox(height: 7 * s),
              Text(
                menuKickerText,
                key: const Key('menu-kicker'),
                style: _font(
                  Fonts.plexMono,
                  FontWeight.w500,
                  9,
                  1,
                  Palette.textDim,
                  s,
                  letterSpacingEm: .24,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// A tappable part of the menu: one semantics button reading [label], its
/// drawn box built by [builder] with whether it is pressed, and a touch
/// area [spill] taller above and below than the drawn box.
class _Tappable extends StatefulWidget {
  const _Tappable({
    required this.tapKey,
    required this.label,
    required this.onTap,
    required this.builder,
    this.spill = 0,
  });

  final Key tapKey;
  final String label;
  final VoidCallback onTap;
  final Widget Function(BuildContext context, bool pressed) builder;
  final double spill;

  @override
  State<_Tappable> createState() => _TappableState();
}

class _TappableState extends State<_Tappable> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed != value) setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: widget.label,
      onTap: widget.onTap,
      excludeSemantics: true,
      child: Listener(
        onPointerDown: (_) => _setPressed(true),
        onPointerUp: (_) => _setPressed(false),
        onPointerCancel: (_) => _setPressed(false),
        child: GestureDetector(
          key: widget.tapKey,
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: widget.spill),
            child: widget.builder(context, _pressed),
          ),
        ),
      ),
    );
  }
}

/// #80's notice that a document could not be read: the message and
/// Dismiss, announced when it shows, until Dismiss clears the store's
/// notices.
class _Banner extends StatefulWidget {
  const _Banner({required this.scale, required this.onDismiss});

  final double scale;
  final VoidCallback onDismiss;

  static double _lineHeight(double s) => 12.5 * 1.3 * s;

  /// How far the banner's slot reaches past its drawn box, so Dismiss is
  /// [_minTouch] to touch while the message is one line.
  static double spill(double s) => _spill(24 * s + _lineHeight(s));

  @override
  State<_Banner> createState() => _BannerState();
}

class _BannerState extends State<_Banner> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed != value) setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.scale;
    final spill = _Banner.spill(s);
    TextStyle style(FontWeight weight, Color colour) =>
        _font(Fonts.outfit, weight, 12.5, 1.3, colour, s);
    final dismiss = style(FontWeight.w600, Palette.dangerText);
    return Stack(
      key: const Key('menu-banner'),
      children: [
        Padding(
          padding: EdgeInsets.symmetric(vertical: spill),
          child: Semantics(
            liveRegion: true,
            container: true,
            child: Container(
              key: const Key('menu-banner-box'),
              padding: EdgeInsets.symmetric(
                vertical: 12 * s,
                horizontal: 14 * s,
              ),
              decoration: BoxDecoration(
                color: Palette.resignFill,
                border: Border.all(color: Palette.resignEdge),
                borderRadius: BorderRadius.circular(14 * s),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      damagedDataText,
                      key: const Key('menu-banner-text'),
                      style: style(FontWeight.w400, Palette.dangerText),
                    ),
                  ),
                  SizedBox(width: 12 * s),
                  ExcludeSemantics(
                    child: Text(
                      dismissText,
                      key: const Key('menu-banner-dismiss-text'),
                      style: _pressed
                          ? dismiss.copyWith(color: Palette.teal)
                          : dismiss,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        // Dismiss's touch area: invisible, over the drawn word, the
        // banner's right padding and half the gap before it, the slot's
        // full height, and never narrower than the minimum.
        Positioned(
          top: 0,
          bottom: 0,
          right: 0,
          child: Semantics(
            button: true,
            label: dismissText,
            onTap: widget.onDismiss,
            excludeSemantics: true,
            child: Listener(
              onPointerDown: (_) => _setPressed(true),
              onPointerUp: (_) => _setPressed(false),
              onPointerCancel: (_) => _setPressed(false),
              child: GestureDetector(
                key: const Key('menu-banner-dismiss'),
                behavior: HitTestBehavior.opaque,
                onTap: widget.onDismiss,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minWidth: _minTouch),
                  child: Padding(
                    padding: EdgeInsets.only(left: 6 * s, right: 14 * s),
                    child: Center(
                      widthFactor: 1,
                      child: Opacity(
                        opacity: 0,
                        child: Text(dismissText, style: dismiss),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ContinueButton extends StatelessWidget {
  const _ContinueButton({required this.scale, required this.offered});

  final double scale;
  final OfferedGame offered;

  static double drawnHeight(double s) => (18 * 2 + 18) * s;

  @override
  Widget build(BuildContext context) {
    final s = scale;
    final label = continueLabel(offered);
    final meta = continueMeta(offered);
    return _Tappable(
      tapKey: const Key('menu-continue'),
      label: '$label, $meta',
      spill: _spill(drawnHeight(s)),
      onTap: () => unawaited(continueGame(context)),
      builder: (context, pressed) => Container(
        key: const Key('menu-continue-box'),
        padding: EdgeInsets.symmetric(vertical: 18 * s, horizontal: 20 * s),
        decoration: BoxDecoration(
          color: pressed ? Palette.tealPressed : Palette.teal,
          borderRadius: BorderRadius.circular(16 * s),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                key: const Key('menu-continue-label'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: _font(
                  Fonts.outfit,
                  FontWeight.w600,
                  18,
                  1,
                  Palette.onTeal,
                  s,
                ),
              ),
            ),
            SizedBox(width: 12 * s),
            Opacity(
              opacity: Palette.continueMetaOpacity,
              child: Text(
                meta,
                key: const Key('menu-continue-meta'),
                style: _font(
                  Fonts.plexMono,
                  FontWeight.w500,
                  11,
                  1,
                  Palette.onTeal,
                  s,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One square of a card's mini board: its colour and an optional glyph.
typedef _ArtSquare = ({Color fill, String? glyph, Color? ink});

class _ModeCard extends StatelessWidget {
  const _ModeCard({
    required this.scale,
    required this.tapKey,
    required this.title,
    required this.subtitle,
    required this.subtitleColour,
    required this.washStart,
    required this.washEnd,
    required this.squares,
    required this.accent,
    required this.onTap,
  });

  final double scale;
  final Key tapKey;
  final String title;
  final String subtitle;
  final Color subtitleColour;
  final Color washStart;
  final Color washEnd;

  /// The mini board's eight squares, the top row first.
  final List<_ArtSquare> squares;

  /// The border while pressed.
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = scale;
    final radius = BorderRadius.circular(16 * s);
    return _Tappable(
      tapKey: tapKey,
      label: '$title, $subtitle',
      onTap: onTap,
      builder: (context, pressed) => Container(
        decoration: BoxDecoration(
          color: Palette.cardFill,
          borderRadius: radius,
          border: Border.all(color: pressed ? accent : Palette.borderStrong),
        ),
        child: ClipRRect(
          // Inside the 1 dp border.
          borderRadius: BorderRadius.circular(16 * s - 1),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                height: 78 * s,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    // CSS's 150°: towards the bottom, a little right.
                    transform: const GradientRotation(math.pi / 3),
                    colors: [washStart, washEnd],
                  ),
                ),
                padding: EdgeInsets.only(left: 16 * s, top: 14 * s),
                alignment: Alignment.topLeft,
                child: ExcludeSemantics(child: _miniBoard(s)),
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(16 * s, 13 * s, 16 * s, 16 * s),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: _font(
                        Fonts.outfit,
                        FontWeight.w600,
                        16,
                        1,
                        const Color(0xFFFFFFFF),
                        s,
                      ),
                    ),
                    SizedBox(height: 6 * s),
                    Text(
                      subtitle,
                      style: _font(
                        Fonts.outfit,
                        FontWeight.w400,
                        11.5,
                        1.4,
                        subtitleColour,
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
    );
  }

  Widget _miniBoard(double s) {
    final side = 25 * s;
    Widget square(_ArtSquare sq) => Container(
      width: side,
      height: side,
      color: sq.fill,
      alignment: Alignment.center,
      child: sq.glyph == null
          ? null
          : Text(
              // U+FE0E asks for the text form, as the board's glyphs do.
              '${sq.glyph}\u{FE0E}',
              style: _font(Fonts.pieces, FontWeight.w400, 19, 1, sq.ink!, s),
            ),
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var row = 0; row < 2; row++)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var c = 0; c < 4; c++) square(squares[row * 4 + c]),
            ],
          ),
      ],
    );
  }
}

class _ModeCards extends StatelessWidget {
  const _ModeCards({required this.scale});

  final double scale;

  @override
  Widget build(BuildContext context) {
    final s = scale;
    const light = Palette.textChoice, dark = Palette.computerArtBlue;
    const twoLight = Palette.twoArtLight, twoDark = Palette.twoArtDark;
    _ArtSquare plain(Color fill) => (fill: fill, glyph: null, ink: null);
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: _ModeCard(
              scale: s,
              tapKey: const Key('menu-vs-computer'),
              title: computerCardTitle,
              subtitle: computerCardSubtitle,
              subtitleColour: Palette.textBody,
              washStart: Palette.computerArtBlue,
              washEnd: Palette.onTeal,
              accent: Palette.teal,
              squares: [
                plain(light),
                plain(dark),
                plain(light),
                plain(dark),
                plain(dark),
                (fill: light, glyph: '♞', ink: Palette.artInkDark),
                plain(dark),
                plain(light),
              ],
              onTap: () => unawaited(openScreen(context, computerSetupRoute())),
            ),
          ),
          SizedBox(width: 11 * s),
          Expanded(
            child: _ModeCard(
              scale: s,
              tapKey: const Key('menu-two-players'),
              title: twoCardTitle,
              subtitle: twoCardSubtitle,
              subtitleColour: Palette.violetText,
              washStart: Palette.twoArtWashStart,
              washEnd: Palette.twoArtWashEnd,
              accent: Palette.violet,
              squares: [
                (fill: twoLight, glyph: '♛', ink: Palette.artInkDark),
                plain(twoDark),
                plain(twoLight),
                plain(twoDark),
                plain(twoDark),
                plain(twoLight),
                (fill: twoDark, glyph: '♕', ink: Palette.artInkLight),
                plain(twoLight),
              ],
              onTap: () =>
                  unawaited(openScreen(context, twoPlayerSetupRoute())),
            ),
          ),
        ],
      ),
    );
  }
}

/// Statistics, How to play, Settings and About the app, two by two.
class _ScreenButtons extends StatelessWidget {
  const _ScreenButtons({required this.scale});

  final double scale;

  static double drawnHeight(double s) => (15 * 2 + 14) * s;

  @override
  Widget build(BuildContext context) {
    final s = scale;
    final spill = _spill(drawnHeight(s));
    Widget button(String key, String label, Route<void> Function() route) =>
        Expanded(
          child: _Tappable(
            tapKey: Key('menu-$key'),
            label: label,
            spill: spill,
            onTap: () => unawaited(openScreen(context, route())),
            builder: (context, pressed) => Container(
              padding: EdgeInsets.symmetric(
                vertical: 15 * s,
                horizontal: 16 * s,
              ),
              decoration: BoxDecoration(
                color: Palette.optionFill,
                borderRadius: BorderRadius.circular(14 * s),
                border: Border.all(
                  color: pressed ? Palette.teal : Palette.borderIdle,
                ),
              ),
              child: Text(
                label,
                style: _font(
                  Fonts.outfit,
                  FontWeight.w500,
                  14,
                  1,
                  const Color(0xFFFFFFFF),
                  s,
                ),
              ),
            ),
          ),
        );
    return Column(
      children: [
        Row(
          children: [
            button('statistics', 'Statistics', statsRoute),
            SizedBox(width: 10 * s),
            button('how-to-play', 'How to play', howToPlayRoute),
          ],
        ),
        SizedBox(height: math.max(0.0, 10 * s - 2 * spill)),
        Row(
          children: [
            button('settings', 'Settings', settingsRoute),
            SizedBox(width: 10 * s),
            button('about-app', 'About the app', aboutAppRoute),
          ],
        ),
      ],
    );
  }
}

class _AboutArcadeBar extends StatelessWidget {
  const _AboutArcadeBar({required this.scale});

  final double scale;

  static double drawnHeight(double s) => (15 * 2 + 13.5 + 6 + 11 * 1.3) * s;

  @override
  Widget build(BuildContext context) {
    final s = scale;
    return _Tappable(
      tapKey: const Key('menu-about-arcade'),
      label: '$aboutArcadeBarTitle, $aboutArcadeBarSubtitle',
      spill: _spill(drawnHeight(s)),
      onTap: () => unawaited(openScreen(context, aboutArcadeRoute())),
      builder: (context, pressed) => Container(
        key: const Key('menu-about-arcade-box'),
        padding: EdgeInsets.symmetric(vertical: 15 * s, horizontal: 16 * s),
        decoration: BoxDecoration(
          color: pressed ? Palette.tealBarPressed : Palette.tealPanelFill,
          borderRadius: BorderRadius.circular(14 * s),
          border: Border.all(color: Palette.tealBarEdge),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    aboutArcadeBarTitle,
                    style: _font(
                      Fonts.outfit,
                      FontWeight.w600,
                      13.5,
                      1,
                      Palette.teal,
                      s,
                    ),
                  ),
                  SizedBox(height: 6 * s),
                  Text(
                    aboutArcadeBarSubtitle,
                    style: _font(
                      Fonts.outfit,
                      FontWeight.w400,
                      11,
                      1.3,
                      Palette.textMuted,
                      s,
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(width: 12 * s),
            ExcludeSemantics(
              child: Text(
                '›',
                key: const Key('menu-about-arcade-chevron'),
                style: _font(
                  Fonts.outfit,
                  FontWeight.w500,
                  16,
                  1,
                  Palette.teal,
                  s,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
