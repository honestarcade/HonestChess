import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../board/board_options.dart';
import '../game/defaults.dart';
import '../game/labels.dart';
import '../navigation.dart';
import '../theme/palette.dart';
import '../widgets/screen_header.dart';
import '../widgets/setting_row.dart';
import '../widgets/time_control_picker.dart';
import '../widgets/titled_section.dart';

/// The Time control card's note, from the design.
/// The house rules card's kicker.
const houseRulesKicker = 'HOUSE RULES';

const twoPlayerTimeNote = 'Both clocks sit on the board, the running one lit.';

/// The rotate row's text: Settings' switch under the design's own wording
/// for this screen.
const rotateLabel = 'Rotate board each turn';
const rotateDescription =
    'Turn the board to face whoever is to move. Off keeps white at the '
    'bottom.';

/// The house-rules note, reworded from the design to what the board does:
/// its first sentence follows Settings' Takeback allowed.
String houseRulesText({required bool takebackAllowed}) {
  final takeback = takebackAllowed
      ? 'Takeback is shared — either player can undo the last move.'
      : 'Takeback is off in Settings.';
  return '$takeback Either player can agree a draw from the pause card '
      'with one tap. Everything else is tournament legal.';
}

/// "Two players": the time control and whether the board turns to face
/// whoever is to move, then Start game — a pass-and-play game on a new
/// board. The time choice is #83's stored setup choice, written at every
/// tap; the rotate switch is the board setting Settings shows.
class TwoPlayerSetupScreen extends StatelessWidget {
  const TwoPlayerSetupScreen({super.key});

  Future<void> _start(BuildContext context) async {
    final choices = AppScope.of(context).settings.setup.value;
    await startGame(context, choices.twoPlayerSetup());
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final settings = scope.settings;
    final guard = scope.navigation;
    return Scaffold(
      backgroundColor: Palette.screenBg,
      body: SafeArea(
        child: ListenableBuilder(
          listenable: Listenable.merge([settings.setup, settings.board]),
          builder: (context, _) {
            final choices = settings.setup.value;
            final BoardOptions board = settings.board.value;
            return CustomScrollView(
              key: const Key('psetup-scroll'),
              slivers: [
                SliverPadding(
                  // The design's 56 dp top padding, less its 44 dp status
                  // bar (SafeArea's here).
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                  sliver: SliverList.list(
                    children: [
                      const ScreenHeader(
                        title: 'Two players',
                        kicker: 'ONE PHONE · PASS AND PLAY',
                        kickerColor: Palette.kickerViolet,
                        keyPrefix: 'psetup',
                        accent: Accent.violet,
                      ),
                      const SizedBox(height: 13),
                      TitledSection(
                        title: 'Time control',
                        intro: twoPlayerTimeNote,
                        child: TimeControlPicker(
                          keyPrefix: 'psetup',
                          accent: Accent.violet,
                          selected: choices.two.time,
                          custom: choices.custom,
                          onChanged: (time, minutes, increment) =>
                              settings.updateSetup(
                                (s) => s.copyWith(
                                  two: s.two.copyWith(time: time),
                                  custom: CustomTime(
                                    minutes: minutes,
                                    increment: increment,
                                  ),
                                ),
                              ),
                        ),
                      ),
                      const SizedBox(height: 13),
                      SettingRow(
                        key: const Key('psetup-rotate'),
                        label: rotateLabel,
                        description: rotateDescription,
                        value: board.rotateEachTurn,
                        accent: Accent.violet,
                        padding: const EdgeInsets.symmetric(
                          vertical: 13,
                          horizontal: 15,
                        ),
                        radius: 14,
                        onChanged: () => settings.updateBoard(
                          (o) => o.copyWith(rotateEachTurn: !o.rotateEachTurn),
                        ),
                      ),
                      const SizedBox(height: 13),
                      _HouseRules(takebackAllowed: board.takebackAllowed),
                    ],
                  ),
                ),
                // The design pins Start game with margin-top:auto: at the
                // bottom when the cards fit, after them when not.
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

class _HouseRules extends StatelessWidget {
  const _HouseRules({required this.takebackAllowed});

  final bool takebackAllowed;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 15),
      decoration: BoxDecoration(
        color: Palette.optionFill,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            container: true,
            header: true,
            headingLevel: 2,
            child: Text(
              houseRulesKicker,
              semanticsLabel: spokenCaps(houseRulesKicker),
              style: const TextStyle(
                fontFamily: Fonts.plexMono,
                fontWeight: FontWeight.w500,
                fontSize: 9,
                height: 1,
                letterSpacing: 9 * .16,
                color: Palette.kicker,
              ),
            ),
          ),
          const SizedBox(height: 9),
          // Its own node, so a screen reader reads it after the
          // heading (#147).
          Semantics(
            container: true,
            child: Text(
              houseRulesText(takebackAllowed: takebackAllowed),
              key: const Key('psetup-house-rules'),
              style: const TextStyle(
                fontFamily: Fonts.outfit,
                fontWeight: FontWeight.w400,
                fontSize: 11,
                height: 1.5,
                color: Palette.textMuted,
              ),
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
        key: const Key('psetup-start'),
        behavior: HitTestBehavior.opaque,
        onTap: widget.onPressed,
        onTapDown: (_) => _setPressed(true),
        onTapUp: (_) => _setPressed(false),
        onTapCancel: () => _setPressed(false),
        child: Container(
          key: const Key('psetup-start-fill'),
          padding: const EdgeInsets.all(17),
          decoration: BoxDecoration(
            color: _pressed ? Palette.violetPressed : Palette.violet,
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
              color: Color(0xFFFFFFFF),
            ),
          ),
        ),
      ),
    );
  }
}
