import 'package:flutter/material.dart';

import '../../data/play_mode.dart';
import '../../data/stats_listener.dart';
import '../../engine/engine.dart';
import '../app_scope.dart';
import '../game/defaults.dart';
import '../game/labels.dart';
import '../navigation.dart';
import '../theme/palette.dart';
import '../widgets/option_button.dart';
import '../widgets/screen_header.dart';
import '../widgets/time_control_picker.dart';
import '../widgets/titled_section.dart';

/// The Strength card's intro, from the design.
const strengthIntro =
    'A plain engine with a dial. At the low steps it looks less far ahead '
    'and misses things on purpose — no fake blunders dressed up as '
    'personality.';

/// Shown under Start game while it would abandon a game you have moved in.
const lossWarningText = 'Your current game will count as a loss.';

/// The Play as choices' symbols: the piece font's kings, and ⁇, which
/// Outfit lacks, in text presentation from the platform's fallback font.
String colourGlyph(ColourChoice choice) => switch (choice) {
  ColourChoice.white => '♔\u{FE0E}',
  ColourChoice.black => '♚\u{FE0E}',
  ColourChoice.random => '⁇\u{FE0E}',
};

String _colourLabel(ColourChoice choice) => switch (choice) {
  ColourChoice.white => 'White',
  ColourChoice.black => 'Black',
  ColourChoice.random => 'Random',
};

/// "New game vs computer": the strength, your colour and the time control,
/// then Start game; or Keep playing the unfinished game against the
/// computer. It shows the setup choices as #83's store holds them and
/// writes every change there at once.
///
/// Opened from the board ([fromBoard]), back and Keep playing return to
/// that board; opened from the menu, Keep playing opens the board.
class ComputerSetupScreen extends StatelessWidget {
  const ComputerSetupScreen({super.key, this.fromBoard = false});

  final bool fromBoard;

  Future<void> _start(BuildContext context) async {
    final scope = AppScope.of(context);
    final choices = scope.settings.setup.value;
    final colour = switch (choices.computer.colour) {
      ColourChoice.white => Colour.white,
      ColourChoice.black => Colour.black,
      ColourChoice.random =>
        scope.random.nextBool() ? Colour.white : Colour.black,
    };
    await startGame(context, choices.computerSetup(colour));
  }

  Future<void> _keepPlaying(BuildContext context) async {
    final scope = AppScope.of(context);
    final navigator = Navigator.of(context);
    final controller = scope.controller;
    final saves = scope.saves;
    final live = !controller.isIdle && !controller.game.isOver
        ? controller.game
        : null;
    if (live == null || PlayMode.of(live.mode) != PlayMode.computer) {
      // The board holds no computer game: the saved one comes back, after
      // any two-player game on the board is saved where it will be found.
      if (live != null) await saves.save(live, controller.recorded);
      final saved = saves.load(PlayMode.computer);
      if (saved == null ||
          !controller.restore(
            saved,
            recorded: saves.recorded(PlayMode.computer),
          )) {
        return;
      }
    }
    controller.resume();
    if (fromBoard) {
      navigator.pop();
    } else if (context.mounted) {
      openBoard(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final settings = scope.settings;
    final saves = scope.saves;
    final controller = scope.controller;
    final guard = scope.navigation;
    return Scaffold(
      backgroundColor: Palette.screenBg,
      body: SafeArea(
        child: ListenableBuilder(
          listenable: Listenable.merge([settings.setup, saves, controller]),
          builder: (context, _) {
            final choices = settings.setup.value;
            void update(ComputerChoices Function(ComputerChoices) change) =>
                settings.updateSetup(
                  (s) => s.copyWith(computer: change(s.computer)),
                );
            final canKeepPlaying = saves.unfinished(PlayMode.computer) != null;
            final warn = wouldAbandon(controller, saves, PlayMode.computer);
            return CustomScrollView(
              key: const Key('csetup-scroll'),
              slivers: [
                SliverPadding(
                  // The design's 56 dp top padding, less its 44 dp status
                  // bar (SafeArea's here).
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                  sliver: SliverList.list(
                    children: [
                      const ScreenHeader(
                        title: 'New game vs computer',
                        kicker: 'RUNS ON DEVICE · NO NETWORK',
                        keyPrefix: 'csetup',
                      ),
                      const SizedBox(height: 13),
                      TitledSection(
                        title: 'Strength',
                        intro: strengthIntro,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            for (final step in Strength.values) ...[
                              if (step.index > 0) const SizedBox(height: 8),
                              _StrengthButton(
                                step: step,
                                selected: choices.computer.step == step,
                                onPressed: () =>
                                    update((c) => c.copyWith(step: step)),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 13),
                      TitledSection(
                        title: 'Play as',
                        child: Row(
                          children: [
                            for (final colour in ColourChoice.values) ...[
                              if (colour.index > 0) const SizedBox(width: 8),
                              Expanded(
                                child: _ColourButton(
                                  choice: colour,
                                  selected: choices.computer.colour == colour,
                                  onPressed: () =>
                                      update((c) => c.copyWith(colour: colour)),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 13),
                      TitledSection(
                        title: 'Time control',
                        child: TimeControlPicker(
                          keyPrefix: 'csetup',
                          selected: choices.computer.time,
                          custom: choices.custom,
                          onChanged: (time, minutes, increment) =>
                              settings.updateSetup(
                                (s) => s.copyWith(
                                  computer: s.computer.copyWith(time: time),
                                  custom: CustomTime(
                                    minutes: minutes,
                                    increment: increment,
                                  ),
                                ),
                              ),
                        ),
                      ),
                    ],
                  ),
                ),
                // The design pins the buttons with margin-top:auto: at
                // the bottom when the cards fit, after them when not.
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 13, 20, 30),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _StartButton(
                          onPressed: () => guard.run(() => _start(context)),
                        ),
                        if (warn) ...[
                          const SizedBox(height: 9),
                          const Text(
                            lossWarningText,
                            key: Key('csetup-loss-warning'),
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontFamily: Fonts.outfit,
                              fontWeight: FontWeight.w400,
                              fontSize: 11,
                              height: 1.3,
                              color: Palette.dangerText,
                            ),
                          ),
                        ],
                        if (canKeepPlaying) ...[
                          const SizedBox(height: 9),
                          _KeepPlayingButton(
                            onPressed: () =>
                                guard.run(() => _keepPlaying(context)),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _StrengthButton extends StatelessWidget {
  const _StrengthButton({
    required this.step,
    required this.selected,
    required this.onPressed,
  });

  final Strength step;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final rank = step.index + 1;
    return OptionButton(
      key: Key('csetup-strength-${step.name}'),
      selected: selected,
      onPressed: onPressed,
      padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 14),
      look: OptionLook.setup,
      child: Semantics(
        label:
            '${step.label}, step $rank of ${Strength.values.length}, '
            '${step.description}',
        child: ExcludeSemantics(
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      step.label,
                      style: const TextStyle(
                        fontFamily: Fonts.outfit,
                        fontWeight: FontWeight.w600,
                        fontSize: 13.5,
                        height: 1,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      step.description,
                      key: Key('csetup-strength-${step.name}-description'),
                      style: const TextStyle(
                        fontFamily: Fonts.outfit,
                        fontWeight: FontWeight.w400,
                        fontSize: 10.5,
                        height: 1.3,
                        color: Palette.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              for (var n = 0; n < Strength.values.length; n++) ...[
                if (n > 0) const SizedBox(width: 3),
                Container(
                  key: Key('csetup-pip-${step.name}-$n'),
                  width: 5,
                  height: 16,
                  decoration: BoxDecoration(
                    color: n < rank
                        ? (selected ? Palette.teal : Palette.textDim)
                        : Palette.borderSoft,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ColourButton extends StatelessWidget {
  const _ColourButton({
    required this.choice,
    required this.selected,
    required this.onPressed,
  });

  final ColourChoice choice;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final king = choice != ColourChoice.random;
    return OptionButton(
      key: Key('csetup-colour-${choice.name}'),
      selected: selected,
      onPressed: onPressed,
      padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 8),
      radius: 11,
      look: OptionLook.setup,
      child: Column(
        children: [
          // One fixed line for the three symbols, so the labels line up.
          ExcludeSemantics(
            child: SizedBox(
              height: 17,
              child: Center(
                child: Text(
                  colourGlyph(choice),
                  key: Key('csetup-colour-glyph-${choice.name}'),
                  textHeightBehavior: const TextHeightBehavior(
                    applyHeightToFirstAscent: false,
                    applyHeightToLastDescent: false,
                  ),
                  style: TextStyle(
                    fontFamily: king ? Fonts.pieces : Fonts.outfit,
                    fontFamilyFallback: king ? const [] : null,
                    fontWeight: FontWeight.w400,
                    fontSize: 17,
                    height: 1,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 7),
          Text(
            _colourLabel(choice),
            style: const TextStyle(
              fontFamily: Fonts.outfit,
              fontWeight: FontWeight.w600,
              fontSize: 12.5,
              height: 1,
            ),
          ),
        ],
      ),
    );
  }
}

class _StartButton extends StatefulWidget {
  const _StartButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  State<_StartButton> createState() => _StartButtonState();
}

class _StartButtonState extends State<_StartButton> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed != value) setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Start game',
      onTap: widget.onPressed,
      excludeSemantics: true,
      child: GestureDetector(
        key: const Key('csetup-start'),
        behavior: HitTestBehavior.opaque,
        onTap: widget.onPressed,
        onTapDown: (_) => _setPressed(true),
        onTapUp: (_) => _setPressed(false),
        onTapCancel: () => _setPressed(false),
        child: Container(
          padding: const EdgeInsets.all(17),
          decoration: BoxDecoration(
            color: _pressed ? Palette.tealPressed : Palette.teal,
            borderRadius: BorderRadius.circular(14),
          ),
          alignment: Alignment.center,
          child: const Text(
            'Start game',
            style: TextStyle(
              fontFamily: Fonts.outfit,
              fontWeight: FontWeight.w600,
              fontSize: 16,
              height: 1,
              color: Palette.onTeal,
            ),
          ),
        ),
      ),
    );
  }
}

class _KeepPlayingButton extends StatefulWidget {
  const _KeepPlayingButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  State<_KeepPlayingButton> createState() => _KeepPlayingButtonState();
}

class _KeepPlayingButtonState extends State<_KeepPlayingButton> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed != value) setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Keep playing the current game',
      onTap: widget.onPressed,
      excludeSemantics: true,
      child: GestureDetector(
        key: const Key('csetup-keep-playing'),
        behavior: HitTestBehavior.opaque,
        onTap: widget.onPressed,
        onTapDown: (_) => _setPressed(true),
        onTapUp: (_) => _setPressed(false),
        onTapCancel: () => _setPressed(false),
        child: Container(
          constraints: const BoxConstraints(minHeight: OptionButton.minTouch),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Palette.optionFill,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: _pressed ? Palette.teal : Palette.borderStrong,
            ),
          ),
          alignment: Alignment.center,
          child: const Text(
            'Keep playing the current game',
            style: TextStyle(
              fontFamily: Fonts.outfit,
              fontWeight: FontWeight.w500,
              fontSize: 13,
              height: 1,
              color: Palette.textBody,
            ),
          ),
        ),
      ),
    );
  }
}
