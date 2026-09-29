import 'package:flutter/material.dart';

import 'package:honest_chess/engine/engine.dart';
import 'package:honest_chess/ui/game/game_controller.dart';
import 'package:honest_chess/ui/game/labels.dart';
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

/// The card's line after the computer declines: "Club declines — play on".
String declineText(Strength step) => '${step.label} declines — play on';

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
const Color _hintInk = Color(0x80FFFFFF);

/// The design's Paused card over a scrim that also covers the top bar,
/// shown while [controller] is paused and the game goes on. The board stays
/// visible behind it. Resume — or a tap on the scrim, or Android's back —
/// restarts the clocks; the draw button offers a draw; Resign resigns.
/// The design's Rules, Settings and Main menu buttons are left out until
/// M4 provides their screens. While the computer considers a draw, every
/// way off the card is shut.
///
/// A layer of the play screen, like the promotion sheet: with the game
/// unpaused it draws nothing and takes no touches.
class PauseOverlay extends StatefulWidget {
  const PauseOverlay({super.key, required this.controller});

  final GameController controller;

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

  @override
  void initState() {
    super.initState();
    _controller.addListener(_sync);
    _show.addStatusListener((status) {
      if (status == AnimationStatus.dismissed && mounted) setState(() {});
    });
    _track();
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
      if (!_show.isForwardOrCompleted) _show.forward();
    } else if (_show.isForwardOrCompleted) {
      _show.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    final open = _open;
    final asking = _controller.state.drawAsking;
    return PopScope(
      canPop: !open,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _controller.resume();
      },
      child: !open && _show.isDismissed
          ? const SizedBox.shrink()
          : IgnorePointer(
              ignoring: !open,
              child: FadeTransition(
                key: const Key('pause-overlay'),
                opacity: _eased,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
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
                        child: _card(asking),
                      ),
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
    final declined = switch (game.mode) {
      VsComputer(:final step) when _controller.state.drawDeclined =>
        declineText(step),
      _ => null,
    };
    return Semantics(
      key: const Key('pause-card'),
      container: true,
      explicitChildNodes: true,
      child: DecoratedBox(
        decoration: const BoxDecoration(
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
        ),
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Semantics(
                header: true,
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
                style: const TextStyle(
                  fontFamily: Fonts.plexMono,
                  fontWeight: FontWeight.w500,
                  fontSize: 10,
                  height: 1,
                  letterSpacing: 1.4,
                  color: Palette.textDim,
                ),
              ),
              // Always in the tree, so a screen reader hears the decline
              // as the live region's text changes.
              Semantics(
                liveRegion: true,
                child: declined == null
                    ? const SizedBox(height: 0)
                    : Padding(
                        padding: const EdgeInsets.only(top: 14),
                        child: Text(
                          declined,
                          key: const Key('pause-declined'),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontFamily: Fonts.outfit,
                            fontWeight: FontWeight.w500,
                            fontSize: 13,
                            height: 1.2,
                            color: Palette.textBody,
                          ),
                        ),
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
                    color: _hintInk,
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
            ],
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
