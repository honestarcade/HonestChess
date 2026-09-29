import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:honest_chess/data/app_store.dart';
import 'package:honest_chess/data/game_saves.dart';
import 'package:honest_chess/data/play_mode.dart';
import 'package:honest_chess/data/stats.dart';
import 'package:honest_chess/engine/engine.dart';
import 'package:honest_chess/ui/content/stats_view.dart';
import 'package:honest_chess/ui/screens/stats_screen.dart';
import 'package:honest_chess/ui/theme/palette.dart';

import '../support/app_harness.dart';

/// Win one against Beginner, lose one against Club: the story's demo.
const _demo = StatsDocument(
  computer: ComputerStats(
    played: 2,
    won: 1,
    lost: 1,
    longestMoves: 31,
    steps: {
      Strength.beginner: StepStats(played: 1, won: 1),
      Strength.casual: StepStats(),
      Strength.club: StepStats(played: 1),
      Strength.strong: StepStats(),
      Strength.master: StepStats(),
    },
  ),
  two: TwoPlayerStats(
    played: 3,
    whiteWins: 2,
    drawn: 1,
    longestMoves: 40,
    clocks: {
      StatsClock.untimed: 2,
      StatsClock.blitz: 0,
      StatsClock.rapid: 1,
      StatsClock.classical: 0,
      StatsClock.custom: 0,
    },
  ),
);

/// A recorder whose reset can be held open ([gate]) and made to fail
/// [failures] times before it runs for real.
class _TestRecorder extends StatsRecorder {
  _TestRecorder(AppStore store) : super(store: store);

  int failures = 0;
  Completer<void>? gate;
  int resets = 0;

  @override
  Future<void> resetAll() async {
    resets++;
    final held = gate;
    if (held != null) await held.future;
    if (failures > 0) {
      failures--;
      throw const StatsResetFailed();
    }
    return super.resetAll();
  }
}

class _Rig {
  _Rig(this.store, this.stats, this.harness);

  final AppStore store;
  final _TestRecorder stats;
  final AppHarness harness;
}

Future<_Rig> _pump(
  WidgetTester tester, {
  StatsDocument document = _demo,
  PlayMode? openOn,
  PlayMode? lastPlayed,
  Size size = const Size(390, 844),
  bool disableAnimations = false,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  if (disableAnimations) {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
  }
  final store = AppStore.memory(
    documents: {
      StoreDoc.stats: document.toJson(),
      if (lastPlayed != null) StoreDoc.meta: {'lastPlayed': lastPlayed.name},
    },
  );
  final stats = _TestRecorder(store);
  final saves = GameSaves(store);
  addTearDown(() {
    saves.dispose();
    stats.dispose();
  });
  await stats.load();
  await saves.loadMeta();
  final harness = await pumpUnderScope(
    tester,
    StatsScreen(openOn: openOn),
    store: store,
    stats: stats,
    saves: saves,
  );
  await tester.pump();
  return _Rig(store, stats, harness);
}

Finder _key(String key) => find.byKey(Key(key));

String _text(WidgetTester tester, String key) =>
    tester.widget<Text>(_key(key)).data!;

String _card(WidgetTester tester, String name) =>
    _text(tester, 'stats-card-$name-value');

String _row(WidgetTester tester, String name) =>
    _text(tester, 'stats-row-$name-value');

bool _selected(WidgetTester tester, PlayMode tab) =>
    isSemantics(isSelected: true)
        .matches(tester.getSemantics(_key('stats-tab-${tab.name}')), {});

final _scrollable = find.descendant(
  of: _key('stats-scroll'),
  matching: find.byType(Scrollable),
);

double _offset(WidgetTester tester) =>
    tester.state<ScrollableState>(_scrollable).position.pixels;

Future<void> _open(WidgetTester tester) async {
  await tester.scrollUntilVisible(
    _key('stats-reset'),
    100,
    scrollable: _scrollable,
  );
  await tester.tap(_key('stats-reset'));
  await tester.pump();
  await tester.pump(resetEnterDuration + const Duration(milliseconds: 16));
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(resetExitDuration + const Duration(milliseconds: 16));
  await tester.pump();
}

/// Every card shows a dash and every row is empty, on the shown tab.
void _expectEmpty(WidgetTester tester, PlayMode tab) {
  final cards = switch (tab) {
    PlayMode.computer => [
      'games-played',
      'win-rate',
      'draws',
      'current-streak',
      'usual-level',
      'longest-game',
    ],
    PlayMode.two => [
      'games-played',
      'white-wins',
      'black-wins',
      'draws',
      'usual-clock',
      'longest-game',
    ],
  };
  for (final name in cards) {
    expect(_card(tester, name), '—', reason: '$tab $name');
  }
  final rows = switch (tab) {
    PlayMode.computer => [for (final s in Strength.values) s.name],
    PlayMode.two => [for (final c in StatsClock.values) c.name],
  };
  for (final name in rows) {
    expect(
      _row(tester, name),
      tab == PlayMode.computer ? '0 / 0 · —' : '0 games',
      reason: '$tab $name',
    );
    expect(
      tester
          .widget<FractionallySizedBox>(_key('stats-row-$name-bar'))
          .widthFactor,
      0,
    );
  }
}

List<String> _captureAnnouncements(WidgetTester tester) {
  final said = <String>[];
  tester.binding.defaultBinaryMessenger.setMockDecodedMessageHandler<Object?>(
    SystemChannels.accessibility,
    (message) async {
      final map = message! as Map<Object?, Object?>;
      if (map['type'] == 'announce') {
        said.add((map['data']! as Map<Object?, Object?>)['message']! as String);
      }
      return null;
    },
  );
  addTearDown(
    () => tester.binding.defaultBinaryMessenger
        .setMockDecodedMessageHandler<Object?>(
          SystemChannels.accessibility,
          null,
        ),
  );
  return said;
}

void main() {
  group('opening tab', () {
    testWidgets('openOn wins over the mode played last', (tester) async {
      await _pump(tester, openOn: PlayMode.two, lastPlayed: PlayMode.computer);
      expect(_selected(tester, PlayMode.two), isTrue);
      expect(_selected(tester, PlayMode.computer), isFalse);
      expect(_key('stats-card-white-wins'), findsOneWidget);
      expect(_key('stats-card-win-rate'), findsNothing);
    });

    testWidgets('without openOn, the mode played last', (tester) async {
      await _pump(tester, lastPlayed: PlayMode.two);
      expect(_selected(tester, PlayMode.two), isTrue);
      expect(_key('stats-row-untimed'), findsOneWidget);
      expect(_key('stats-row-beginner'), findsNothing);
    });

    testWidgets('with neither, vs Computer', (tester) async {
      await _pump(tester);
      expect(_selected(tester, PlayMode.computer), isTrue);
      expect(_key('stats-card-win-rate'), findsOneWidget);
      expect(_key('stats-card-white-wins'), findsNothing);
    });
  });

  group('numbers', () {
    testWidgets('the demo: vs Computer cards and rows', (tester) async {
      await _pump(tester);
      expect(_text(tester, 'stats-title'), 'Statistics');
      expect(_card(tester, 'games-played'), '2');
      expect(_card(tester, 'win-rate'), '50%');
      expect(_text(tester, 'stats-card-win-rate-caption'), '1 won');
      expect(_card(tester, 'current-streak'), '0');
      expect(_row(tester, 'beginner'), '1 / 1 · 100%');
      expect(_row(tester, 'club'), '0 / 1 · 0%');
      expect(_row(tester, 'master'), '0 / 0 · —');
      expect(_text(tester, 'stats-breakdown-title'), 'BY STRENGTH');
      // Only WIN RATE is teal.
      expect(
        tester.widget<Text>(_key('stats-card-win-rate-value')).style!.color,
        Palette.teal,
      );
      expect(
        tester.widget<Text>(_key('stats-card-draws-value')).style!.color,
        const Color(0xFFFFFFFF),
      );
      // The club row's bar is a sliver of its track, Beginner's the whole.
      final track = tester.getSize(_key('stats-row-club-track')).width;
      expect(
        tester.getSize(_key('stats-row-club-bar')).width,
        closeTo(track * minBarFraction, 1e-6),
      );
      expect(
        tester.getSize(_key('stats-row-beginner-bar')).width,
        closeTo(track, 1e-6),
      );
    });

    testWidgets('a tab switch swaps at once and scrolls to the top', (
      tester,
    ) async {
      await _pump(tester, size: const Size(390, 500));
      await tester.drag(_key('stats-scroll'), const Offset(0, -40));
      await tester.pump();
      expect(_offset(tester), greaterThan(0));
      await tester.tap(_key('stats-tab-two'));
      await tester.pump();
      expect(_offset(tester), 0);
      expect(_card(tester, 'white-wins'), '2');
      expect(_text(tester, 'stats-card-white-wins-caption'), '67% of games');
      expect(_card(tester, 'usual-clock'), 'Untimed');
      expect(_row(tester, 'rapid'), '1 game');
      expect(_text(tester, 'stats-breakdown-title'), 'BY TIME CONTROL');
    });

    testWidgets('a number too wide for its card shrinks, never cut', (
      tester,
    ) async {
      await _pump(
        tester,
        document: const StatsDocument(
          computer: ComputerStats(played: 1234567890, longestMoves: 987654321),
        ),
        size: const Size(320, 700),
      );
      // The drawn (scaled) value sits inside its card.
      final card = tester.getRect(_key('stats-card-games-played'));
      final value = tester.getRect(_key('stats-card-games-played-value'));
      expect(value.left, greaterThanOrEqualTo(card.left));
      expect(value.right, lessThanOrEqualTo(card.right));
      expect(_card(tester, 'games-played'), '1,234,567,890');
      expect(tester.takeException(), isNull);
    });

    testWidgets('each card and row is one spoken node', (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(tester);
      expect(
        tester.getSemantics(_key('stats-card-win-rate')),
        isSemantics(label: 'Win rate, 50%, 1 won'),
      );
      expect(
        tester.getSemantics(_key('stats-row-club')),
        isSemantics(label: 'Club, 0 won of 1, 0%'),
      );
      expect(
        tester.getSemantics(_key('stats-row-master')),
        isSemantics(label: 'Master, no games'),
      );
      handle.dispose();
    });
  });

  group('reset', () {
    testWidgets('opens the confirmation, reworded for Android backup', (
      tester,
    ) async {
      final said = _captureAnnouncements(tester);
      await _pump(tester);
      expect(_key('stats-reset-card'), findsNothing);
      await _open(tester);
      expect(_text(tester, 'stats-reset-title'), 'Reset statistics?');
      expect(
        _text(tester, 'stats-reset-body'),
        'Clears every recorded game, streak and result for both the computer '
        'and pass-and-play. Nothing was ever uploaded by this app, so it '
        'keeps no other copy.',
      );
      expect(said, ['$resetTitle $resetBody']);
      // Focus rests on Cancel.
      final cancel = tester.widget<InkWell>(_key('stats-reset-cancel'));
      expect(cancel.autofocus, isTrue);
      expect(
        Focus.of(
          tester.element(
            find.descendant(
              of: _key('stats-reset-cancel'),
              matching: find.byType(Text),
            ),
          ),
        ).hasFocus,
        isTrue,
      );
    });

    testWidgets('even with nothing recorded, Reset statistics asks first', (
      tester,
    ) async {
      final rig = await _pump(tester, document: const StatsDocument.empty());
      await _open(tester);
      expect(_key('stats-reset-card'), findsOneWidget);
      expect(rig.stats.resets, 0);
    });

    testWidgets('Cancel changes nothing, byte for byte', (tester) async {
      final rig = await _pump(tester);
      final before = rig.store.rawText(StoreDoc.stats);
      await _open(tester);
      await tester.tap(_key('stats-reset-cancel'));
      await _settle(tester);
      expect(_key('stats-reset-card'), findsNothing);
      expect(rig.stats.resets, 0);
      await rig.store.flush();
      expect(rig.store.rawText(StoreDoc.stats), before);
      expect(_card(tester, 'games-played'), '2');
      // Focus goes back to Reset statistics.
      expect(
        Focus.of(
          tester.element(
            find.descendant(
              of: _key('stats-reset'),
              matching: find.byType(Text),
            ),
          ),
        ).hasFocus,
        isTrue,
      );
    });

    testWidgets('a scrim tap and Android back cancel too', (tester) async {
      final rig = await _pump(tester);
      await _open(tester);
      await tester.tapAt(const Offset(10, 10));
      await _settle(tester);
      expect(_key('stats-reset-card'), findsNothing);

      await _open(tester);
      await tester.binding.handlePopRoute();
      await _settle(tester);
      expect(_key('stats-reset-card'), findsNothing);
      // Back with the card closed leaves nothing else to cancel, and the
      // screen itself is the only route.
      expect(find.byType(StatsScreen), findsOneWidget);
      expect(rig.stats.resets, 0);
      expect(_card(tester, 'games-played'), '2');
    });

    testWidgets('Reset clears both tabs at once and persists', (tester) async {
      final said = _captureAnnouncements(tester);
      final rig = await _pump(tester, size: const Size(390, 600));
      await _open(tester);
      final scrolled = _offset(tester);
      await tester.tap(_key('stats-reset-confirm'));
      await _settle(tester);
      expect(_key('stats-reset-card'), findsNothing);
      expect(said.last, 'Statistics reset');
      // Same tab, same place.
      expect(_offset(tester), scrolled);
      await tester.drag(_key('stats-scroll'), const Offset(0, 1000));
      await tester.pump();
      expect(_selected(tester, PlayMode.computer), isTrue);
      _expectEmpty(tester, PlayMode.computer);
      expect(_text(tester, 'stats-card-games-played-caption'), 'Since reset');
      await tester.tap(_key('stats-tab-two'));
      await tester.pump();
      _expectEmpty(tester, PlayMode.two);
      expect(_text(tester, 'stats-card-games-played-caption'), 'Since reset');

      await rig.store.flush();
      final read = await rig.store.read(StoreDoc.stats);
      final stored = StatsDocument.fromJson((read as Loaded).data);
      expect(stored.computer.played, 0);
      expect(stored.two.played, 0);
      expect(stored.resetAt, isNotNull);
    });

    testWidgets('while resetting, nothing else can be pressed', (tester) async {
      final rig = await _pump(tester);
      rig.stats.gate = Completer();
      await _open(tester);
      await tester.tap(_key('stats-reset-confirm'));
      await tester.pump();
      expect(rig.stats.resets, 1);
      for (final key in ['stats-reset-cancel', 'stats-reset-confirm']) {
        expect(tester.widget<InkWell>(_key(key)).onTap, isNull);
        expect(
          tester
              .widget<Opacity>(
                find
                    .ancestor(of: _key(key), matching: find.byType(Opacity))
                    .first,
              )
              .opacity,
          0.4,
        );
      }
      await tester.tapAt(const Offset(10, 10));
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(_key('stats-reset-card'), findsOneWidget);
      rig.stats.gate!.complete();
      // The held reset writes, then the card closes.
      await tester.pump(const Duration(milliseconds: 16));
      await _settle(tester);
      expect(_key('stats-reset-card'), findsNothing);
      _expectEmpty(tester, PlayMode.computer);
    });

    testWidgets('a failed reset keeps the numbers; the retry clears them', (
      tester,
    ) async {
      final rig = await _pump(tester);
      rig.stats.failures = 1;
      final before = rig.store.rawText(StoreDoc.stats);
      await _open(tester);
      expect(_key('stats-reset-error'), findsNothing);
      await tester.tap(_key('stats-reset-confirm'));
      await tester.pump();
      await tester.pump();
      expect(_text(tester, 'stats-reset-error'), "Couldn't reset — try again");
      expect(_key('stats-reset-card'), findsOneWidget);
      for (final key in ['stats-reset-cancel', 'stats-reset-confirm']) {
        expect(tester.widget<InkWell>(_key(key)).onTap, isNotNull);
      }
      await rig.store.flush();
      expect(rig.store.rawText(StoreDoc.stats), before);
      expect(_card(tester, 'games-played'), '2');

      await tester.tap(_key('stats-reset-confirm'));
      await tester.pump();
      expect(_key('stats-reset-error'), findsNothing);
      await _settle(tester);
      expect(_key('stats-reset-card'), findsNothing);
      _expectEmpty(tester, PlayMode.computer);
      await tester.tap(_key('stats-tab-two'));
      await tester.pump();
      _expectEmpty(tester, PlayMode.two);
    });

    testWidgets('buttons: drawn at the design size, 48 dp to touch, and '
        'their pressed looks', (tester) async {
      await _pump(tester);
      await tester.scrollUntilVisible(
        _key('stats-reset'),
        100,
        scrollable: _scrollable,
      );
      expect(tester.getSize(_key('stats-reset-box')).height, 41);
      expect(tester.getSize(_key('stats-reset')).height, 48);
      BoxDecoration box(String key) =>
          tester.widget<Container>(_key('$key-box')).decoration!
              as BoxDecoration;
      expect(box('stats-reset').border!.top.color, Palette.resignEdge);
      final press = await tester.startGesture(
        tester.getCenter(_key('stats-reset')),
      );
      await tester.pump(const Duration(milliseconds: 200));
      expect(box('stats-reset').border!.top.color, Palette.danger);
      await press.cancel();
      await tester.pump();

      await _open(tester);
      expect(tester.getSize(_key('stats-reset-cancel-box')).height, 39);
      final cancel = await tester.startGesture(
        tester.getCenter(_key('stats-reset-cancel')),
      );
      await tester.pump(const Duration(milliseconds: 200));
      expect(box('stats-reset-cancel').border!.top.color, Palette.teal);
      await cancel.cancel();
      await tester.pump();
      final confirm = await tester.startGesture(
        tester.getCenter(_key('stats-reset-confirm')),
      );
      await tester.pump(const Duration(milliseconds: 200));
      expect(box('stats-reset-confirm').color, Palette.dangerPressed);
      await confirm.cancel();
      await tester.pump();
      expect(box('stats-reset-confirm').color, Palette.danger);
    });

    testWidgets('with animations off, the card comes and goes at once', (
      tester,
    ) async {
      await _pump(tester, disableAnimations: true);
      await tester.ensureVisible(_key('stats-reset'));
      await tester.pump();
      await tester.tap(_key('stats-reset'));
      await tester.pump();
      expect(tester.hasRunningAnimations, isFalse);
      expect(
        tester
            .widget<FadeTransition>(_key('stats-reset-overlay'))
            .opacity
            .value,
        1,
      );
      await tester.tap(_key('stats-reset-cancel'));
      await tester.pump();
      expect(tester.hasRunningAnimations, isFalse);
      await tester.pump();
      expect(_key('stats-reset-card'), findsNothing);
    });

    testWidgets('the scrim covers the whole screen, bars included', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _pump(tester);
      tester.view.padding = const FakeViewPadding(top: 44, bottom: 34);
      await tester.pump();
      await _open(tester);
      expect(
        tester.getRect(_key('stats-reset-scrim')),
        const Rect.fromLTWH(0, 0, 390, 844),
      );
      expect(
        tester.getSemantics(_key('stats-reset-scrim')),
        isSemantics(label: 'Cancel reset', isButton: true),
      );
      // Behind the scrim, nothing is spoken.
      expect(find.semantics.byLabel('Win rate, 50%, 1 won'), findsNothing);
      expect(find.semantics.byLabel(resetTitle), findsOne);
      handle.dispose();
    });
  });
}
