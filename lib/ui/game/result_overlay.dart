import 'dart:async';

import 'package:flutter/material.dart';

import 'package:honest_chess/ui/board/board_view.dart' show boardMargin;
import 'package:honest_chess/ui/game/game_controller.dart';
import 'package:honest_chess/ui/game/pause_overlay.dart' show CardButton;
import 'package:honest_chess/ui/game/result_text.dart';
import 'package:honest_chess/ui/theme/palette.dart';

/// How long after a game-ending move the card appears, so the final move
/// can be seen landing. Endings off the board show the card at once.
const Duration resultDelay = Duration(milliseconds: 600);

/// The card's entry (the design's `hc-rise .35s`), and its fade on View
/// board.
const Duration resultRiseDuration = Duration(milliseconds: 350);
const Duration resultFadeDuration = Duration(milliseconds: 150);

/// How far below its place the card starts as it rises in.
const double resultRise = 8;

/// The result bar's height in view-board mode.
const double resultBarHeight = 56;

/// The card's inset from the screen's edges, and its widest.
const double resultInset = 26, resultMaxWidth = 440;

/// The finished game's result: the design's card over a scrim — who won
/// and why, the rule in a sentence, the game's numbers, Rematch and View
/// board — or, after View board, a slim bar over the top of the screen
/// with the result and Rematch, the final position frozen below it and the
/// tool row still live. The design's See statistics and Main menu buttons
/// are left out until M4 provides their screens.
///
/// A tap on the scrim, or Android's back, does what View board does; a tap
/// on the bar, or back again, brings the card back. The last layer of the
/// play screen: while the game goes on it draws nothing and takes no
/// touches.
class ResultOverlay extends StatefulWidget {
  const ResultOverlay({super.key, required this.controller});

  final GameController controller;

  @override
  State<ResultOverlay> createState() => _ResultOverlayState();
}

class _ResultOverlayState extends State<ResultOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _show = AnimationController(
    vsync: this,
    duration: resultRiseDuration,
    reverseDuration: resultFadeDuration,
  );

  late final Animation<double> _eased = CurvedAnimation(
    parent: _show,
    curve: Curves.easeOut,
  );

  /// The view last tracked; null before the first and while the game goes
  /// on.
  ResultView? _seen;
  bool _tracked = false;
  Timer? _delay;

  /// The system's animations are off: no delay, no rise, no fade.
  bool _still = false;

  GameController get _controller => widget.controller;

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
    _still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (!_tracked) {
      _tracked = true;
      _track();
    }
  }

  @override
  void didUpdateWidget(ResultOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_sync);
      widget.controller.addListener(_sync);
      _seen = null;
      _track();
    }
  }

  @override
  void dispose() {
    _delay?.cancel();
    _controller.removeListener(_sync);
    _show.dispose();
    super.dispose();
  }

  void _sync() => setState(_track);

  /// A new ending shows the card — after [resultDelay] when a move ended
  /// the game; a return from the bar shows it at once. View board fades it
  /// out; a re-opened or new game removes it at once, pending or not.
  void _track() {
    final view = _controller.state.resultView;
    final before = _seen;
    _seen = view;
    if (view == before) return;
    _delay?.cancel();
    _delay = null;
    switch (view) {
      case ResultView.card
          when before == null && !_still && endedByMove(_controller.game):
        _delay = Timer(resultDelay, () {
          if (mounted) setState(_appear);
        });
      case ResultView.card:
        _appear();
      case ResultView.board when !_still:
        _show.reverse();
      case ResultView.board || null:
        _show.value = 0;
    }
  }

  void _appear() {
    _delay = null;
    if (_still) {
      _show.value = 1;
    } else {
      _show.forward(from: 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    _still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final state = _controller.state;
    final view = state.resultView;
    return PopScope(
      canPop: view == null,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (!_controller.viewBoard()) _controller.showResult();
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (!_show.isDismissed)
            IgnorePointer(
              ignoring: view != ResultView.card,
              child: FadeTransition(
                key: const Key('result-overlay'),
                opacity: _eased,
                child: _layer(),
              ),
            ),
          if (view == ResultView.board)
            Positioned(
              left: boardMargin,
              right: boardMargin,
              top: 0,
              height: resultBarHeight,
              child: _bar(),
            ),
        ],
      ),
    );
  }

  ResultText get _text {
    final game = _controller.game;
    return describeResult(game.status, game.mode, resultYou(game));
  }

  static Color _kicker(ResultText text) =>
      text.lost ? Palette.alarm : Palette.teal;

  Widget _layer() {
    return Stack(
      fit: StackFit.expand,
      children: [
        Semantics(
          label: 'View board',
          button: true,
          child: GestureDetector(
            key: const Key('result-scrim'),
            behavior: HitTestBehavior.opaque,
            onTap: _controller.viewBoard,
            child: const ColoredBox(color: Palette.resultScrim),
          ),
        ),
        Center(
          child: Padding(
            padding: const EdgeInsets.all(resultInset),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: resultMaxWidth),
              child: SingleChildScrollView(
                child: AnimatedBuilder(
                  animation: _eased,
                  builder: (context, card) => Transform.translate(
                    // Only the entry rises; the exit is a plain fade.
                    offset: Offset(
                      0,
                      _show.status == AnimationStatus.reverse
                          ? 0
                          : resultRise * (1 - _eased.value),
                    ),
                    child: card,
                  ),
                  child: _card(),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _card() {
    final text = _text;
    final stats = resultStats(_controller.game);
    Widget row(int first) => IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: _StatTile(stat: stats[first], index: first),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: _StatTile(stat: stats[first + 1], index: first + 1),
          ),
        ],
      ),
    );
    return Semantics(
      key: const Key('result-card'),
      container: true,
      explicitChildNodes: true,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            // CSS 170°: from just left of top to just right of bottom.
            begin: Alignment(-0.17, -1),
            end: Alignment(0.17, 1),
            colors: [Palette.card, Palette.resultCardEnd],
          ),
          borderRadius: BorderRadius.all(Radius.circular(20)),
          border: Border.fromBorderSide(BorderSide(color: Palette.resultEdge)),
          boxShadow: [
            BoxShadow(
              color: Palette.cardShadow,
              offset: Offset(0, 24),
              blurRadius: 60,
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Inserted afresh each time the card appears, so a screen
              // reader hears the result on every showing.
              Semantics(
                liveRegion: true,
                container: true,
                header: true,
                label: '${text.tag}, ${text.title}',
                excludeSemantics: true,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      text.tag,
                      key: const Key('result-tag'),
                      style: TextStyle(
                        fontFamily: Fonts.plexMono,
                        fontWeight: FontWeight.w500,
                        fontSize: 10,
                        height: 1,
                        letterSpacing: 10 * .2,
                        color: _kicker(text),
                      ),
                    ),
                    const SizedBox(height: 11),
                    Text(
                      text.title,
                      key: const Key('result-title'),
                      style: const TextStyle(
                        fontFamily: Fonts.outfit,
                        fontWeight: FontWeight.w700,
                        fontSize: 26,
                        height: 1.1,
                        letterSpacing: 26 * -.02,
                        color: Color(0xFFFFFFFF),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Text(
                text.body,
                key: const Key('result-body'),
                style: const TextStyle(
                  fontFamily: Fonts.outfit,
                  fontWeight: FontWeight.w400,
                  fontSize: 12.5,
                  height: 1.55,
                  color: Palette.resultBody,
                ),
              ),
              const SizedBox(height: 18),
              row(0),
              const SizedBox(height: 9),
              row(2),
              const SizedBox(height: 18),
              CardButton(
                buttonKey: const Key('result-rematch'),
                label: 'Rematch',
                fill: Palette.teal,
                edge: null,
                ink: Palette.resumeInk,
                weight: FontWeight.w600,
                fontSize: 15,
                padding: 15,
                autofocus: true,
                onTap: _controller.restart,
              ),
              const SizedBox(height: 9),
              CardButton(
                buttonKey: const Key('result-view-board'),
                label: 'View board',
                fill: Palette.panelDim,
                edge: Palette.choiceEdge,
                ink: const Color(0xFFFFFFFF),
                fontSize: 13.5,
                padding: 13,
                onTap: _controller.viewBoard,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _bar() {
    final text = _text;
    const radius = BorderRadius.all(Radius.circular(14));
    return Semantics(
      key: const Key('result-bar'),
      container: true,
      explicitChildNodes: true,
      child: Material(
        color: Palette.card,
        shape: const RoundedRectangleBorder(
          borderRadius: radius,
          side: BorderSide(color: Palette.cardEdge),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: const Key('result-bar-show'),
          borderRadius: radius,
          onTap: _controller.showResult,
          child: Padding(
            padding: const EdgeInsets.only(left: 14, right: 8),
            child: Row(
              children: [
                Expanded(
                  child: Semantics(
                    button: true,
                    label: 'Show the result: ${text.tag}, ${text.title}',
                    onTap: _controller.showResult,
                    excludeSemantics: true,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          text.tag,
                          key: const Key('result-bar-tag'),
                          maxLines: 1,
                          style: TextStyle(
                            fontFamily: Fonts.plexMono,
                            fontWeight: FontWeight.w500,
                            fontSize: 10,
                            height: 1,
                            letterSpacing: 10 * .2,
                            color: _kicker(text),
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          text.title,
                          key: const Key('result-bar-title'),
                          maxLines: 1,
                          softWrap: false,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontFamily: Fonts.outfit,
                            fontWeight: FontWeight.w600,
                            fontSize: 16,
                            height: 1.1,
                            color: Color(0xFFFFFFFF),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Semantics(
                  button: true,
                  label: 'Rematch',
                  excludeSemantics: true,
                  child: Material(
                    color: Palette.teal,
                    shape: const RoundedRectangleBorder(
                      borderRadius: BorderRadius.all(Radius.circular(11)),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      key: const Key('result-bar-rematch'),
                      onTap: _controller.restart,
                      child: const Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        child: Text(
                          'Rematch',
                          style: TextStyle(
                            fontFamily: Fonts.outfit,
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                            height: 1,
                            color: Palette.resumeInk,
                          ),
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
}

/// One of the card's numbers: its label over its value, read aloud as
/// "Moves, 24".
class _StatTile extends StatelessWidget {
  const _StatTile({required this.stat, required this.index});

  final ResultStat stat;
  final int index;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: stat.spoken,
      excludeSemantics: true,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          color: Palette.statFill,
          borderRadius: BorderRadius.all(Radius.circular(12)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                stat.label,
                key: Key('result-stat-label-$index'),
                style: const TextStyle(
                  fontFamily: Fonts.plexMono,
                  fontWeight: FontWeight.w500,
                  fontSize: 9,
                  height: 1,
                  letterSpacing: 9 * .14,
                  color: Palette.byline,
                ),
              ),
              const SizedBox(height: 7),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  stat.value,
                  key: Key('result-stat-value-$index'),
                  maxLines: 1,
                  style: const TextStyle(
                    fontFamily: Fonts.outfit,
                    fontWeight: FontWeight.w600,
                    fontSize: 18,
                    height: 1,
                    color: Color(0xFFFFFFFF),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
