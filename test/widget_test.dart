import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:honest_chess/data/app_store.dart';
import 'package:honest_chess/data/play_mode.dart';
import 'package:honest_chess/engine/engine.dart';
import 'package:honest_chess/main.dart';
import 'package:honest_chess/ui/app_scope.dart';
import 'package:honest_chess/ui/board/board_options.dart';
import 'package:honest_chess/ui/board/board_view.dart';
import 'package:honest_chess/ui/game/computer_turns.dart';
import 'package:honest_chess/ui/game/game_controller.dart';
import 'package:honest_chess/ui/game/game_screen.dart';

import 'support/fake_platform_channel.dart';
import 'ui/game/fake_computer.dart';
import 'ui/game/pause_overlay_test.dart' show comeBack, leave;
import 'ui/game/player_panel_test.dart' show text;

void main() {
  testWidgets('the app opens on a game against Club: you White, Rapid 10+5', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final fakes = FakeComputers();
    final store = AppStore.memory();
    final platform = FakePlatformChannel();
    await tester.pumpWidget(
      HonestChessApp(
        computerFactory: fakes.call,
        store: store,
        platform: platform,
      ),
    );
    // The first frame is the loading frame; the saved games are read then.
    await tester.pump();

    final board = tester.widget<BoardView>(find.byType(BoardView));
    expect(
      board.position.toFen(),
      'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1',
      reason: 'app: the play screen starts from the start position',
    );
    expect(board.bottom, Colour.white, reason: 'app: White at the bottom');
    expect(board.options, const BoardOptions(), reason: 'app: design defaults');

    final game = tester
        .state<GameScreenState>(find.byType(GameScreen))
        .controller
        .game;
    expect(game.mode, isA<VsComputer>(), reason: 'app: against the computer');
    final mode = game.mode as VsComputer;
    expect((mode.step, mode.playerColour), (Strength.club, Colour.white));
    expect(game.clock.control, Timed.rapid);
    expect(
      (fakes.current.strength, fakes.current.seed),
      (Strength.club, mode.seed),
      reason: 'app: the computer is built for this game',
    );
    expect(fakes.current.requests, isEmpty, reason: 'app: your move first');

    expect(text(tester, 'name-black'), 'Club');
    expect(text(tester, 'sub-white'), contains('YOU · WHITE'));
    expect(text(tester, 'sub-white'), contains('RAPID 10+5'));
    expect(text(tester, 'status-text'), 'WHITE TO MOVE');

    final state = tester.state<HonestChessAppState>(
      find.byType(HonestChessApp),
    );
    expect(
      state.settings.board.value,
      const BoardOptions(),
      reason: 'app: the root holds the board options',
    );

    final scope = AppScope.of(tester.element(find.byType(GameScreen)));
    expect(
      scope.store,
      same(store),
      reason: 'app: the injected store is the scope\'s',
    );
    expect(
      scope.platform,
      same(platform),
      reason: 'app: the injected platform is the scope\'s',
    );

    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
    expect(scaffold.backgroundColor, const Color(0xFF05285F));

    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.debugShowCheckedModeBanner, isFalse);
    expect(app.title, 'Honest Chess');
    expect(
      app.theme!.textTheme.bodyMedium!.fontFamily,
      'Outfit',
      reason: 'app: Outfit is the app-wide text face',
    );
  });

  testWidgets('from launch: play e2-e4 and the computer replies', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final fakes = FakeComputers();
    await tester.pumpWidget(
      HonestChessApp(
        computerFactory: fakes.call,
        seed: 42,
        store: AppStore.memory(),
        platform: FakePlatformChannel(),
      ),
    );
    await tester.pump();
    expect(fakes.current.seed, 42, reason: 'app: the seed override is used');
    await tester.tap(find.byKey(const Key('cell-e2')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('cell-e4')));
    await tester.pump();
    fakes.current.last.move('e7e5');
    await tester.pump(minThinkTime);
    final screen = tester.state<GameScreenState>(find.byType(GameScreen));
    expect(screen.controller.game.moves.map((m) => m.toUci()), [
      'e2e4',
      'e7e5',
    ], reason: 'app: the computer answers on the home board');
    // The running clock keeps a ticker alive; leaving stops it.
    await tester.pumpWidget(const SizedBox());
  });

  group('saved games', () {
    Future<(GameController, FakeComputers)> launch(
      WidgetTester tester,
      AppStore store, {
      bool resumeSaved = true,
      int? seed,
    }) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final fakes = FakeComputers();
      await tester.pumpWidget(
        HonestChessApp(
          key: UniqueKey(),
          computerFactory: fakes.call,
          store: store,
          platform: FakePlatformChannel(),
          resumeSaved: resumeSaved,
          seed: seed,
        ),
      );
      await tester.pump();
      final root = tester.state<HonestChessAppState>(
        find.byType(HonestChessApp),
      );
      return (root.controller, fakes);
    }

    testWidgets('leaving saves the paused game; the next launch opens on it, '
        'paused', (tester) async {
      final store = AppStore.memory();
      final (first, fakes) = await launch(tester, store);
      expect(
        store.rawText(StoreDoc.gameComputer),
        isNotNull,
        reason: 'app: the new game is saved at once',
      );
      await tester.tap(find.byKey(const Key('cell-e2')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('cell-e4')));
      await tester.pump();
      fakes.current.last.move('e7e5');
      await tester.pump(minThinkTime);
      final seed = (first.game.mode as VsComputer).seed;

      await leave(tester, AppLifecycleState.hidden);
      expect(first.state.paused, isTrue, reason: 'app: leaving pauses');
      final root = tester.state<HonestChessAppState>(
        find.byType(HonestChessApp),
      );
      await root.saves.flush();
      expect(root.saves.load(PlayMode.computer)?.moves, first.game.moves);
      await tester.pumpWidget(const SizedBox());
      await comeBack(tester);

      final (second, again) = await launch(tester, store);
      expect(second.game.moves.map((m) => m.toUci()), ['e2e4', 'e7e5']);
      expect(second.state.paused, isTrue, reason: 'app: restored paused');
      expect(find.byKey(const Key('pause-card')), findsOneWidget);
      expect((second.game.mode as VsComputer).seed, seed);
      expect(again.current.seed, seed, reason: 'app: same computer seed');
      await tester.pump(const Duration(seconds: 1));
      expect(
        again.current.requests,
        isEmpty,
        reason: 'app: nothing is asked of the computer while paused',
      );
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('the device test\'s overrides skip the saved game', (
      tester,
    ) async {
      final store = AppStore.memory();
      final (first, _) = await launch(tester, store);
      first.move(Square.parse('d2'), Square.parse('d4'));
      await tester.pumpWidget(const SizedBox());

      final (second, fakes) = await launch(
        tester,
        store,
        resumeSaved: false,
        seed: 2026,
      );
      expect(second.game.moves, isEmpty);
      expect(second.state.paused, isFalse);
      expect(fakes.current.seed, 2026);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('a finished game found at launch is counted by the root', (
      tester,
    ) async {
      var game = Game.start(
        const VsComputer(
          playerColour: Colour.black,
          step: Strength.club,
          seed: 4,
        ),
        const Untimed(),
      );
      for (final uci in ['f2f3', 'e7e5', 'g2g4', 'd8h4']) {
        game = game.play(
          Move.fromUci(game.position, uci),
          byComputer: game.sideToMove == Colour.white,
        );
      }
      final store = AppStore.memory()
        ..putRaw(
          StoreDoc.gameComputer,
          jsonEncode({
            'format': 1,
            'data': {
              'game': game.toJson(),
              'recorded': {'id': '0123456789abcdef', 'started': true},
            },
          }),
        );
      await launch(tester, store);
      await tester.pump();
      final root = tester.state<HonestChessAppState>(
        find.byType(HonestChessApp),
      );
      await root.saves.flush();
      await root.stats.idle;
      expect(root.stats.isLoaded, isTrue);
      expect(
        (root.stats.document.computer.played, root.stats.document.computer.won),
        (1, 1),
        reason: 'app: the listener is wired before the launch load',
      );
      expect(
        AppScope.of(tester.element(find.byType(GameScreen))).stats,
        same(root.stats),
      );
      await tester.pumpWidget(const SizedBox());
    });
  });

  test(
    'every bundled font licence is registered for the licence page',
    () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      registerFontLicences();
      final entries = await LicenseRegistry.licenses.toList();
      final packages = <String>{for (final e in entries) ...e.packages};
      for (final family in fontLicences.keys) {
        expect(
          packages,
          contains(family),
          reason: 'licences: $family\'s OFL is on the licence page',
        );
      }
      final ofl = entries.where(
        (e) => e.packages.contains('Noto Sans Symbols 2'),
      );
      expect(
        ofl.single.paragraphs.map((p) => p.text).join(' '),
        contains('SIL Open Font License'),
        reason: 'licences: the registered text is the OFL itself',
      );
    },
  );
}
