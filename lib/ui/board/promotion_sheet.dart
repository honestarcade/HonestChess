import 'package:flutter/material.dart';

import 'package:honest_chess/engine/engine.dart';
import 'package:honest_chess/ui/board/board_options.dart';
import 'package:honest_chess/ui/board/board_view.dart';
import 'package:honest_chess/ui/game/game_controller.dart';
import 'package:honest_chess/ui/theme/palette.dart';

/// How long the card and its scrim take to appear (the design's `hc-rise`).
const Duration promotionEnterDuration = Duration(milliseconds: 250);

/// How long the card and its scrim take to fade away.
const Duration promotionExitDuration = Duration(milliseconds: 150);

/// How far below its place the card starts as it rises in.
const double promotionRise = 8;

/// The pieces offered, in the design's order.
const List<PieceKind> promotionChoices = [
  PieceKind.queen,
  PieceKind.rook,
  PieceKind.bishop,
  PieceKind.knight,
];

/// The design's "Promote to" card over a scrim, shown while [controller]
/// has a promotion pending. A choice completes the move; a tap on the
/// scrim or Android's back cancels it. It is a layer of the play screen,
/// not a route: it fills the space it is given and, with nothing pending,
/// draws nothing and takes no touches.
class PromotionSheet extends StatefulWidget {
  const PromotionSheet({super.key, required this.controller});

  final GameController controller;

  @override
  State<PromotionSheet> createState() => _PromotionSheetState();
}

class _PromotionSheetState extends State<PromotionSheet>
    with SingleTickerProviderStateMixin {
  late final AnimationController _show = AnimationController(
    vsync: this,
    duration: promotionEnterDuration,
    reverseDuration: promotionExitDuration,
  );

  late final Animation<double> _eased = CurvedAnimation(
    parent: _show,
    curve: Curves.easeOut,
  );

  /// The promotion drawn, kept through the exit fade after the controller
  /// has cleared it.
  PendingPromotion? _shown;
  Piece? _pawn;

  GameController get _controller => widget.controller;

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
  void didUpdateWidget(PromotionSheet oldWidget) {
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

  /// Starts the entry when a promotion opens and the exit when it closes.
  void _track() {
    final pending = _controller.state.pendingPromotion;
    if (pending != null) {
      if (pending != _shown) {
        _shown = pending;
        _pawn = _controller.state.position.pieceAt(pending.from);
        _show.forward(from: 0);
      }
    } else if (_shown != null) {
      _shown = null;
      _show.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    final open = _controller.state.pendingPromotion != null;
    final pawn = _pawn;
    final pending = _shown ?? _controller.state.pendingPromotion;
    final visible = pawn != null && (open || !_show.isDismissed);
    return PopScope(
      canPop: !open,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _controller.cancelPromotion();
      },
      child: !visible
          ? const SizedBox.shrink()
          : IgnorePointer(
              ignoring: !open,
              child: FadeTransition(
                opacity: _eased,
                child: _layer(pawn, pending),
              ),
            ),
    );
  }

  Widget _layer(Piece pawn, PendingPromotion? pending) {
    final square = (pending?.to.name ?? '').toUpperCase();
    return Stack(
      fit: StackFit.expand,
      children: [
        Semantics(
          label: 'Cancel promotion',
          button: true,
          child: GestureDetector(
            key: const Key('promo-scrim'),
            behavior: HitTestBehavior.opaque,
            onTap: _controller.cancelPromotion,
            child: const ColoredBox(color: Palette.scrim),
          ),
        ),
        Center(
          child: Padding(
            padding: const EdgeInsets.all(26),
            child: AnimatedBuilder(
              animation: _eased,
              builder: (context, card) => Transform.translate(
                // Only the entry rises; the exit is a plain fade.
                offset: Offset(
                  0,
                  _show.status == AnimationStatus.reverse
                      ? 0
                      : promotionRise * (1 - _eased.value),
                ),
                child: card,
              ),
              child: _card(pawn, square),
            ),
          ),
        ),
      ],
    );
  }

  Widget _card(Piece pawn, String square) {
    return Semantics(
      key: const Key('promo-card'),
      container: true,
      liveRegion: true,
      label: 'Promote pawn on $square',
      child: DecoratedBox(
        decoration: const BoxDecoration(
          color: Palette.card,
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
              // The card's own label says both lines to a screen reader.
              const ExcludeSemantics(
                child: Text(
                  'Promote to',
                  style: TextStyle(
                    fontFamily: Fonts.outfit,
                    fontWeight: FontWeight.w600,
                    fontSize: 18,
                    height: 1,
                    color: Color(0xFFFFFFFF),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              ExcludeSemantics(
                child: Text(
                  'PAWN TO $square',
                  key: const Key('promo-meta'),
                  style: const TextStyle(
                    fontFamily: Fonts.plexMono,
                    fontWeight: FontWeight.w500,
                    fontSize: 10,
                    height: 1,
                    letterSpacing: 1.4,
                    color: Palette.textDim,
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  for (final (i, kind) in promotionChoices.indexed) ...[
                    if (i > 0) const SizedBox(width: 9),
                    Expanded(
                      child: _PromotionChoice(
                        piece: Piece.of(pawn.colour, kind),
                        style: _controller.options.pieceStyle,
                        onPick: () => _controller.choosePromotion(kind),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One of the card's four buttons: the piece over its name.
class _PromotionChoice extends StatefulWidget {
  const _PromotionChoice({
    required this.piece,
    required this.style,
    required this.onPick,
  });

  final Piece piece;
  final PieceStyle style;
  final VoidCallback onPick;

  @override
  State<_PromotionChoice> createState() => _PromotionChoiceState();
}

class _PromotionChoiceState extends State<_PromotionChoice> {
  bool _pressed = false;

  static const _radius = BorderRadius.all(Radius.circular(13));

  @override
  Widget build(BuildContext context) {
    final kind = widget.piece.kind;
    return Semantics(
      button: true,
      label: 'Promote to ${kind.name}',
      excludeSemantics: true,
      child: Material(
        color: Palette.choiceFill,
        shape: RoundedRectangleBorder(
          borderRadius: _radius,
          side: BorderSide(color: _pressed ? Palette.teal : Palette.choiceEdge),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: Key('promo-${kind.letter}'),
          borderRadius: _radius,
          splashColor: Palette.teal.withValues(alpha: 0.2),
          highlightColor: Palette.teal.withValues(alpha: 0.2),
          onHighlightChanged: (pressed) => setState(() => _pressed = pressed),
          onTap: widget.onPick,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Padding(
              padding: const EdgeInsets.only(top: 14, bottom: 11),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  PieceGlyph(
                    piece: widget.piece,
                    style: widget.style,
                    fontSize: 28,
                    textKey: Key('promo-piece-${kind.letter}'),
                  ),
                  const SizedBox(height: 9),
                  Text(
                    kind.name.toUpperCase(),
                    style: const TextStyle(
                      fontFamily: Fonts.plexMono,
                      fontWeight: FontWeight.w500,
                      fontSize: 9,
                      height: 1,
                      letterSpacing: 0.9,
                      color: Palette.textBody,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
