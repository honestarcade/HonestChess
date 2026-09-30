import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:honest_chess/a11y/announcer.dart';
import 'package:honest_chess/engine/engine.dart';
import 'package:honest_chess/feedback/clips.dart';
import 'package:honest_chess/feedback/game_feedback.dart';
import 'package:honest_chess/data/game_event.dart';
import 'package:honest_chess/feedback/music_controller.dart';
import 'package:honest_chess/ui/board/board_options.dart';
import 'package:honest_chess/ui/game/computer_turns.dart';
import 'package:honest_chess/ui/game/defaults.dart';
import 'package:honest_chess/ui/game/game_controller.dart';
import 'package:honest_chess/ui/navigation.dart';
import 'package:honest_chess/ui/screens/settings_screen.dart';

import '../support/app_harness.dart';
import '../ui/game/fake_computer.dart';

/// A controller, the hub over it and everything the hub reads.
class _Rig {
  _Rig({
    GameController? controller,
    BoardOptions options = const BoardOptions(),
  }) : controller = controller ?? GameController(),
       board = ValueNotifier(options) {
    feedback = GameFeedback(
      events: this.controller.events,
      refusals: this.controller.refusals,
      board: board,
      foreground: foreground,
      player: sound,
      haptics: haptics,
      announcer: announcer,
    );
  }

  final GameController controller;
  final ValueNotifier<BoardOptions> board;
  final foreground = ValueNotifier<bool>(true);
  final sound = FakeSoundPlayer();
  final haptics = FakeHaptics();
  final announcer = RecordingAnnouncer();
  late final GameFeedback feedback;

  void move(String uci) => expect(
    controller.move(
      Square.parse(uci.substring(0, 2)),
      Square.parse(uci.substring(2, 4)),
    ),
    isTrue,
    reason: 'test: $uci is playable',
  );

  void dispose() {
    feedback.dispose();
    controller.dispose();
    board.dispose();
    foreground.dispose();
  }
}

/// The music's gate over a two-player untimed game, with every condition
/// open except the setting, which the test turns on.
class _MusicRig {
  _MusicRig({bool music = true, bool idle = false})
    : controller = idle ? GameController.idle() : GameController(),
      board = ValueNotifier(BoardOptions(music: music)) {
    gate = MusicController(
      controller: controller,
      board: board,
      boardVisible: visible,
      foreground: foreground,
      player: sound,
    );
  }

  final GameController controller;
  final ValueNotifier<BoardOptions> board;
  final visible = ValueNotifier<bool>(true);
  final foreground = ValueNotifier<bool>(true);
  final sound = FakeSoundPlayer();
  late final MusicController gate;

  /// The music calls since the last look.
  Future<List<String>> calls() async {
    await gate.settle();
    final seen = [...sound.music];
    sound.music.clear();
    return seen;
  }

  void move(String uci) => expect(
    controller.move(
      Square.parse(uci.substring(0, 2)),
      Square.parse(uci.substring(2, 4)),
    ),
    isTrue,
  );

  void dispose() {
    gate.dispose();
    controller.dispose();
    board.dispose();
    visible.dispose();
    foreground.dispose();
  }
}

void main() {
  group('effects', () {
    test('each move plays its one clip; mate plays one end', () {
      final rig = _Rig();
      addTearDown(rig.dispose);
      rig.move('f2f3');
      rig.move('e7e5');
      rig.move('g2g4');
      rig.move('d8h4');
      expect(rig.sound.played, [
        Clip.move,
        Clip.move,
        Clip.move,
        Clip.end,
      ], reason: 'feedback: one clip per move, and the mate only its end');
    });

    test('resignation plays the end; takeback, pause and resume play '
        'nothing', () {
      final rig = _Rig();
      addTearDown(rig.dispose);
      rig.move('e2e4');
      rig.sound.played.clear();
      expect(rig.controller.takeBack(), isTrue);
      expect(rig.controller.pause(), isTrue);
      expect(rig.controller.resume(), isTrue);
      expect(
        rig.sound.played,
        isEmpty,
        reason: 'feedback: takeback, pause and resume are silent',
      );
      rig.move('e2e4');
      rig.sound.played.clear();
      expect(rig.controller.resign(), isTrue);
      expect(rig.sound.played, [Clip.end]);
    });

    test('restart and a new game play nothing', () async {
      final rig = _Rig();
      addTearDown(rig.dispose);
      rig.move('e2e4');
      rig.sound.played.clear();
      expect(await rig.controller.restart(), isTrue);
      expect(await rig.controller.newGame(twoPlayerDefault), isTrue);
      expect(
        rig.sound.played,
        isEmpty,
        reason: 'feedback: new games are silent',
      );
    });

    test('with Sound effects off nothing plays', () {
      final rig = _Rig(options: const BoardOptions(sfx: false));
      addTearDown(rig.dispose);
      rig.move('e2e4');
      rig.move('d7d5');
      rig.move('e4d5');
      rig.controller.resign();
      expect(
        rig.sound.played,
        isEmpty,
        reason: 'feedback: Sound effects off plays nothing',
      );
    });

    test('the switch applies at once, both ways', () {
      final rig = _Rig();
      addTearDown(rig.dispose);
      rig.move('e2e4');
      rig.board.value = const BoardOptions(sfx: false);
      rig.move('e7e5');
      rig.board.value = const BoardOptions();
      rig.move('g1f3');
      expect(rig.sound.played, [Clip.move, Clip.move]);
    });

    test('nothing plays while the app is not in the foreground', () {
      final rig = _Rig();
      addTearDown(rig.dispose);
      rig.foreground.value = false;
      rig.move('e2e4');
      expect(
        rig.sound.played,
        isEmpty,
        reason: 'feedback: no effect while the app is away',
      );
    });

    testWidgets("the computer's moves sound as yours do", (tester) async {
      final computers = FakeComputers();
      var ms = 0;
      Future<void> think() async {
        ms += minThinkTime.inMilliseconds;
        await tester.pump(minThinkTime);
      }

      final rig = _Rig(
        controller: GameController(
          mode: const VsComputer(
            playerColour: Colour.white,
            step: Strength.club,
            seed: 1,
          ),
          now: () => ms,
          computer: computers.call,
        ),
      );
      addTearDown(rig.dispose);
      rig.move('e2e4');
      await tester.pump();
      computers.current.last.move('d7d5');
      await think();
      rig.move('e4d5');
      await tester.pump();
      computers.current.last.move('d8d5');
      await think();
      expect(rig.sound.played, [
        Clip.move,
        Clip.move,
        Clip.capture,
        Clip.capture,
      ], reason: "feedback: the computer's move plays by the same rule");
    });
  });

  group('announcements', () {
    test('every change of game is spoken, in order', () async {
      final rig = _Rig();
      addTearDown(rig.dispose);
      rig.move('g1f3');
      rig.move('e7e5');
      expect(rig.controller.takeBack(), isTrue);
      expect(rig.controller.pause(), isTrue);
      expect(rig.controller.resume(), isTrue);
      expect(await rig.controller.restart(), isTrue);
      rig.move('e2e4');
      expect(
        await rig.controller.newGame((
          mode: GameKind.vsComputer,
          strength: Strength.club,
          colour: Colour.black,
          timeControl: const Untimed(),
        )),
        isTrue,
      );
      expect(rig.announcer.spoken, [
        'White knight to f3',
        'Black pawn to e5',
        'Took back Black pawn to e5',
        'Paused',
        'Resumed',
        'Game restarted, two players',
        'White pawn to e4',
        // The unfinished game it replaced is abandoned in silence.
        'New game, you play Black',
      ]);
    });

    test('a restored game says whose move it is', () {
      final rig = _Rig();
      addTearDown(rig.dispose);
      final game = Game.start(
        const TwoPlayer(),
        const Untimed(),
      ).play(Move.fromUci(Position.initial(), 'e2e4'));
      expect(rig.controller.restore(game), isTrue);
      expect(rig.announcer.spoken, ['Game restored, Black to move']);
    });

    test('an end with no move is spoken once, as the card words it', () {
      final rig = _Rig();
      addTearDown(rig.dispose);
      rig.move('e2e4');
      rig.announcer.spoken.clear();
      expect(rig.controller.resign(), isTrue);
      expect(rig.announcer.spoken, ['White wins. Black resigned.']);
    });

    test('a refusal is spoken with the piece that could not go', () {
      final rig = _Rig();
      addTearDown(rig.dispose);
      expect(rig.controller.tapSquare(Square.parse('b1')), isTrue);
      rig.controller.tapSquare(Square.parse('b4'));
      expect(rig.announcer.spoken, ["Knight can't move there, put down"]);
    });

    test('no setting and no lifecycle silences them', () {
      final rig = _Rig(options: const BoardOptions(sfx: false, haptics: false));
      addTearDown(rig.dispose);
      rig.foreground.value = false;
      rig.move('e2e4');
      rig.controller.tapSquare(Square.parse('b8'));
      rig.controller.tapSquare(Square.parse('b4'));
      expect(rig.sound.played, isEmpty);
      expect(rig.haptics.ticks, 0);
      expect(rig.announcer.spoken, [
        'White pawn to e4',
        "Knight can't move there, put down",
      ]);
    });

    test('a declined draw says who declined; it plays and ticks nothing', () {
      final vs = Game.start(
        const VsComputer(
          playerColour: Colour.white,
          step: Strength.club,
          seed: 1,
        ),
        const Untimed(),
      );
      final event = GameDrawDeclined(vs, const {});
      expect(announcementFor(event), 'Club declined the draw');
      expect(clipForEvent(event), isNull, reason: 'decline: played a clip');
      expect(ticksFor(event), isFalse, reason: 'decline: ticked');
    });

    test('an abandoned game has no words of its own', () {
      final game = Game.start(const TwoPlayer(), const Untimed());
      expect(announcementFor(GameAbandoned(game, const {})), isNull);
    });
  });

  group('music', () {
    test('never starts with Background music off', () async {
      final rig = _MusicRig(music: false);
      addTearDown(rig.dispose);
      rig.move('e2e4');
      rig.controller.pause();
      rig.controller.resume();
      rig.visible.value = false;
      rig.visible.value = true;
      expect(
        await rig.calls(),
        isEmpty,
        reason: 'music: off by default and never started while off',
      );
    });

    test('never starts with no game on the board', () async {
      final rig = _MusicRig(idle: true);
      addTearDown(rig.dispose);
      expect(await rig.calls(), isEmpty);
    });

    test('starts on a live game and pauses on each transition', () async {
      final rig = _MusicRig();
      addTearDown(rig.dispose);
      expect(await rig.calls(), ['start']);

      rig.controller.pause();
      expect(await rig.calls(), ['pause'], reason: 'music: the pause card');
      rig.controller.resume();
      expect(await rig.calls(), ['start']);

      rig.visible.value = false;
      expect(await rig.calls(), ['pause'], reason: 'music: another screen');
      rig.visible.value = true;
      expect(await rig.calls(), ['start']);

      rig.foreground.value = false;
      expect(await rig.calls(), ['pause'], reason: 'music: the app leaves');
      rig.foreground.value = true;
      expect(await rig.calls(), ['start']);

      rig.move('e2e4');
      expect(
        await rig.calls(),
        isEmpty,
        reason: 'music: a move changes nothing',
      );

      rig.controller.resign();
      expect(await rig.calls(), ['pause'], reason: 'music: the game ends');
      expect(await rig.controller.restart(), isTrue);
      expect(await rig.calls(), [
        'stop',
        'start',
      ], reason: 'music: a new game starts the loop from its beginning');
    });

    test('switching it off stops at once; on starts again', () async {
      final rig = _MusicRig();
      addTearDown(rig.dispose);
      expect(await rig.calls(), ['start']);
      rig.board.value = const BoardOptions();
      expect(await rig.calls(), ['stop'], reason: 'music: off stops the loop');
      rig.move('e2e4');
      expect(await rig.calls(), isEmpty);
      rig.board.value = const BoardOptions(music: true);
      expect(await rig.calls(), ['start']);
    });

    test('a refused start waits for the next change of the gate', () async {
      final rig = _MusicRig(music: false);
      addTearDown(rig.dispose);
      rig.sound.startAnswers = false;
      rig.board.value = const BoardOptions(music: true);
      expect(await rig.calls(), ['start']);
      rig.move('e2e4');
      rig.move('e7e5');
      expect(
        await rig.calls(),
        isEmpty,
        reason: 'music: a refused start is not retried on every move',
      );
      rig.controller.pause();
      expect(
        await rig.calls(),
        isEmpty,
        reason: 'music: nothing to pause after a refusal',
      );
      rig.sound.startAnswers = true;
      rig.controller.resume();
      expect(await rig.calls(), ['start']);
    });

    test('a start that lands after the gate closed is paused', () async {
      final rig = _MusicRig();
      addTearDown(rig.dispose);
      rig.controller.pause();
      expect(await rig.calls(), isEmpty);
      rig.controller.resume();
      rig.controller.pause();
      expect(
        await rig.calls(),
        isEmpty,
        reason: 'music: a stale start is dropped',
      );
    });
  });

  group('the board route', () {
    Future<AppHarness> board(WidgetTester tester) async {
      final harness = await pumpBoard(
        tester,
        setup: (
          mode: GameKind.twoPlayers,
          strength: null,
          colour: null,
          timeControl: const Untimed(),
        ),
        computerFactory: FakeComputers().call,
      );
      await tester.pumpAndSettle();
      return harness;
    }

    testWidgets('the loop plays on the board and pauses under another page', (
      tester,
    ) async {
      final harness = await board(tester);
      expect(harness.boardRoutes.visible.value, isTrue);
      expect(harness.sound.music, isEmpty, reason: 'music: off by default');
      harness.settings.updateBoard((o) => o.copyWith(music: true));
      await harness.music.settle();
      expect(harness.sound.music, ['start']);

      Navigator.of(tester.element(find.byKey(const Key('board'))))
          .push(settingsRoute());
      await tester.pumpAndSettle();
      await harness.music.settle();
      expect(harness.boardRoutes.visible.value, isFalse);
      expect(harness.sound.music, ['start', 'pause']);

      Navigator.of(tester.element(find.byType(SettingsScreen))).pop();
      await tester.pumpAndSettle();
      await harness.music.settle();
      expect(harness.sound.music, ['start', 'pause', 'start']);
    });

    testWidgets('a dialog over the board leaves it showing', (tester) async {
      final harness = await board(tester);
      showDialog<void>(
        context: tester.element(find.byKey(const Key('board'))),
        builder: (_) => const SizedBox(key: Key('a-dialog')),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('a-dialog')), findsOneWidget);
      expect(harness.boardRoutes.visible.value, isTrue);
      Navigator.of(tester.element(find.byKey(const Key('a-dialog')))).pop();
      await tester.pumpAndSettle();
    });
  });
}
