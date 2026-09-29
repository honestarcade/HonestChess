import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../data/play_mode.dart';
import '../app_scope.dart';
import '../board/board_view.dart' show designWidth;
import '../content/stats_view.dart';
import '../game/pause_overlay.dart' show disabledPauseButtonOpacity;
import '../theme/palette.dart';
import '../widgets/option_button.dart';
import '../motion.dart';
import '../widgets/screen_header.dart';
import '../widgets/segmented_tabs.dart';

/// The widest screen the design's sizes scale up to.
const statsScaleCapWidth = 480.0;

/// How long the reset confirmation takes to rise in (the design's
/// `hc-rise`), and to fade out.
const resetEnterDuration = Duration(milliseconds: 250);
const resetExitDuration = Duration(milliseconds: 150);

/// How far the confirmation card rises as it appears.
const resetRise = 8.0;

/// The widest the confirmation card grows, as the result card.
const resetCardMaxWidth = 440.0;

/// The design's inset around the confirmation card.
const resetInset = 26.0;

/// Statistics: what the recorder has counted, per mode, in cards and bars,
/// and a reset that asks first. It opens on [openOn]'s tab, else on the
/// mode played last, else on vs Computer.
class StatsScreen extends StatefulWidget {
  const StatsScreen({super.key, this.openOn});

  final PlayMode? openOn;

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen>
    with SingleTickerProviderStateMixin {
  late PlayMode _tab;
  final _scroll = ScrollController();
  final _resetFocus = FocusNode(debugLabel: 'stats-reset');
  late final AnimationController _confirm = AnimationController(
    vsync: this,
    duration: resetEnterDuration,
    reverseDuration: resetExitDuration,
  );
  late final Animation<double> _eased = CurvedAnimation(
    parent: _confirm,
    curve: Curves.easeOut,
  );

  /// Whether the confirmation is up (it may still be fading in); false
  /// from the moment it starts to close.
  bool _open = false;

  /// Whether `resetAll()` is being awaited.
  bool _busy = false;

  /// Whether the last Reset failed.
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    final scope = AppScope.of(context);
    _tab = openingTab(widget.openOn, scope.saves.lastPlayed);
    scope.stats.load().ignore();
    _confirm.addStatusListener((status) {
      if (status == AnimationStatus.dismissed && mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _confirm.dispose();
    _resetFocus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  bool get _instant => Motion.of(context).isOff;

  void _show(PlayMode tab) {
    setState(() => _tab = tab);
    // A tab starts at its top, as the design's re-rendered scroll does.
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  void _announce(String message) =>
      AppScope.of(context).announcer.announce(message);

  void _ask() {
    if (_open) return;
    setState(() {
      _open = true;
      _failed = false;
    });
    if (_instant) {
      _confirm.value = 1;
    } else {
      _confirm.forward(from: 0);
    }
    _announce('$resetTitle $resetBody');
  }

  void _close() {
    if (!_open || _busy) return;
    setState(() {
      _open = false;
      _failed = false;
    });
    if (_instant) {
      _confirm.value = 0;
    } else {
      _confirm.reverse();
    }
    _resetFocus.requestFocus();
  }

  Future<void> _reset() async {
    if (!_open || _busy) return;
    setState(() {
      _busy = true;
      _failed = false;
    });
    final stats = AppScope.of(context).stats;
    try {
      await stats.resetAll();
    } on Object catch (_) {
      // StatsResetFailed: the statistics are unchanged, so the numbers
      // behind the card stay and the player may try again.
      if (mounted) {
        setState(() {
          _busy = false;
          _failed = true;
        });
      }
      return;
    }
    if (!mounted) return;
    setState(() => _busy = false);
    _close();
    _announce(resetDoneText);
  }

  @override
  Widget build(BuildContext context) {
    final stats = AppScope.of(context).stats;
    final s =
        math.min(MediaQuery.sizeOf(context).width, statsScaleCapWidth) /
        designWidth;
    return PopScope(
      canPop: !_open,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close();
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          Scaffold(
            backgroundColor: Palette.screenBg,
            body: SafeArea(
              child: ListenableBuilder(
                listenable: stats,
                builder: (context, _) =>
                    _body(statsView(stats.document, _tab), s),
              ),
            ),
          ),
          if (!_confirm.isDismissed || _open) _overlay(s),
        ],
      ),
    );
  }

  Widget _body(StatsView view, double s) {
    final pillGap = 13 * s - SegmentedTabs.overhang(s);
    return CustomScrollView(
      key: const Key('stats-scroll'),
      controller: _scroll,
      slivers: [
        SliverPadding(
          // The design's 56 dp top padding, less its 44 dp status bar
          // (SafeArea's here).
          padding: EdgeInsets.fromLTRB(20 * s, 12, 20 * s, 0),
          sliver: SliverList.list(
            children: [
              const ScreenHeader(title: statsTitle, keyPrefix: 'stats'),
              SizedBox(height: pillGap),
              SegmentedTabs<PlayMode>(
                values: PlayMode.values,
                labelOf: (mode) => switch (mode) {
                  PlayMode.computer => computerTabLabel,
                  PlayMode.two => twoTabLabel,
                },
                selected: _tab,
                onChanged: _show,
                keyPrefix: 'stats',
                scale: s,
              ),
              SizedBox(height: pillGap),
              _Cards(cards: view.cards, scale: s),
              SizedBox(height: 13 * s),
              _Breakdown(view: view, scale: s),
            ],
          ),
        ),
        // The design pins the button with margin-top:auto: at the bottom
        // when the cards fit, after them when not.
        SliverFillRemaining(
          hasScrollBody: false,
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              20 * s,
              13 * s - _Button.overhang(14, s),
              20 * s,
              30 * s - _Button.overhang(14, s),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Button(
                  keyName: 'stats-reset',
                  label: resetButtonText,
                  focusNode: _resetFocus,
                  fill: Palette.resignFill,
                  edge: Palette.resignEdge,
                  pressedEdge: Palette.danger,
                  ink: Palette.dangerText,
                  weight: FontWeight.w600,
                  padding: 14,
                  radius: 13,
                  scale: s,
                  onTap: _ask,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _overlay(double s) {
    final eased = _eased;
    final busy = _busy;
    return BlockSemantics(
      child: Material(
        type: MaterialType.transparency,
        child: IgnorePointer(
          ignoring: !_open,
          child: FadeTransition(
            key: const Key('stats-reset-overlay'),
            opacity: eased,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Semantics(
                  label: resetScrimLabel,
                  button: true,
                  enabled: !busy,
                  child: GestureDetector(
                    key: const Key('stats-reset-scrim'),
                    behavior: HitTestBehavior.opaque,
                    onTap: busy ? null : _close,
                    child: const ColoredBox(color: Palette.scrim),
                  ),
                ),
                SafeArea(
                  child: Center(
                    child: SingleChildScrollView(
                      padding: EdgeInsets.all(resetInset * s),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(
                          maxWidth: resetCardMaxWidth,
                        ),
                        child: AnimatedBuilder(
                          animation: eased,
                          builder: (context, card) => Transform.translate(
                            offset: Offset(
                              0,
                              _open ? resetRise * (1 - eased.value) : 0,
                            ),
                            child: card,
                          ),
                          child: _card(s, busy),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _card(double s, bool busy) {
    return Semantics(
      key: const Key('stats-reset-card'),
      container: true,
      explicitChildNodes: true,
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.fromLTRB(
          22 * s,
          22 * s,
          22 * s,
          22 * s - _Button.overhang(13, s),
        ),
        decoration: BoxDecoration(
          color: Palette.cardSurface,
          borderRadius: BorderRadius.circular(18 * s),
          boxShadow: [
            BoxShadow(
              color: Palette.confirmShadow,
              offset: Offset(0, 20 * s),
              blurRadius: 50 * s,
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              header: true,
              child: Text(
                resetTitle,
                key: const Key('stats-reset-title'),
                style: _font(Fonts.outfit, FontWeight.w600, 17, 1, s),
              ),
            ),
            SizedBox(height: 11 * s),
            Text(
              resetBody,
              key: const Key('stats-reset-body'),
              style: _font(
                Fonts.outfit,
                FontWeight.w400,
                12.5,
                1.55,
                s,
                colour: Palette.textLead,
              ),
            ),
            // Always in the tree, so a screen reader hears the failure as
            // the live region's text changes.
            Semantics(
              liveRegion: true,
              child: _failed
                  ? Padding(
                      padding: EdgeInsets.only(top: 12 * s),
                      child: Text(
                        resetFailedText,
                        key: const Key('stats-reset-error'),
                        style: _font(
                          Fonts.outfit,
                          FontWeight.w400,
                          12.5,
                          1.3,
                          s,
                          colour: Palette.dangerText,
                        ),
                      ),
                    )
                  : const SizedBox(height: 0),
            ),
            SizedBox(height: 18 * s - _Button.overhang(13, s)),
            Row(
              children: [
                Expanded(
                  child: _Button(
                    keyName: 'stats-reset-cancel',
                    label: resetCancelText,
                    autofocus: true,
                    fill: Palette.choiceFill,
                    edge: Palette.cancelEdge,
                    pressedEdge: Palette.teal,
                    ink: const Color(0xFFFFFFFF),
                    weight: FontWeight.w500,
                    padding: 13,
                    radius: 12,
                    scale: s,
                    onTap: busy ? null : _close,
                  ),
                ),
                SizedBox(width: 9 * s),
                Expanded(
                  child: _Button(
                    keyName: 'stats-reset-confirm',
                    label: resetConfirmText,
                    fill: Palette.danger,
                    pressedFill: Palette.dangerPressed,
                    ink: const Color(0xFFFFFFFF),
                    weight: FontWeight.w600,
                    padding: 13,
                    radius: 12,
                    scale: s,
                    onTap: busy ? null : _reset,
                  ),
                ),
              ],
            ),
          ],
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
  double scale, {
  Color colour = const Color(0xFFFFFFFF),
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

/// The two-column card grid: each row as tall as its taller card, as the
/// design's CSS grid stretches them.
class _Cards extends StatelessWidget {
  const _Cards({required this.cards, required this.scale});

  final List<StatCard> cards;
  final double scale;

  @override
  Widget build(BuildContext context) {
    final s = scale;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < cards.length; i += 2) ...[
          if (i > 0) SizedBox(height: 9 * s),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: _Card(card: cards[i], scale: s),
                ),
                SizedBox(width: 9 * s),
                Expanded(
                  child: i + 1 < cards.length
                      ? _Card(card: cards[i + 1], scale: s)
                      : const SizedBox.shrink(),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.card, required this.scale});

  final StatCard card;
  final double scale;

  @override
  Widget build(BuildContext context) {
    final s = scale;
    final key = 'stats-card-${card.name}';
    return Semantics(
      key: Key(key),
      container: true,
      label: card.spoken,
      excludeSemantics: true,
      child: Container(
        padding: EdgeInsets.all(14 * s),
        decoration: BoxDecoration(
          color: card.highlighted ? Palette.accentFill : Palette.cardFill,
          borderRadius: BorderRadius.circular(13 * s),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              card.kicker,
              key: Key('$key-kicker'),
              style: _font(
                Fonts.plexMono,
                FontWeight.w500,
                9,
                1,
                s,
                colour: Palette.textDim,
                letterSpacingEm: .14,
              ),
            ),
            SizedBox(height: 8 * s),
            // A number too wide for the card shrinks to fit, never cut.
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                card.value,
                key: Key('$key-value'),
                maxLines: 1,
                softWrap: false,
                style: _font(
                  Fonts.outfit,
                  FontWeight.w600,
                  21,
                  1,
                  s,
                  colour: card.highlighted
                      ? Palette.teal
                      : const Color(0xFFFFFFFF),
                ),
              ),
            ),
            SizedBox(height: 6 * s),
            Text(
              card.caption,
              key: Key('$key-caption'),
              style: _font(
                Fonts.outfit,
                FontWeight.w400,
                10.5,
                1.3,
                s,
                colour: Palette.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Breakdown extends StatelessWidget {
  const _Breakdown({required this.view, required this.scale});

  final StatsView view;
  final double scale;

  @override
  Widget build(BuildContext context) {
    final s = scale;
    return Container(
      key: const Key('stats-breakdown'),
      padding: EdgeInsets.all(15 * s),
      decoration: BoxDecoration(
        color: Palette.cardFill,
        borderRadius: BorderRadius.circular(13 * s),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: Text(
              view.breakdownTitle,
              key: const Key('stats-breakdown-title'),
              style: _font(
                Fonts.plexMono,
                FontWeight.w500,
                9.5,
                1,
                s,
                colour: Palette.kicker,
                letterSpacingEm: .16,
              ),
            ),
          ),
          for (final row in view.rows) ...[
            SizedBox(height: 10 * s),
            _Row(row: row, scale: s),
          ],
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.row, required this.scale});

  final StatRow row;
  final double scale;

  @override
  Widget build(BuildContext context) {
    final s = scale;
    final key = 'stats-row-${row.name}';
    final radius = BorderRadius.circular(3 * s);
    return Semantics(
      key: Key(key),
      container: true,
      label: row.spoken,
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                row.label,
                key: Key('$key-label'),
                maxLines: 1,
                softWrap: false,
                style: _font(
                  Fonts.outfit,
                  FontWeight.w500,
                  11.5,
                  1,
                  s,
                  colour: Palette.textChoice,
                ),
              ),
              SizedBox(width: 8 * s),
              // The value takes the rest of the row and shrinks to fit,
              // never cut.
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: Text(
                    row.value,
                    key: Key('$key-value'),
                    maxLines: 1,
                    softWrap: false,
                    style: _font(
                      Fonts.plexMono,
                      FontWeight.w500,
                      11.5,
                      1,
                      s,
                      colour: Palette.textBody,
                    ),
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 7 * s),
          ClipRRect(
            borderRadius: radius,
            child: Container(
              key: Key('$key-track'),
              height: 6 * s,
              color: Palette.barTrack,
              alignment: Alignment.centerLeft,
              child: FractionallySizedBox(
                key: Key('$key-bar'),
                widthFactor: row.fraction,
                heightFactor: 1,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: row.colour,
                    borderRadius: radius,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A full-width button of the screen and its card: [fill] and [edge] at
/// rest, [pressedFill] and [pressedEdge] while held, dimmed and inert with
/// no [onTap]. It is drawn at the design's size and touched across a slot
/// at least [OptionButton.minTouch] tall, centred on it; the screen takes
/// the [overhang] out of the space around it, so the drawn layout is the
/// design's.
class _Button extends StatefulWidget {
  const _Button({
    required this.keyName,
    required this.label,
    required this.fill,
    required this.ink,
    required this.weight,
    required this.padding,
    required this.radius,
    required this.scale,
    required this.onTap,
    this.edge,
    this.pressedFill,
    this.pressedEdge,
    this.focusNode,
    this.autofocus = false,
  });

  /// The InkWell's key; the drawn box's is this plus `-box`.
  final String keyName;
  final String label;
  final Color fill;
  final Color? edge;
  final Color? pressedFill;
  final Color? pressedEdge;
  final Color ink;
  final FontWeight weight;
  final double padding;
  final double radius;
  final double scale;
  final FocusNode? focusNode;
  final bool autofocus;
  final VoidCallback? onTap;

  static const labelSize = 13.0;

  /// The drawn height of a button with [padding] at [scale].
  static double drawnHeight(double padding, double scale) =>
      (2 * padding + labelSize) * scale;

  /// How far the touch slot reaches past the drawn button, above and below.
  static double overhang(double padding, double scale) {
    final drawn = drawnHeight(padding, scale);
    return (math.max(OptionButton.minTouch, drawn) - drawn) / 2;
  }

  @override
  State<_Button> createState() => _ButtonState();
}

class _ButtonState extends State<_Button> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final w = widget;
    final s = w.scale;
    final pressed = _pressed && w.onTap != null;
    final edge = pressed ? (w.pressedEdge ?? w.edge) : w.edge;
    final drawn = _Button.drawnHeight(w.padding, s);
    return Semantics(
      button: true,
      enabled: w.onTap != null,
      label: w.label,
      excludeSemantics: true,
      child: Opacity(
        opacity: w.onTap == null ? disabledPauseButtonOpacity : 1,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            key: Key(w.keyName),
            focusNode: w.focusNode,
            autofocus: w.autofocus,
            splashFactory: NoSplash.splashFactory,
            highlightColor: const Color(0x00000000),
            onHighlightChanged: (value) => setState(() => _pressed = value),
            onTap: w.onTap,
            child: SizedBox(
              height: drawn + 2 * _Button.overhang(w.padding, s),
              child: Center(
                child: Container(
                  key: Key('${w.keyName}-box'),
                  height: drawn,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: pressed ? (w.pressedFill ?? w.fill) : w.fill,
                    borderRadius: BorderRadius.circular(w.radius * s),
                    border: edge == null ? null : Border.all(color: edge),
                  ),
                  child: Text(
                    w.label,
                    maxLines: 1,
                    style: _font(
                      Fonts.outfit,
                      w.weight,
                      _Button.labelSize,
                      1,
                      s,
                      colour: w.ink,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
