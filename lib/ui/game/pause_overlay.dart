import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:honest_chess/engine/engine.dart';
import 'package:honest_chess/ui/game/game_controller.dart';
import 'package:honest_chess/ui/game/labels.dart';
import 'package:honest_chess/ui/game/result_overlay.dart' show resultMaxWidth;
import 'package:honest_chess/ui/motion.dart';
import 'package:honest_chess/ui/theme/palette.dart';

/// How long the pause card and its scrim take to fade in, and out.
const Duration pauseFadeDuration = Duration(milliseconds: 200);

/// The pause card's line under its title: "VS CLUB · RAPID 10+5 · MOVE 12",
/// or "TWO PLAYERS · UNTIMED · MOVE 1"; the move is the position's
/// fullmove number.
String pauseMeta(Game game) {
  final who = switch (game.mode) {
    VsComputer(:final step) => 'VS ${step.label.toUpperCase()}',
    TwoPlayer() => 'TWO PLAYERS',
  };
  return '$who · ${game.clock.control.label} · '
      'MOVE ${game.position.fullmoveNumber}';
}

/// The draw button's label: the computer is asked, two players agree.
String drawLabel(GameMode mode) =>
    mode is VsComputer ? 'Claim a draw' : 'Agree a draw';

/// The caption under the draw button while it cannot be pressed; null when
/// it can, or while the computer is answering (the button's spinner says
/// that).
String? drawHint(DrawOffer offer) => switch (offer) {
  DrawOffer.tooEarly => 'After both sides have moved',
  DrawOffer.afterNextMove => 'After your next move',
  DrawOffer.open || DrawOffer.asking || DrawOffer.over => null,
};

/// A card button's opacity while it cannot be pressed, as a disabled
/// tool's.
const double disabledPauseButtonOpacity = 0.4;

/// The card text colour at half strength: the draw hint's colour.

/// The design's Paused card over a scrim that also covers the top bar,
/// shown while [controller] is paused and the game goes on. The board stays
/// visible behind it. Resume — or a tap on the scrim — restarts the
/// clocks; the draw button offers a draw; Resign resigns; Rules, Settings
/// and Main menu call [onRules], [onSettings] and [onMainMenu]. While the
/// computer considers a draw, every way off the card is shut. Once it
/// declines, the declined-draw card takes the pause card's place: it says
/// only that, and play resumes on its Resume button alone — the scrim is
/// inert under it (#160). Android's back is the play screen's to handle.
///
/// A layer of the play screen, like the promotion sheet: with the game
/// unpaused it draws nothing and takes no touches. The card is at most
/// [resultMaxWidth] wide, as the result card, and scrolls on a short
/// screen.
class PauseOverlay extends StatefulWidget {
  const PauseOverlay({
    super.key,
    required this.controller,
    required this.onRules,
    required this.onSettings,
    required this.onMainMenu,
  });

  final GameController controller;
  final VoidCallback onRules;
  final VoidCallback onSettings;
  final VoidCallback onMainMenu;

  @override
  State<PauseOverlay> createState() => _PauseOverlayState();
}

class _PauseOverlayState extends State<PauseOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _show = AnimationController(
    vsync: this,
    duration: pauseFadeDuration,
  );

  late final Animation<double> _eased = CurvedAnimation(
    parent: _show,
    curve: Curves.easeOut,
  );

  GameController get _controller => widget.controller;

  bool get _open => _controller.state.paused && !_controller.state.over;

  /// Motion is off: the card appears and goes at once.
  bool _still = false;
  bool _tracked = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_sync);
    _show.addStatusListener((status) {
      if (status == AnimationStatus.dismissed && mounted) setState(() {});
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _still = Motion.of(context).isOff;
    if (!_tracked) {
      _tracked = true;
      _track();
    }
  }

  @override
  void didUpdateWidget(PauseOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_sync);
      widget.controller.addListener(_sync);
      _track();
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_sync);
    _show.dispose();
    super.dispose();
  }

  void _sync() => setState(_track);

  void _track() {
    if (_open) {
      if (_still) {
        _show.value = 1;
      } else if (!_show.isForwardOrCompleted) {
        _show.forward();
      }
    } else if (_still) {
      _show.value = 0;
    } else if (_show.isForwardOrCompleted) {
      _show.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    final open = _open;
    final asking = _controller.state.drawAsking;
    final declined = switch (_controller.game.mode) {
      VsComputer(:final step) when _controller.state.drawDeclined => step,
      _ => null,
    };
    if (!open && _show.isDismissed) return const SizedBox.shrink();
    return IgnorePointer(
      ignoring: !open,
      child: FadeTransition(
        key: const Key('pause-overlay'),
        opacity: _eased,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (declined != null)
              GestureDetector(
                key: const Key('pause-scrim'),
                behavior: HitTestBehavior.opaque,
                excludeFromSemantics: true,
                child: const ColoredBox(color: Palette.scrim),
              )
            else
              Semantics(
                label: 'Resume',
                button: true,
                enabled: !asking,
                child: GestureDetector(
                  key: const Key('pause-scrim'),
                  behavior: HitTestBehavior.opaque,
                  onTap: asking ? null : _controller.resume,
                  child: const ColoredBox(color: Palette.scrim),
                ),
              ),
            Center(
              child: Padding(
                padding: const EdgeInsets.all(26),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: resultMaxWidth),
                  child: SingleChildScrollView(
                    key: const Key('pause-scroll'),
                    child: declined == null
                        ? _card(asking)
                        : _declinedCard(declined),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static const _cardLook = BoxDecoration(
    color: Palette.cardSurface,
    borderRadius: BorderRadius.all(Radius.circular(20)),
    border: Border.fromBorderSide(BorderSide(color: Palette.cardEdge)),
    boxShadow: [
      BoxShadow(
        color: Palette.cardShadow,
        offset: Offset(0, 24),
        blurRadius: 60,
      ),
    ],
  );

  /// The card that says the computer declined the draw, with one way off
  /// it: Resume, focused as the card comes up.
  Widget _declinedCard(Strength step) {
    return Semantics(
      key: const Key('declined-card'),
      container: true,
      explicitChildNodes: true,
      child: DecoratedBox(
        decoration: _cardLook,
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Semantics(
                container: true,
                header: true,
                headingLevel: 2,
                child: Text(
                  declineText(step),
                  key: const Key('pause-declined'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontFamily: Fonts.outfit,
                    fontWeight: FontWeight.w600,
                    fontSize: 19,
                    height: 1.25,
                    color: Color(0xFFFFFFFF),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              CardButton(
                buttonKey: const Key('declined-resume'),
                label: 'Resume',
                fill: Palette.teal,
                edge: null,
                ink: Palette.onTeal,
                weight: FontWeight.w600,
                fontSize: 15,
                padding: 15,
                autofocus: true,
                onTap: _controller.resume,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _card(bool asking) {
    final game = _controller.game;
    final offer = _controller.drawOffer;
    final hint = drawHint(offer);
    return Semantics(
      key: const Key('pause-card'),
      container: true,
      explicitChildNodes: true,
      child: DecoratedBox(
        decoration: _cardLook,
        child: Padding(
          padding: EdgeInsets.fromLTRB(22, 22, 22, 22 - _menuReachBelow),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Semantics(
                container: true,
                header: true,
                headingLevel: 2,
                child: const Text(
                  'Paused',
                  style: TextStyle(
                    fontFamily: Fonts.outfit,
                    fontWeight: FontWeight.w600,
                    fontSize: 19,
                    height: 1,
                    color: Color(0xFFFFFFFF),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                pauseMeta(game),
                key: const Key('pause-meta'),
                semanticsLabel: spokenCaps(pauseMeta(game)),
                style: const TextStyle(
                  fontFamily: Fonts.plexMono,
                  fontWeight: FontWeight.w500,
                  fontSize: 10,
                  height: 1,
                  letterSpacing: 1.4,
                  color: Palette.textDim,
                ),
              ),
              const SizedBox(height: 18),
              CardButton(
                buttonKey: const Key('pause-resume'),
                label: 'Resume',
                fill: Palette.teal,
                edge: null,
                ink: Palette.onTeal,
                weight: FontWeight.w600,
                fontSize: 15,
                padding: 15,
                autofocus: true,
                onTap: asking ? null : _controller.resume,
              ),
              const SizedBox(height: 9),
              CardButton(
                buttonKey: const Key('pause-draw'),
                label: drawLabel(game.mode),
                fill: Palette.drawFill,
                edge: Palette.drawEdge,
                ink: const Color(0xFFFFFFFF),
                onTap: offer == DrawOffer.open
                    ? () => _controller.offerDraw().ignore()
                    : null,
                busy: asking,
              ),
              if (hint != null) ...[
                const SizedBox(height: 6),
                Text(
                  hint,
                  key: const Key('pause-draw-hint'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontFamily: Fonts.plexMono,
                    fontSize: 11,
                    height: 1,
                    color: Palette.hintInk,
                  ),
                ),
              ],
              const SizedBox(height: 9),
              CardButton(
                buttonKey: const Key('pause-resign'),
                label: 'Resign',
                fill: Palette.resignFill,
                edge: Palette.resignEdge,
                ink: Palette.dangerText,
                onTap: asking ? null : _controller.resign,
              ),
              const SizedBox(height: cardHalfGap),
              Row(
                children: [
                  Expanded(
                    child: CardLinkButton(
                      id: 'pause-rules',
                      label: 'Rules',
                      look: _outlined,
                      reachAbove: cardHalfGap,
                      reachBelow: cardHalfGap,
                      onTap: asking ? null : widget.onRules,
                    ),
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: CardLinkButton(
                      id: 'pause-settings',
                      label: 'Settings',
                      look: _outlined,
                      reachAbove: cardHalfGap,
                      reachBelow: cardHalfGap,
                      onTap: asking ? null : widget.onSettings,
                    ),
                  ),
                ],
              ),
              CardLinkButton(
                id: 'pause-main-menu',
                label: 'Main menu',
                look: _menuLook,
                reachAbove: cardHalfGap,
                reachBelow: _menuReachBelow,
                onTap: asking ? null : widget.onMainMenu,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// The design's Rules and Settings: two equal outlined buttons.
  static const _outlined = CardLinkLook(
    fill: Palette.optionFill,
    edge: Palette.borderIdle,
    ink: Palette.textBody,
    fontSize: 13,
    padding: 13,
  );

  /// The design's Main menu: a text button.
  static const _menuLook = CardLinkLook(
    ink: Palette.textDim,
    fontSize: 13,
    padding: 13,
  );

  /// Main menu's hit area below its drawn button, taken from the card's
  /// bottom padding.
  static final double _menuReachBelow = _menuLook.reachBelow(
    above: cardHalfGap,
  );
}

/// Half the design's 9 dp gap between two stacked card buttons: each half
/// belongs to the hit area of the button beside it, so stacked hit areas
/// meet at the gap's midpoint and never overlap.
const double cardHalfGap = 4.5;

/// The least height of a card button's hit area.
const double cardMinTouch = 48;

/// How a [CardLinkButton] is drawn: outlined when [edge] is set, else a
/// text button. Its drawn height is the design's: one line of [fontSize]
/// text, [padding] above and below, and the 1 dp border when outlined.
class CardLinkLook {
  const CardLinkLook({
    this.fill,
    this.edge,
    required this.ink,
    required this.fontSize,
    required this.padding,
  });

  final Color? fill;
  final Color? edge;
  final Color ink;
  final double fontSize;
  final double padding;

  double get drawnHeight => fontSize + 2 * padding + (edge == null ? 0 : 2);

  /// The hit area a button reaching [above] its drawn box still needs below
  /// it to be [cardMinTouch] tall.
  double reachBelow({required double above}) =>
      math.max(0, cardMinTouch - above - drawnHeight);
}

/// A card's secondary button — the pause card's Rules, Settings and Main
/// menu, the result card's See statistics and Main menu — drawn at the
/// design's size, its hit area reaching [reachAbove] and [reachBelow]
/// beyond the drawn box without moving it. Pressed, an outlined button's
/// border turns teal, a text button's text. A tap takes focus first, so
/// focus comes back to the button when a screen it opened closes.
class CardLinkButton extends StatefulWidget {
  const CardLinkButton({
    super.key,
    required this.id,
    required this.label,
    required this.look,
    required this.onTap,
    this.reachAbove = 0,
    this.reachBelow = 0,
  });

  /// The button's key, `Key(id)`; its drawn box is `Key('<id>-box')`.
  final String id;
  final String label;
  final CardLinkLook look;
  final VoidCallback? onTap;
  final double reachAbove;
  final double reachBelow;

  @override
  State<CardLinkButton> createState() => _CardLinkButtonState();
}

class _CardLinkButtonState extends State<CardLinkButton> {
  late final FocusNode _focus = FocusNode(debugLabel: widget.id);
  bool _pressed = false;

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  void _tap() {
    _focus.requestFocus();
    widget.onTap?.call();
  }

  @override
  Widget build(BuildContext context) {
    final look = widget.look;
    final enabled = widget.onTap != null;
    final pressed = _pressed && enabled;
    final edge = look.edge;
    const radius = BorderRadius.all(Radius.circular(13));
    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.label,
      onTap: enabled ? _tap : null,
      excludeSemantics: true,
      child: Opacity(
        opacity: enabled ? 1 : disabledPauseButtonOpacity,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            key: Key(widget.id),
            focusNode: _focus,
            onTap: enabled ? _tap : null,
            onHighlightChanged: (on) => setState(() => _pressed = on),
            splashFactory: NoSplash.splashFactory,
            overlayColor: const WidgetStatePropertyAll(Color(0x00000000)),
            child: Padding(
              padding: EdgeInsets.only(
                top: widget.reachAbove,
                bottom: widget.reachBelow,
              ),
              child: Container(
                key: Key('${widget.id}-box'),
                height: look.drawnHeight,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: look.fill,
                  borderRadius: radius,
                  border: edge == null
                      ? null
                      : Border.all(color: pressed ? Palette.teal : edge),
                ),
                child: Text(
                  widget.label,
                  maxLines: 1,
                  style: TextStyle(
                    fontFamily: Fonts.outfit,
                    fontWeight: FontWeight.w500,
                    fontSize: look.fontSize,
                    height: 1,
                    color: edge == null && pressed ? Palette.teal : look.ink,
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

/// A card's full-width button — the pause card's and the result card's —
/// dimmed while it cannot be pressed; [busy] shows a spinner beside the
/// label.
class CardButton extends StatelessWidget {
  const CardButton({
    super.key,
    required this.buttonKey,
    required this.label,
    required this.fill,
    required this.edge,
    required this.ink,
    required this.onTap,
    this.weight = FontWeight.w500,
    this.fontSize = 14,
    this.padding = 14,
    this.autofocus = false,
    this.busy = false,
  });

  final Key buttonKey;
  final String label;
  final Color fill;
  final Color? edge;
  final Color ink;
  final FontWeight weight;
  final double fontSize;
  final double padding;
  final bool autofocus;
  final bool busy;
  final VoidCallback? onTap;

  static const _radius = BorderRadius.all(Radius.circular(13));

  @override
  Widget build(BuildContext context) {
    final edge = this.edge;
    return Semantics(
      button: true,
      enabled: onTap != null,
      label: busy ? '$label, waiting for the answer' : label,
      onTap: onTap,
      excludeSemantics: true,
      child: Opacity(
        opacity: onTap == null && !busy ? disabledPauseButtonOpacity : 1,
        child: Material(
          color: fill,
          shape: RoundedRectangleBorder(
            borderRadius: _radius,
            side: edge == null ? BorderSide.none : BorderSide(color: edge),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            key: buttonKey,
            autofocus: autofocus,
            borderRadius: _radius,
            onTap: onTap,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 48),
              child: Padding(
                padding: EdgeInsets.all(padding),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (busy) ...[
                      SizedBox.square(
                        dimension: fontSize,
                        child: CircularProgressIndicator(
                          key: const Key('pause-draw-spinner'),
                          strokeWidth: 2,
                          color: ink,
                        ),
                      ),
                      const SizedBox(width: 10),
                    ],
                    Text(
                      label,
                      style: TextStyle(
                        fontFamily: Fonts.outfit,
                        fontWeight: weight,
                        fontSize: fontSize,
                        height: 1,
                        color: ink,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
