// The two-player setup screen (#86): each time choice reaches the started
// game, the rotate switch is Settings' own, the house rules follow
// Takeback allowed, and Start game replaces an unfinished two-player game
// without recording it. The complements are checked beside each: nothing
// is counted, and the saved game against the computer stays byte-identical.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:honest_chess/data/app_store.dart';
import 'package:honest_chess/data/game_saves.dart';
import 'package:honest_chess/data/play_mode.dart';
import 'package:honest_chess/data/settings_store.dart';
import 'package:honest_chess/data/stats.dart';
import 'package:honest_chess/data/stats_listener.dart';
import 'package:honest_chess/engine/engine.dart';
import 'package:honest_chess/ui/game/defaults.dart';
import 'package:honest_chess/ui/game/game_controller.dart';
import 'package:honest_chess/ui/game/game_screen.dart';
import 'package:honest_chess/ui/navigation.dart';
import 'package:honest_chess/ui/screens/settings_screen.dart';
import 'package:honest_chess/ui/screens/two_player_setup_screen.dart';
import 'package:honest_chess/ui/theme/palette.dart';
import 'package:honest_chess/ui/widgets/option_button.dart';
import 'package:honest_chess/ui/widgets/setting_row.dart';
import 'package:honest_chess/ui/widgets/time_control_picker.dart';
import 'package:honest_chess/ui/widgets/toggle_switch.dart';

import '../support/app_harness.dart';
import 'game/fake_computer.dart';

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

  int get twoPlayed =>
      recorder.document.two.clocks.values.fold(0, (a, b) => a + b);

  int get computerLost => [
    for (final s in recorder.document.computer.steps.values) s.played - s.won,
  ].fold(0, (a, b) => a + b);

  void dispose() {
    listener.dispose();
    recorder.dispose();
    saves.dispose();
    settings.dispose();
    controller.dispose();
  }
}

/// A stand-in for the menu: the first route, under the setup screen.
class _FirstRoute extends StatelessWidget {
  const _FirstRoute();

  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Text('first', key: Key('first-route')));
}

/// Launches the rig over [store], lets [before] act on it, and pushes the
/// setup screen over a stand-in first route — or, with [overBoard], over
/// the first route and a board, as the board's New opens it.
Future<_Rig> _pumpSetup(
  WidgetTester tester, {
  AppStore? store,
  bool overBoard = false,
  Future<void> Function(_Rig rig)? before,
}) async {
  tester.view.physicalSize = const Size(390, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final rig = _Rig(store ?? AppStore.memory());
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox());
    rig.dispose();
  });
  await rig.recorder.load();
  await rig.saves.loadAll();
  await rig.settings.load(rig.store);
  if (before != null) await before(rig);
  await pumpUnderScope(
    tester,
    const _FirstRoute(),
    store: rig.store,
    controller: rig.controller,
    saves: rig.saves,
    stats: rig.recorder,
    settings: rig.settings,
  );
  final navigator = tester.state<NavigatorState>(find.byType(Navigator));
  if (overBoard) {
    navigator.push(boardRoute());
    await _settleRoute(tester);
  }
  navigator.push(
    MaterialPageRoute<void>(builder: (_) => const TwoPlayerSetupScreen()),
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

/// Every queued save, record and write.
Future<void> _drain(WidgetTester tester, _Rig rig) async {
  for (var i = 0; i < 3; i++) {
    await rig.saves.flush();
    await rig.recorder.idle;
    await rig.store.flush();
    await tester.pump();
  }
}

Future<void> _startGame(WidgetTester tester, _Rig rig) async {
  await _tap(tester, 'psetup-start');
  await _drain(tester, rig);
  await _settleRoute(tester);
}

void _move(GameController c, String uci) => expect(
  c.move(Square.parse(uci.substring(0, 2)), Square.parse(uci.substring(2))),
  isTrue,
  reason: 'test: $uci is playable',
);

bool _selected(WidgetTester tester, TimeChoice time) => tester
    .widget<OptionButton>(find.byKey(Key('psetup-time-${time.name}')))
    .selected;

bool _rotateRow(WidgetTester tester, String key) =>
    tester.widget<SettingRow>(find.byKey(Key(key))).value;

String _houseRules(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(const Key('psetup-house-rules'))).data!;

/// The border colour of the box drawn inside [key] while a finger is down
/// on it.
Future<Color> _pressedBorder(
  WidgetTester tester,
  String key,
  Finder box,
) async {
  final finder = find.byKey(Key(key));
  await tester.ensureVisible(finder);
  await tester.pump();
  final gesture = await tester.startGesture(tester.getCenter(finder));
  await tester.pump(const Duration(milliseconds: 150));
  final decoration = tester.widget<Container>(box).decoration! as BoxDecoration;
  // Away from the button, so the release is no tap.
  await gesture.moveBy(const Offset(0, 400));
  await gesture.up();
  await tester.pump();
  return (decoration.border! as Border).top.color;
}

/// The saved two-player game in [store], decoded.
Future<Game> _savedTwo(AppStore store) async {
  final read = await store.read(StoreDoc.gameTwo);
  expect(read, isA<Loaded>(), reason: 'psetup: game-two is saved');
  return Game.fromJson((read as Loaded).data['game']! as Map<String, Object?>);
}

Game _computerGame() {
  final game = Game.start(
    const VsComputer(playerColour: Colour.white, step: Strength.club, seed: 9),
    Timed.rapid,
  );
  return game.play(Move.fromUci(game.position, 'e2e4'));
}

void main() {
  group('the screen', () {
    testWidgets('opens on the design text and Rapid 10+5', (tester) async {
      final rig = await _pumpSetup(tester);
      expect(find.text('Two players'), findsOneWidget);
      final kicker = tester.widget<Text>(
        find.byKey(const Key('psetup-kicker')),
      );
      expect(kicker.data, 'ONE PHONE · PASS AND PLAY');
      expect(kicker.style!.color, Palette.kickerViolet);
      expect(find.text('Time control'), findsOneWidget);
      expect(find.text(twoPlayerTimeNote), findsOneWidget);
      expect(find.text('HOUSE RULES'), findsOneWidget);
      for (final time in TimeChoice.values) {
        expect(
          _selected(tester, time),
          time == TimeChoice.rapid,
          reason: 'psetup: the first-time choice is Rapid 10+5 alone',
        );
        expect(
          tester
              .widget<OptionButton>(find.byKey(Key('psetup-time-${time.name}')))
              .accent,
          Accent.violet,
          reason: 'psetup: the time choices are violet',
        );
      }
      expect(rig.settings.setup.value, SetupChoices.initial);
      final row = tester.widget<SettingRow>(
        find.byKey(const Key('psetup-rotate')),
      );
      expect(
        (row.label, row.description, row.value, row.accent),
        (rotateLabel, rotateDescription, false, Accent.violet),
      );
      expect(
        (row.padding, row.radius),
        (const EdgeInsets.symmetric(vertical: 13, horizontal: 15), 14.0),
        reason: "psetup: the rotate row takes the design's 13/15 and 14",
      );
      expect(
        tester
            .widget<ToggleSwitch>(
              find.descendant(
                of: find.byKey(const Key('psetup-rotate')),
                matching: find.byType(ToggleSwitch),
              ),
            )
            .accent,
        Accent.violet,
      );
      // Custom is not chosen, so the steppers are not there.
      expect(find.byKey(const Key('psetup-minutes-dec')), findsNothing);
      expect(
        (tester
                    .widget<Container>(
                      find.byKey(const Key('psetup-start-fill')),
                    )
                    .decoration!
                as BoxDecoration)
            .color,
        Palette.violet,
      );
    });

    testWidgets('outlined elements and Start game press violet', (
      tester,
    ) async {
      await _pumpSetup(
        tester,
        store: AppStore.memory(
          documents: {
            StoreDoc.settings: {
              'setup': encodeSetup(
                SetupChoices.initial.copyWith(
                  two: const TwoPlayerChoices(time: TimeChoice.custom),
                ),
              ),
            },
          },
        ),
      );
      expect(
        await _pressedBorder(
          tester,
          'psetup-back',
          find.byKey(const Key('psetup-back-box')),
        ),
        Palette.violet,
        reason: 'psetup: ‹ presses violet',
      );
      Finder drawn(String key) => find.descendant(
        of: find.byKey(Key(key)),
        matching: find.byType(Container),
      );
      for (final key in ['psetup-minutes-dec', 'psetup-increment-inc']) {
        expect(
          await _pressedBorder(tester, key, drawn(key)),
          Palette.violet,
          reason: 'psetup: $key presses violet',
        );
      }
      final blitz = find.byKey(const Key('psetup-time-blitz'));
      final gesture = await tester.startGesture(tester.getCenter(blitz));
      await tester.pump(const Duration(milliseconds: 150));
      final box = tester.widget<DecoratedBox>(
        find.descendant(of: blitz, matching: find.byType(DecoratedBox)).first,
      );
      expect(
        ((box.decoration as BoxDecoration).border! as Border).top.color,
        Palette.violet,
        reason: 'psetup: an unselected time choice presses violet',
      );
      await gesture.moveBy(const Offset(0, 400));
      await gesture.up();
      await tester.pump();

      final start = find.byKey(const Key('psetup-start'));
      await tester.ensureVisible(start);
      await tester.pump();
      final press = await tester.startGesture(tester.getCenter(start));
      await tester.pump(const Duration(milliseconds: 150));
      expect(
        (tester
                    .widget<Container>(
                      find.byKey(const Key('psetup-start-fill')),
                    )
                    .decoration!
                as BoxDecoration)
            .color,
        Palette.violetPressed,
      );
      await press.moveBy(const Offset(0, -600));
      await press.up();
      await tester.pump();
    });

    testWidgets('the house rules follow Takeback allowed, word for word', (
      tester,
    ) async {
      final rig = await _pumpSetup(tester);
      expect(
        _houseRules(tester),
        'Takeback is shared — either player can undo the last move. Either '
        'player can agree a draw from the pause card with one tap. '
        'Everything else is tournament legal.',
      );
      rig.settings.updateBoard((o) => o.copyWith(takebackAllowed: false));
      await tester.pump();
      expect(
        _houseRules(tester),
        'Takeback is off in Settings. Either player can agree a draw from '
        'the pause card with one tap. Everything else is tournament legal.',
      );
      rig.settings.updateBoard((o) => o.copyWith(takebackAllowed: true));
      await tester.pump();
      expect(_houseRules(tester), startsWith('Takeback is shared'));
    });
  });

  group('each time choice reaches the started game', () {
    for (final time in TimeChoice.values) {
      testWidgets(time.name, (tester) async {
        final rig = await _pumpSetup(tester);
        await _tap(tester, 'psetup-time-${time.name}');
        expect(rig.settings.setup.value.two.time, time);
        expect(
          rig.settings.setup.value.computer.time,
          TimeChoice.rapid,
          reason: "psetup: the computer's time choice is not touched",
        );
        await _startGame(tester, rig);
        expect(rig.controller.game.mode, isA<TwoPlayer>());
        expect(rig.controller.game.clock.control, time.toTimeControl(10, 5));
        expect(rig.controller.game.history, hasLength(1));
        expect(find.byType(GameScreen), findsOneWidget);
        expect(find.byType(TwoPlayerSetupScreen), findsNothing);
        expect(rig.computers.built, isEmpty);
      });
    }

    testWidgets('Custom starts the shared custom time', (tester) async {
      final rig = await _pumpSetup(tester);
      await _tap(tester, 'psetup-time-custom');
      await _tap(tester, 'psetup-minutes-inc');
      await _tap(tester, 'psetup-increment-dec');
      expect(
        rig.settings.setup.value.custom,
        const CustomTime(minutes: 11, increment: 4),
      );
      await _startGame(tester, rig);
      expect(rig.controller.game.clock.control, Timed(11, 4));
    });
  });

  testWidgets('the rotate switch is the Settings switch, both ways', (
    tester,
  ) async {
    final rig = await _pumpSetup(tester);
    await _tap(tester, 'psetup-rotate');
    expect(rig.settings.board.value.rotateEachTurn, isTrue);
    expect(_rotateRow(tester, 'psetup-rotate'), isTrue);
    expect(
      tester.getSemantics(find.byKey(const Key('psetup-rotate'))),
      isSemantics(
        label: '$rotateLabel, $rotateDescription',
        hasToggledState: true,
        isToggled: true,
        hasTapAction: true,
      ),
    );

    tester
        .state<NavigatorState>(find.byType(Navigator))
        .push(MaterialPageRoute<void>(builder: (_) => const SettingsScreen()));
    await _settleRoute(tester);
    expect(
      _rotateRow(tester, 'settings-toggle-rotate'),
      isTrue,
      reason: 'psetup: Settings shows the rotate chosen here',
    );
    await _tap(tester, 'settings-toggle-rotate');
    expect(rig.settings.board.value.rotateEachTurn, isFalse);
    tester.state<NavigatorState>(find.byType(Navigator)).pop();
    await _settleRoute(tester);
    expect(
      _rotateRow(tester, 'psetup-rotate'),
      isFalse,
      reason: 'psetup: and shows the rotate chosen in Settings',
    );

    for (final expected in [true, false]) {
      await _tap(tester, 'psetup-rotate');
      await rig.store.flush();
      final saved = await rig.store.read(StoreDoc.settings);
      expect(
        decodeBoard((saved as Loaded).data['board']).rotateEachTurn,
        expected,
        reason: 'psetup: the rotate switch is saved as the board setting',
      );
    }
  });

  group('Start game over an unfinished two-player game', () {
    testWidgets('(a) played through the controller: nothing is recorded and '
        'game-computer stays byte-identical', (tester) async {
      final rig = await _pumpSetup(
        tester,
        overBoard: true,
        before: (rig) async {
          await rig.saves.save(_computerGame(), {
            'id': '00000000000000c0',
            'started': true,
            'outcome': false,
          });
          await rig.controller.newGame(
            SetupChoices.initial
                .copyWith(two: const TwoPlayerChoices(time: TimeChoice.blitz))
                .twoPlayerSetup(),
          );
          _move(rig.controller, 'e2e4');
          _move(rig.controller, 'e7e5');
          rig.controller.pause();
        },
      );
      await _drain(tester, rig);
      final computerBefore = rig.store.rawText(StoreDoc.gameComputer);
      expect(computerBefore, isNotNull, reason: 'test: a saved computer game');
      expect((await _savedTwo(rig.store)).history, hasLength(3));

      await _startGame(tester, rig);
      expect(
        rig.twoPlayed,
        0,
        reason: 'psetup: the replaced game is not counted',
      );
      expect(rig.computerLost, 0, reason: 'psetup: nor any computer game');
      final two = await _savedTwo(rig.store);
      expect(two.history, hasLength(1));
      expect(two.position.fullmoveNumber, 1);
      expect(two.clock.control, Timed.rapid);
      expect(rig.store.rawText(StoreDoc.gameComputer), computerBefore);
      expect(
        find.byType(GameScreen, skipOffstage: false),
        findsOneWidget,
        reason: 'psetup: a new game leaves exactly one board',
      );
    });

    testWidgets('(b) only saved, with a paused computer game on the board: '
        'nothing is recorded and game-computer stays byte-identical', (
      tester,
    ) async {
      final started = Game.start(const TwoPlayer(), Timed.classical);
      final twoGame = started.play(Move.fromUci(started.position, 'd2d4'));
      final rig = await _pumpSetup(
        tester,
        before: (rig) async {
          await rig.saves.save(twoGame, {
            'id': '00000000000000d0',
            'started': true,
            'outcome': false,
          });
          await rig.controller.newGame(vsComputerDefault, seed: 5);
          _move(rig.controller, 'e2e4');
          rig.controller.pause();
        },
      );
      await _drain(tester, rig);
      expect(rig.saves.unfinished(PlayMode.two), isNotNull);
      expect(rig.controller.game.mode, isA<VsComputer>());
      final computerBefore = rig.store.rawText(StoreDoc.gameComputer);
      expect(computerBefore, isNotNull, reason: 'test: a saved computer game');

      await _startGame(tester, rig);
      expect(
        rig.twoPlayed,
        0,
        reason: 'psetup: the replaced game is not counted',
      );
      expect(
        rig.computerLost,
        0,
        reason: 'psetup: the computer game is kept, not lost',
      );
      final two = await _savedTwo(rig.store);
      expect(two.history, hasLength(1));
      expect(two.clock.control, Timed.rapid);
      expect(rig.store.rawText(StoreDoc.gameComputer), computerBefore);
      expect(rig.controller.game.mode, isA<TwoPlayer>());
    });
  });

  testWidgets('back from the board returns to it still paused', (tester) async {
    final rig = await _pumpSetup(
      tester,
      overBoard: true,
      before: (rig) async {
        await rig.controller.newGame(twoPlayerDefault);
        _move(rig.controller, 'e2e4');
        rig.controller.pause();
      },
    );
    await _tap(tester, 'psetup-back');
    await _settleRoute(tester);
    expect(find.byType(TwoPlayerSetupScreen), findsNothing);
    expect(find.byType(GameScreen), findsOneWidget);
    expect(rig.controller.state.paused, isTrue);
    expect(rig.controller.game.history, hasLength(2));
  });

  group('the last time choice', () {
    testWidgets('survives a relaunch', (tester) async {
      final store = AppStore.memory();
      final rig = await _pumpSetup(tester, store: store);
      await _tap(tester, 'psetup-time-blitz');
      await rig.store.flush();
      await tester.pumpWidget(const SizedBox());

      final relaunched = await _pumpSetup(tester, store: store);
      expect(relaunched.settings.setup.value.two.time, TimeChoice.blitz);
      expect(_selected(tester, TimeChoice.blitz), isTrue);
      expect(_selected(tester, TimeChoice.rapid), isFalse);
    });

    testWidgets('an unknown stored value opens on Rapid', (tester) async {
      await _pumpSetup(
        tester,
        store: AppStore.memory(
          documents: {
            StoreDoc.settings: {
              'setup': {
                'two': {'time': 'bullet'},
              },
            },
          },
        ),
      );
      expect(_selected(tester, TimeChoice.rapid), isTrue);
      expect(find.byType(TimeControlPicker), findsOneWidget);
    });
  });
}
