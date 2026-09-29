// The vs-computer setup screen (#85): every choice reaches the started
// game, the steppers stop at their ends, Random resolves once per game, and
// Start game abandons only the computer game it replaces. The complements
// are checked beside each: the two-player document is never touched, and
// with no unfinished computer game neither the warning nor Keep playing
// shows.
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:honest_chess/data/app_store.dart';
import 'package:honest_chess/data/game_saves.dart';
import 'package:honest_chess/data/play_mode.dart';
import 'package:honest_chess/data/settings_store.dart';
import 'package:honest_chess/data/stats.dart';
import 'package:honest_chess/data/stats_listener.dart';
import 'package:honest_chess/engine/engine.dart';
import 'package:honest_chess/ui/game/computer_turns.dart';
import 'package:honest_chess/ui/game/defaults.dart';
import 'package:honest_chess/ui/game/game_controller.dart';
import 'package:honest_chess/ui/game/game_screen.dart';
import 'package:honest_chess/ui/navigation.dart';
import 'package:honest_chess/ui/screens/computer_setup_screen.dart';
import 'package:honest_chess/ui/theme/palette.dart';
import 'package:honest_chess/ui/widgets/time_control_picker.dart';

import '../support/app_harness.dart';
import '../support/scripted_random.dart';
import 'game/fake_computer.dart';
import 'piece_font_test.dart' show cmapCodePoints;

/// Everything the app root wires, over one memory store: the controller,
/// the saved games, the statistics with their listener, and the settings
/// loaded from the store.
class _Rig {
  _Rig(this.store) {
    var ids = 0;
    controller = GameController.idle(
      computerFactory: computers.call,
      newGameId: () => (++ids).toRadixString(16).padLeft(16, '0'),
    );
    saves = GameSaves(store)..attach(controller.events);
    recorder = StatsRecorder(store: store, nowMillis: () => 1759104000000);
    listener = StatsListener(
      controller: controller,
      recorder: recorder,
      saves: saves,
    );
  }

  final AppStore store;
  final computers = FakeComputers();
  final settings = SettingsStore();
  late final GameController controller;
  late final GameSaves saves;
  late final StatsRecorder recorder;
  late final StatsListener listener;

  StepStats step(Strength s) => recorder.document.computer.steps[s]!;

  int get computerPlayed =>
      [for (final s in Strength.values) step(s).played]
          .fold(0, (a, b) => a + b);

  void dispose() {
    listener.dispose();
    recorder.dispose();
    saves.dispose();
    settings.dispose();
    controller.dispose();
  }
}

/// Runs [work] in the test's own fake-async zone: the memory store and the
/// data objects were made there, so their futures complete as microtasks
/// flush, which `runAsync`'s real zone would wait on for ever.
Future<T> _inTest<T>(Future<T> Function() work) => work();

/// A stand-in for the menu: the first route, under the setup screen.
class _FirstRoute extends StatelessWidget {
  const _FirstRoute();

  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Text('first', key: Key('first-route')));
}

/// Launches the rig over [store] and pushes the setup screen over a
/// stand-in first route — or, with [overBoard], over the first route and a
/// board, as the board's New opens it.
Future<_Rig> _pumpSetup(
  WidgetTester tester, {
  AppStore? store,
  Random? random,
  bool overBoard = false,
  Size size = const Size(390, 1400),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final rig = _Rig(store ?? AppStore.memory());
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox());
    rig.dispose();
  });
  await _inTest(() async {
    await rig.recorder.load();
    await rig.saves.loadAll();
    await rig.settings.load(rig.store);
  });
  await pumpUnderScope(
    tester,
    const _FirstRoute(),
    store: rig.store,
    controller: rig.controller,
    saves: rig.saves,
    stats: rig.recorder,
    settings: rig.settings,
    random: random,
  );
  final navigator = tester.state<NavigatorState>(find.byType(Navigator));
  if (overBoard) {
    navigator.push(boardRoute());
    await _settleRoute(tester);
  }
  navigator.push(
    MaterialPageRoute<void>(
      builder: (_) => ComputerSetupScreen(fromBoard: overBoard),
    ),
  );
  await _settleRoute(tester);
  return rig;
}

/// Lets a route transition finish without pumpAndSettle, which a running
/// clock's ticker would never let settle.
Future<void> _settleRoute(WidgetTester tester) async {
  await tester.pump();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));
  await tester.pump();
}

Future<void> _tap(WidgetTester tester, String key) async {
  final finder = find.byKey(Key(key));
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder);
  await tester.pump();
}

/// Start game, then the replace stages' writes and the board's push.
Future<void> _startGame(WidgetTester tester, _Rig rig) async {
  await _tap(tester, 'csetup-start');
  await _drain(tester, rig);
  await _settleRoute(tester);
}

/// Every queued save, record and write, in real async.
Future<void> _drain(WidgetTester tester, _Rig rig) async {
  for (var i = 0; i < 3; i++) {
    await _inTest(() async {
      await rig.saves.flush();
      await rig.recorder.idle;
      await rig.store.flush();
    });
    await tester.pump();
  }
}

VsComputer _computerMode(_Rig rig) {
  final mode = rig.controller.game.mode;
  expect(mode, isA<VsComputer>(), reason: 'test: a game against the computer');
  return mode as VsComputer;
}

/// A computer game at Club, you White, after your e2e4 (started).
Game _startedComputerGame() {
  final game = Game.start(
    const VsComputer(
      playerColour: Colour.white,
      step: Strength.club,
      seed: 0x85,
    ),
    Timed.rapid,
  );
  return game.play(Move.fromUci(game.position, 'e2e4'));
}

Game _twoPlayerGame() {
  final game = Game.start(const TwoPlayer(), Timed.blitz);
  final e4 = game.play(Move.fromUci(game.position, 'd2d4'));
  return e4.play(Move.fromUci(e4.position, 'd7d5'));
}

Map<String, Object?> _doc(Game game, String id, {bool started = true}) => {
  'game': game.toJson(),
  'recorded': {'id': id, 'started': started, 'outcome': false},
};

/// A store holding a started computer game and a two-player game.
AppStore _storeWithBoth() => AppStore.memory(
  documents: {
    StoreDoc.gameComputer: _doc(_startedComputerGame(), '00000000000000c0'),
    StoreDoc.gameTwo: _doc(_twoPlayerGame(), '00000000000000d0'),
  },
);

/// The moves of the two-player game as the store's own text holds them.
List<String> _storedTwoPlayerMoves(AppStore store) {
  final text = store.rawText(StoreDoc.gameTwo);
  expect(text, isNotNull, reason: 'test: a two-player document is stored');
  final envelope = jsonDecode(text!) as Map<String, Object?>;
  final doc = envelope['data']! as Map<String, Object?>;
  final game = Game.fromJson(doc['game']! as Map<String, Object?>);
  return [
    for (final snapshot in game.history)
      if (snapshot.move case final move?) move.toUci(),
  ];
}

bool _visible(String key) => find.byKey(Key(key)).evaluate().isNotEmpty;

String _stepperValue(WidgetTester tester, String name) =>
    tester.widget<Text>(find.byKey(Key('csetup-$name-value'))).data!;

double _stepperOpacity(WidgetTester tester, String key) => tester
    .widget<Opacity>(
      find.descendant(of: find.byKey(Key(key)), matching: find.byType(Opacity)),
    )
    .opacity;

void main() {
  group('the screen', () {
    testWidgets('opens on the design text and first-time choices', (
      tester,
    ) async {
      final rig = await _pumpSetup(tester);
      expect(find.text('New game vs computer'), findsOneWidget);
      expect(find.text('RUNS ON DEVICE · NO NETWORK'), findsOneWidget);
      expect(find.text(strengthIntro), findsOneWidget);
      for (final step in Strength.values) {
        expect(
          tester
              .widget<Text>(
                find.byKey(Key('csetup-strength-${step.name}-description')),
              )
              .data,
          step.description,
          reason: "csetup: each step shows #67's owner-approved description",
        );
      }
      expect(rig.settings.setup.value, SetupChoices.initial);
      // Club (step 3) is chosen: three teal pips; Strong's four lit pips
      // are #7FA6D8 and its fifth is unlit.
      Color pip(String step, int n) =>
          (tester
                      .widget<Container>(find.byKey(Key('csetup-pip-$step-$n')))
                      .decoration!
                  as BoxDecoration)
              .color!;
      expect(
        [for (var n = 0; n < 5; n++) pip('club', n)],
        [
          Palette.teal,
          Palette.teal,
          Palette.teal,
          Palette.borderSoft,
          Palette.borderSoft,
        ],
      );
      expect(
        [for (var n = 0; n < 5; n++) pip('strong', n)],
        [
          Palette.textDim,
          Palette.textDim,
          Palette.textDim,
          Palette.textDim,
          Palette.borderSoft,
        ],
      );
      expect(
        tester.getSemantics(find.byKey(const Key('csetup-strength-club'))),
        isSemantics(
          label: 'Club, step 3 of 5, ${Strength.club.description}',
          isButton: true,
          isSelected: true,
          isInMutuallyExclusiveGroup: true,
        ),
      );
      expect(
        tester.getSemantics(find.byKey(const Key('csetup-colour-white'))),
        isSemantics(label: 'White', isButton: true, isSelected: true),
      );
      // Rapid is chosen, so the steppers are not there.
      expect(_visible('csetup-minutes-dec'), isFalse);
      // The complement: with no unfinished computer game, neither the
      // warning nor Keep playing shows.
      expect(_visible('csetup-loss-warning'), isFalse);
      expect(_visible('csetup-keep-playing'), isFalse);
    });

    testWidgets('the Play as symbols: the piece font\'s kings, and ⁇', (
      tester,
    ) async {
      await _pumpSetup(tester);
      for (final choice in ColourChoice.values) {
        final glyph = tester.widget<Text>(
          find.byKey(Key('csetup-colour-glyph-${choice.name}')),
        );
        expect(glyph.data, colourGlyph(choice));
      }
      expect(
        tester
            .widget<Text>(find.byKey(const Key('csetup-colour-glyph-white')))
            .style!
            .fontFamily,
        Fonts.pieces,
      );
      // ⁇ takes the fallback because Outfit has no U+2047.
      for (final file in Directory('assets/fonts/outfit').listSync()) {
        if (!file.path.endsWith('.ttf')) continue;
        expect(
          cmapCodePoints(File(file.path).readAsBytesSync()),
          allOf(isNot(contains(0x2047)), contains(0x2212)),
          reason: 'test: ${file.path} lacks ⁇ and has −',
        );
      }
    });
  });

  group('choices reach the started game', () {
    for (final step in Strength.values) {
      testWidgets('strength ${step.name}', (tester) async {
        final rig = await _pumpSetup(tester);
        await _tap(tester, 'csetup-strength-${step.name}');
        await _startGame(tester, rig);
        final mode = _computerMode(rig);
        expect(mode.step, step);
        expect(mode.playerColour, Colour.white);
        expect(rig.controller.game.clock.control, Timed.rapid);
        expect(rig.computers.current.strength, step);
        expect(find.byType(GameScreen), findsOneWidget);
        expect(find.byType(ComputerSetupScreen), findsNothing);
      });
    }

    for (final (choice, colour) in [
      (ColourChoice.white, Colour.white),
      (ColourChoice.black, Colour.black),
    ]) {
      testWidgets('play as ${choice.name}', (tester) async {
        final random = ScriptedRandom();
        final rig = await _pumpSetup(tester, random: random);
        await _tap(tester, 'csetup-colour-${choice.name}');
        await _startGame(tester, rig);
        expect(_computerMode(rig).playerColour, colour);
        expect(random.taken, 0, reason: 'test: a set colour draws nothing');
        await tester.pump(minThinkTime);
      });
    }

    for (final time in TimeChoice.values) {
      testWidgets('time ${time.name}', (tester) async {
        final rig = await _pumpSetup(tester);
        await _tap(tester, 'csetup-time-${time.name}');
        expect(
          _visible('csetup-minutes-dec'),
          time == TimeChoice.custom,
          reason: 'csetup: the steppers show only for Custom',
        );
        await _startGame(tester, rig);
        expect(rig.controller.game.clock.control, time.toTimeControl(10, 5));
      });
    }

    testWidgets('Random draws White, then Black, and a rematch keeps it', (
      tester,
    ) async {
      final random = ScriptedRandom([true, false]);
      final rig = await _pumpSetup(tester, random: random);
      await _tap(tester, 'csetup-colour-random');
      await _startGame(tester, rig);
      expect(_computerMode(rig).playerColour, Colour.white);
      expect(random.taken, 1);
      await rig.controller.restart();
      await tester.pump();
      expect(
        _computerMode(rig).playerColour,
        Colour.white,
        reason: 'csetup: a rematch keeps the resolved colour',
      );
      expect(random.taken, 1, reason: 'csetup: a rematch draws nothing');

      tester
          .state<NavigatorState>(find.byType(Navigator))
          .push(
            MaterialPageRoute<void>(
              builder: (_) => const ComputerSetupScreen(),
            ),
          );
      await _settleRoute(tester);
      await _startGame(tester, rig);
      expect(_computerMode(rig).playerColour, Colour.black);
      expect(random.taken, 2);
      await tester.pump(minThinkTime);
    });
  });

  group('custom time', () {
    Future<_Rig> pumpCustom(WidgetTester tester, int minutes, int inc) =>
        _pumpSetup(
          tester,
          store: AppStore.memory(
            documents: {
              StoreDoc.settings: {
                'setup': encodeSetup(
                  SetupChoices.initial.copyWith(
                    computer: SetupChoices.initial.computer.copyWith(
                      time: TimeChoice.custom,
                    ),
                    custom: CustomTime(minutes: minutes, increment: inc),
                  ),
                ),
              },
            },
          ),
        );

    testWidgets('the steppers stop at 1 min and 0 sec', (tester) async {
      final rig = await pumpCustom(tester, 2, 1);
      expect(_stepperValue(tester, 'minutes'), '2 min');
      expect(
        tester.getSize(find.byKey(const Key('csetup-minutes-dec'))),
        const Size.square(48),
        reason: 'csetup: a stepper button is 48 dp to touch',
      );
      expect(
        tester.getSize(
          find.descendant(
            of: find.byKey(const Key('csetup-minutes-dec')),
            matching: find.byType(Container),
          ),
        ),
        const Size.square(28),
        reason: 'csetup: and 28 dp drawn, as the design',
      );
      expect(_stepperValue(tester, 'increment'), '1 sec');
      for (final name in ['minutes', 'increment']) {
        await _tap(tester, 'csetup-$name-dec');
        expect(_stepperOpacity(tester, 'csetup-$name-dec'), .4);
        await _tap(tester, 'csetup-$name-dec');
      }
      expect(_stepperValue(tester, 'minutes'), '1 min');
      expect(_stepperValue(tester, 'increment'), '0 sec');
      expect(
        rig.settings.setup.value.custom,
        const CustomTime(minutes: 1, increment: 0),
      );
      await _startGame(tester, rig);
      expect(rig.controller.game.clock.control, Timed(1, 0));
    });

    testWidgets('the steppers stop at 90 min and 60 sec', (tester) async {
      final rig = await pumpCustom(tester, 89, 59);
      for (final name in ['minutes', 'increment']) {
        await _tap(tester, 'csetup-$name-inc');
        expect(_stepperOpacity(tester, 'csetup-$name-inc'), .4);
        expect(_stepperOpacity(tester, 'csetup-$name-dec'), 1);
        await _tap(tester, 'csetup-$name-inc');
      }
      expect(_stepperValue(tester, 'minutes'), '90 min');
      expect(_stepperValue(tester, 'increment'), '60 sec');
      expect(
        rig.settings.setup.value.custom,
        const CustomTime(minutes: 90, increment: 60),
      );
    });

    testWidgets('choosing Custom scrolls its steppers into view', (
      tester,
    ) async {
      await _pumpSetup(tester, size: const Size(390, 844));
      final custom = find.byKey(const Key('csetup-time-custom'));
      await tester.ensureVisible(custom);
      await tester.pump();
      await tester.tap(custom);
      await tester.pump();
      await tester.pump(stepperRevealDuration);
      await tester.pump(stepperRevealDuration);
      await tester.pump();
      final bottom = tester
          .getBottomLeft(find.byKey(const Key('csetup-increment-dec')))
          .dy;
      expect(
        bottom,
        lessThanOrEqualTo(844),
        reason: 'csetup: the steppers are brought on screen',
      );
    });

    testWidgets('a held + repeats after 400 ms, every 80 ms, to the end', (
      tester,
    ) async {
      final rig = await pumpCustom(tester, 85, 5);
      final button = find.byKey(const Key('csetup-minutes-inc'));
      await tester.ensureVisible(button);
      await tester.pump();
      final gesture = await tester.startGesture(tester.getCenter(button));
      await tester.pump(const Duration(milliseconds: 399));
      expect(rig.settings.setup.value.custom.minutes, 85);
      await tester.pump(const Duration(milliseconds: 1));
      expect(rig.settings.setup.value.custom.minutes, 86);
      for (final expected in [87, 88, 89, 90]) {
        await tester.pump(stepperRepeat);
        expect(rig.settings.setup.value.custom.minutes, expected);
      }
      // At the end it stops, and the release adds nothing.
      await tester.pump(stepperRepeat * 3);
      await gesture.up();
      await tester.pump();
      expect(rig.settings.setup.value.custom.minutes, 90);
      expect(_stepperValue(tester, 'minutes'), '90 min');
    });

    testWidgets('a held − released early stops, and adds nothing on release', (
      tester,
    ) async {
      final rig = await pumpCustom(tester, 30, 5);
      final button = find.byKey(const Key('csetup-increment-dec'));
      await tester.ensureVisible(button);
      await tester.pump();
      final gesture = await tester.startGesture(tester.getCenter(button));
      await tester.pump(stepperHoldDelay);
      await tester.pump(stepperRepeat);
      expect(rig.settings.setup.value.custom.increment, 3);
      await gesture.up();
      await tester.pump(stepperRepeat * 3);
      expect(rig.settings.setup.value.custom.increment, 3);
    });
  });

  group('the game it replaces', () {
    testWidgets('Start game over a started computer game records one loss and '
        'leaves the two-player document byte-identical', (tester) async {
      final store = _storeWithBoth();
      final twoBefore = store.rawText(StoreDoc.gameTwo);
      final rig = await _pumpSetup(tester, store: store);
      await _inTest(
        () async => rig.controller.restore(
          rig.saves.load(PlayMode.computer)!,
          recorded: rig.saves.recorded(PlayMode.computer),
        ),
      );
      await tester.pump();
      expect(_visible('csetup-loss-warning'), isTrue);
      expect(find.text(lossWarningText), findsOneWidget);
      expect(_visible('csetup-keep-playing'), isTrue);
      expect(rig.computerPlayed, 0);

      await _startGame(tester, rig);
      expect(rig.step(Strength.club).played, 1);
      expect(rig.step(Strength.club).won, 0);
      expect(rig.computerPlayed, 1, reason: 'csetup: exactly one loss');
      expect(store.rawText(StoreDoc.gameTwo), twoBefore);
    });

    testWidgets(
      'Start game while the board holds a two-player game abandons the '
      'saved computer game and leaves the two-player document alone',
      (tester) async {
        final store = _storeWithBoth();
        final twoBefore = store.rawText(StoreDoc.gameTwo);
        final rig = await _pumpSetup(tester, store: store);
        await _inTest(
          () async => rig.controller.restore(
            rig.saves.load(PlayMode.two)!,
            recorded: rig.saves.recorded(PlayMode.two),
          ),
        );
        await tester.pump();
        expect(_visible('csetup-loss-warning'), isTrue);

        await _startGame(tester, rig);
        expect(rig.step(Strength.club).played, 1);
        expect(rig.computerPlayed, 1);
        expect(
          rig.recorder.document.two.clocks.values.fold(0, (a, b) => a + b),
          0,
          reason: 'csetup: the two-player game is not counted',
        );
        expect(store.rawText(StoreDoc.gameTwo), twoBefore);
        expect(_computerMode(rig).step, Strength.club);
      },
    );

    testWidgets('an unstarted computer game offers Keep playing, no warning', (
      tester,
    ) async {
      final store = AppStore.memory(
        documents: {
          StoreDoc.gameComputer: _doc(
            Game.start(
              const VsComputer(
                playerColour: Colour.white,
                step: Strength.casual,
                seed: 7,
              ),
              Timed.rapid,
            ),
            '00000000000000c1',
            started: false,
          ),
        },
      );
      final rig = await _pumpSetup(tester, store: store);
      expect(_visible('csetup-keep-playing'), isTrue);
      expect(_visible('csetup-loss-warning'), isFalse);
      await _startGame(tester, rig);
      expect(rig.computerPlayed, 0, reason: 'csetup: nothing to abandon');
    });

    testWidgets(
      'Keep playing with a two-player game on the board saves it, then '
      'loads the computer game, unpaused',
      (tester) async {
        final store = _storeWithBoth();
        final rig = await _pumpSetup(tester, store: store);
        // One move more than the slot holds, so the store can only gain it
        // from Keep playing's own save.
        final saved = rig.saves.load(PlayMode.two)!;
        final unsaved = saved.play(Move.fromUci(saved.position, 'c2c4'));
        await _inTest(
          () async => rig.controller.restore(
            unsaved,
            recorded: rig.saves.recorded(PlayMode.two),
          ),
        );
        await tester.pump();
        final two = rig.controller.game;
        expect(
          _storedTwoPlayerMoves(store),
          ['d2d4', 'd7d5'],
          reason: 'csetup: a restore saves nothing, so c2c4 is not stored yet',
        );

        await _tap(tester, 'csetup-keep-playing');
        await _drain(tester, rig);
        await _settleRoute(tester);

        final mode = _computerMode(rig);
        expect(mode.step, Strength.club);
        expect(rig.controller.game.history.length, 2);
        expect(rig.controller.state.paused, isFalse);
        expect(rig.computerPlayed, 0, reason: 'csetup: nothing abandoned');
        expect(_storedTwoPlayerMoves(store), [
          'd2d4',
          'd7d5',
          'c2c4',
        ], reason: 'csetup: the two-player game was saved first');
        expect(
          rig.saves.load(PlayMode.two)?.toJson(),
          two.toJson(),
          reason: 'csetup: the two-player slot holds the game from the board',
        );
        expect(find.byType(GameScreen), findsOneWidget);
        expect(find.byType(ComputerSetupScreen), findsNothing);
        await tester.pump(minThinkTime);
      },
    );

    testWidgets('Keep playing from the board resumes and pops back to it', (
      tester,
    ) async {
      final store = AppStore.memory(
        documents: {
          StoreDoc.gameComputer: _doc(
            _startedComputerGame(),
            '00000000000000c0',
          ),
        },
      );
      final rig = await _pumpSetup(tester, store: store);
      // The board over the computer game, paused, with the screen on top.
      await _inTest(
        () async => rig.controller.restore(
          rig.saves.load(PlayMode.computer)!,
          recorded: rig.saves.recorded(PlayMode.computer),
        ),
      );
      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      navigator.pushAndRemoveUntil(boardRoute(), (r) => r.isFirst);
      await _settleRoute(tester);
      navigator.push(
        MaterialPageRoute<void>(
          builder: (_) => const ComputerSetupScreen(fromBoard: true),
        ),
      );
      await _settleRoute(tester);
      expect(rig.controller.state.paused, isTrue);

      await _tap(tester, 'csetup-keep-playing');
      expect(
        rig.controller.state.paused,
        isFalse,
        reason: 'csetup: resumed at the tap, before the pop',
      );
      await _settleRoute(tester);
      expect(find.byType(ComputerSetupScreen), findsNothing);
      expect(find.byType(GameScreen), findsOneWidget);
      expect(rig.computers.built, hasLength(1));
      await tester.pump(minThinkTime);
    });

    testWidgets('back from the board returns to it still paused', (
      tester,
    ) async {
      final rig = await _pumpSetup(
        tester,
        store: AppStore.memory(
          documents: {
            StoreDoc.gameComputer: _doc(
              _startedComputerGame(),
              '00000000000000c0',
            ),
          },
        ),
      );
      await _inTest(
        () async => rig.controller.restore(
          rig.saves.load(PlayMode.computer)!,
          recorded: rig.saves.recorded(PlayMode.computer),
        ),
      );
      await tester.pump();
      await _tap(tester, 'csetup-back');
      await _settleRoute(tester);
      expect(find.byType(ComputerSetupScreen), findsNothing);
      expect(rig.controller.state.paused, isTrue);
      expect(rig.computerPlayed, 0);
    });
  });

  group('navigation', () {
    testWidgets('a second Start game tap during the first is ignored', (
      tester,
    ) async {
      final rig = await _pumpSetup(tester);
      final start = find.byKey(const Key('csetup-start'));
      await tester.ensureVisible(start);
      await tester.pump();
      await tester.tap(start);
      await tester.tap(start, warnIfMissed: false);
      await _drain(tester, rig);
      await _settleRoute(tester);
      expect(rig.computers.built, hasLength(1));
      expect(find.byType(GameScreen), findsOneWidget);
    });

    testWidgets('a new game over a board leaves exactly one board', (
      tester,
    ) async {
      final rig = await _pumpSetup(tester, overBoard: true);
      await _startGame(tester, rig);
      expect(find.byType(GameScreen, skipOffstage: false), findsOneWidget);
      expect(
        find.byKey(const Key('first-route'), skipOffstage: false),
        findsOneWidget,
      );
    });
  });

  testWidgets('the last choices survive a relaunch', (tester) async {
    final store = AppStore.memory();
    final rig = await _pumpSetup(tester, store: store);
    await _tap(tester, 'csetup-strength-strong');
    await _tap(tester, 'csetup-colour-black');
    await _tap(tester, 'csetup-time-custom');
    for (var i = 0; i < 5; i++) {
      await _tap(tester, 'csetup-minutes-inc');
    }
    for (var i = 0; i < 5; i++) {
      await _tap(tester, 'csetup-increment-inc');
    }
    await _inTest(store.flush);

    final relaunched = SettingsStore();
    addTearDown(relaunched.dispose);
    await _inTest(() => relaunched.load(store));
    expect(
      relaunched.setup.value,
      SetupChoices.initial.copyWith(
        computer: const ComputerChoices(
          step: Strength.strong,
          colour: ColourChoice.black,
          time: TimeChoice.custom,
        ),
        custom: const CustomTime(minutes: 15, increment: 10),
      ),
    );
    expect(rig.settings.setup.value, relaunched.setup.value);
  });
}
