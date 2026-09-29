import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:honest_chess/data/app_store.dart';
import 'package:honest_chess/data/settings_store.dart';
import 'package:honest_chess/data/stats.dart';
import 'package:honest_chess/engine/engine.dart';
import 'package:honest_chess/ui/board/board_interaction.dart';
import 'package:honest_chess/ui/board/board_options.dart';
import 'package:honest_chess/ui/game/game_controller.dart';
import 'package:honest_chess/ui/game/game_screen.dart';
import 'package:honest_chess/ui/game/result_overlay.dart';
import 'package:honest_chess/ui/motion.dart';
import 'package:honest_chess/ui/screens/settings_screen.dart';
import 'package:honest_chess/ui/screens/stats_screen.dart';
import 'package:honest_chess/ui/widgets/toggle_switch.dart';

import '../support/app_harness.dart';

const _promotionFen = '4k3/P7/8/8/8/8/8/4K3 w - - 0 1';
const _foolsMate = ['f2f3', 'e7e5', 'g2g4', 'd8h4'];

Finder _key(String key) => find.byKey(Key(key));

/// A settings store with Piece animations at [animations].
SettingsStore _settings({required bool animations}) {
  final settings = SettingsStore()
    ..updateBoard((o) => o.copyWith(animations: animations));
  addTearDown(settings.dispose);
  return settings;
}

/// The play screen over a two-player game from [fen], with Piece
/// animations at [animations].
Future<GameController> _board(
  WidgetTester tester, {
  required bool animations,
  String? fen,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final options = BoardOptions(animations: animations);
  final c = GameController(fen: fen, options: options);
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });
  await pumpUnderScope(
    tester,
    GameScreen(options: options, controller: c),
    controller: c,
    settings: _settings(animations: animations),
  );
  return c;
}

void _play(GameController c, String uci) => expect(
  c.move(Square.parse(uci.substring(0, 2)), Square.parse(uci.substring(2))),
  isTrue,
  reason: 'test: $uci is playable',
);

double _opacity(WidgetTester tester, Finder fade) =>
    tester.widget<FadeTransition>(fade).opacity.value;

/// Reads [Motion.of] from under the scope and media query given.
Future<Motion> _motionUnder(
  WidgetTester tester, {
  bool? animations,
  bool disableAnimations = false,
}) async {
  late Motion motion;
  Widget probe = Builder(
    builder: (context) {
      motion = Motion.of(context);
      return const SizedBox();
    },
  );
  if (animations != null) {
    probe = MotionScope(animations: animations, child: probe);
  }
  await tester.pumpWidget(
    MediaQuery(
      data: MediaQueryData(disableAnimations: disableAnimations),
      child: probe,
    ),
  );
  return motion;
}

void main() {
  group('motionFor', () {
    test('full only with the switch on and the phone setting off', () {
      for (final animations in [true, false]) {
        for (final disable in [true, false]) {
          expect(
            motionFor(animations: animations, disableAnimations: disable),
            animations && !disable ? Motion.full : Motion.off,
            reason:
                'motion: animations $animations, remove-animations $disable',
          );
        }
      }
    });
  });

  group('Motion.of', () {
    testWidgets('either off-switch turns motion off', (tester) async {
      expect(await _motionUnder(tester, animations: true), Motion.full);
      expect(
        await _motionUnder(tester, animations: false),
        Motion.off,
        reason: 'motion: Piece animations off',
      );
      expect(
        await _motionUnder(tester, animations: true, disableAnimations: true),
        Motion.off,
        reason: "motion: the phone's remove-animations",
      );
    });

    testWidgets('without a scope only the phone setting counts', (
      tester,
    ) async {
      expect(await _motionUnder(tester), Motion.full);
      expect(await _motionUnder(tester, disableAnimations: true), Motion.off);
    });

    testWidgets('follows the setting live under the harness', (tester) async {
      final settings = _settings(animations: true);
      late Motion motion;
      await pumpUnderScope(
        tester,
        Builder(
          builder: (context) {
            motion = Motion.of(context);
            return const SizedBox();
          },
        ),
        settings: settings,
      );
      expect(motion, Motion.full);
      settings.updateBoard((o) => o.copyWith(animations: false));
      await tester.pump();
      expect(motion, Motion.off, reason: 'motion: read live from Settings');
    });
  });

  group('with Piece animations off, everything is instant', () {
    testWidgets("a refused drop's spring-back", (tester) async {
      for (final animations in [true, false]) {
        await _board(tester, animations: animations);
        final from = tester.getCenter(_key('sq-e2'));
        final to = tester.getCenter(_key('sq-e5'));
        await tester.dragFrom(from, to - from);
        await tester.pump();
        expect(
          _key('spring-back'),
          animations ? findsOneWidget : findsNothing,
          reason: 'motion: spring-back with animations $animations',
        );
        await tester.pump(springBackDuration * 2);
      }
    });

    testWidgets('the promotion card', (tester) async {
      final c = await _board(tester, animations: false, fen: _promotionFen);
      _play(c, 'a7a8');
      await tester.pump();
      final fade = find.ancestor(
        of: _key('promo-card'),
        matching: find.byType(FadeTransition),
      );
      expect(_opacity(tester, fade.first), 1, reason: 'motion: promo in');
      c.cancelPromotion();
      await tester.pump();
      expect(_key('promo-card'), findsNothing, reason: 'motion: promo out');
    });

    testWidgets('the pause card', (tester) async {
      final c = await _board(tester, animations: false);
      c.pause();
      await tester.pump();
      expect(
        _opacity(tester, _key('pause-overlay')),
        1,
        reason: 'motion: pause in',
      );
      c.resume();
      await tester.pump();
      expect(_key('pause-overlay'), findsNothing, reason: 'motion: pause out');
    });

    testWidgets('the result card, after its pacing delay', (tester) async {
      final c = await _board(tester, animations: false);
      for (final uci in _foolsMate) {
        _play(c, uci);
      }
      await tester.pump();
      await tester.pump(resultDelay);
      expect(
        _opacity(tester, _key('result-overlay')),
        1,
        reason: 'motion: the card is in at once after the delay',
      );
      c.viewBoard();
      await tester.pump();
      expect(_key('result-overlay'), findsNothing, reason: 'motion: card out');
    });

    testWidgets("a switch's knob", (tester) async {
      tester.view.physicalSize = const Size(390, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final settings = _settings(animations: true);
      await pumpUnderScope(tester, const SettingsScreen(), settings: settings);
      await tester.pump();
      final row = _key('settings-toggle-anim');
      await tester.ensureVisible(row);
      await tester.tap(row);
      await tester.pump();
      expect(settings.board.value.animations, isFalse);
      final knob = find.descendant(
        of: row,
        matching: find.byKey(ToggleSwitch.knobKey),
      );
      final track = find.descendant(
        of: row,
        matching: find.byType(ToggleSwitch),
      );
      expect(
        tester.getTopLeft(knob).dx - tester.getTopLeft(track).dx,
        ToggleSwitch.knobOff,
        reason: "motion: the switch's own knob follows its new value at once",
      );
    });

    testWidgets("Statistics' reset card", (tester) async {
      tester.view.physicalSize = const Size(390, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final store = AppStore.memory();
      final stats = StatsRecorder(store: store);
      addTearDown(stats.dispose);
      await stats.load();
      await pumpUnderScope(
        tester,
        const StatsScreen(),
        store: store,
        stats: stats,
        settings: _settings(animations: false),
      );
      await tester.pump();
      await tester.scrollUntilVisible(
        _key('stats-reset'),
        200,
        scrollable: find.descendant(
          of: _key('stats-scroll'),
          matching: find.byType(Scrollable),
        ),
      );
      await tester.tap(_key('stats-reset'));
      await tester.pump();
      expect(
        _opacity(tester, _key('stats-reset-overlay')),
        1,
        reason: 'motion: the reset card is in at once',
      );
    });
  });
}
