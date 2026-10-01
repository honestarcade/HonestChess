// Labels and roles (#103): on every screen and state of a11y_cases.dart,
// every control tells a screen-reader user what it is and what it does —
// a label naming it (glyphs spoken as words) and a role (button, link,
// toggle, a choice in a group, a tab). The board's 64 squares are left to
// #102's board_semantics_test.dart, which owns them. Then the readings M3
// and M4 left for M5: the tab bars, the splash, the version lines, the
// loss warning, the promise chips, and the headings a screen reader
// navigates by.
import 'dart:async';
import 'dart:ui' show CheckedState, SemanticsRole, Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:honest_chess/data/app_loader.dart';
import 'package:honest_chess/data/app_store.dart';
import 'package:honest_chess/data/game_saves.dart';
import 'package:honest_chess/data/settings_store.dart';
import 'package:honest_chess/data/stats.dart';
import 'package:honest_chess/platform/platform_channel.dart';
import 'package:honest_chess/ui/content/about_content.dart';
import 'package:honest_chess/ui/screens/about_app_screen.dart';
import 'package:honest_chess/ui/screens/how_to_play_screen.dart';
import 'package:honest_chess/ui/screens/settings_screen.dart';
import 'package:honest_chess/ui/screens/splash_screen.dart';
import 'package:honest_chess/ui/widgets/external_link.dart';

import '../support/app_harness.dart';
import '../support/gated_store.dart';
import 'a11y_cases.dart';

/// Tall enough that every lazily built list builds all of its rows.
const _tall = Size(390, 2400);

void _setTall(WidgetTester tester) {
  tester.view.physicalSize = _tall;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

SemanticsNode _root(WidgetTester tester) =>
    tester.binding.renderViews.first.owner!.semanticsOwner!.rootSemanticsNode!;

/// Every node on screen, in the order a screen reader moves through them.
List<SemanticsNode> _nodes(WidgetTester tester) {
  final out = <SemanticsNode>[];
  void walk(SemanticsNode node) {
    out.add(node);
    node
        .debugListChildrenInOrder(DebugSemanticsDumpOrder.traversalOrder)
        .forEach(walk);
  }

  walk(_root(tester));
  return out;
}

/// A board square's node, as #102 labels it: "e4, empty".
final _squareLabel = RegExp(r'^[a-h][1-8], ');

bool _isSquare(SemanticsData data) => _squareLabel.hasMatch(data.label);

/// A node a finger or a screen reader can act on.
bool _tappable(SemanticsData data) =>
    data.hasAction(SemanticsAction.tap) ||
    data.hasAction(SemanticsAction.longPress) ||
    data.hasAction(SemanticsAction.increase) ||
    data.hasAction(SemanticsAction.decrease) ||
    (data.customSemanticsActionIds?.isNotEmpty ?? false);

/// The role a screen reader names: button, link, toggle, a choice in a
/// group, a tab, or a slider.
String? _role(SemanticsData data) {
  final f = data.flagsCollection;
  if (data.role == SemanticsRole.tab) return 'tab';
  if (f.isButton) return 'button';
  if (f.isLink) return 'link';
  if (f.isToggled != Tristate.none) return 'toggle';
  if (f.isChecked != CheckedState.none) return 'checkbox';
  if (f.isSlider) return 'slider';
  if (f.isSelected != Tristate.none && f.isInMutuallyExclusiveGroup) {
    return 'choice';
  }
  return null;
}

/// The characters the screens draw that must be spoken as words.
final _glyphs = RegExp('[‹↗↺⟳⚑✚✓❚·]');

/// An upper-case display word, which a label says in sentence case.
final _shouting = RegExp(r'\b[A-Z]{2,}\b');

/// What is wrong with the screen as a screen reader meets it, and how many
/// board squares were left out.
({List<String> problems, int squares, int tappables}) _audit(
  WidgetTester tester,
) {
  final problems = <String>[];
  var squares = 0, tappables = 0;
  for (final node in _nodes(tester)) {
    final data = node.getSemanticsData();
    if (_isSquare(data)) {
      squares++;
      continue;
    }
    final label = data.label.trim();
    final role = _role(data);
    final what = label.isEmpty ? 'node #${node.id}' : '"$label"';
    if (_glyphs.hasMatch(data.label)) {
      problems.add('$what reads a glyph');
    }
    if (_shouting.hasMatch(data.label)) {
      problems.add('$what reads upper-case display text');
    }
    if (role != null && label.isEmpty) {
      problems.add('$what: a $role with no label');
    }
    if (_tappable(data)) {
      tappables++;
      if (label.isEmpty && role == null) {
        problems.add('$what: a tappable with no label');
      }
      if (role == null) problems.add('$what: a tappable with no role');
    } else if (role != null &&
        data.flagsCollection.isEnabled != Tristate.isFalse) {
      problems.add('$what: a $role nothing can activate');
    }
  }
  return (problems: problems, squares: squares, tappables: tappables);
}

/// The headers in reading order: (level, label).
List<(int, String)> _headers(WidgetTester tester) => [
  for (final node in _nodes(tester))
    if (node.getSemanticsData().flagsCollection.isHeader)
      (node.getSemanticsData().headingLevel, node.getSemanticsData().label),
];

List<String> _labels(WidgetTester tester) => [
  for (final node in _nodes(tester))
    if (node.getSemanticsData().label.isNotEmpty) node.getSemanticsData().label,
];

SemanticsData _byLabel(WidgetTester tester, String label) =>
    tester.getSemantics(find.bySemanticsLabel(label)).getSemanticsData();

void main() {
  group('the audit', () {
    testWidgets('fails on an unlabelled control, a control with no role, a '
        'glyph or capitals read aloud, and a button nothing can press', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      _setTall(tester);
      await pumpUnderScope(
        tester,
        Scaffold(
          body: Column(
            children: [
              GestureDetector(
                onTap: () {},
                child: const SizedBox.square(dimension: 48),
              ),
              Semantics(
                label: 'Plain',
                onTap: () {},
                child: const SizedBox.square(dimension: 48),
              ),
              Semantics(
                button: true,
                label: '↺',
                onTap: () {},
                child: const SizedBox.square(dimension: 48),
              ),
              Semantics(
                button: true,
                label: 'NO ADS',
                onTap: () {},
                child: const SizedBox.square(dimension: 48),
              ),
              Semantics(
                button: true,
                enabled: false,
                child: const SizedBox.square(dimension: 48),
              ),
              SizedBox(width: 200, child: Slider(value: 0, onChanged: (_) {})),
              Semantics(
                button: true,
                label: 'Inert',
                excludeSemantics: true,
                child: GestureDetector(
                  onTap: () {},
                  child: const SizedBox.square(dimension: 48),
                ),
              ),
            ],
          ),
        ),
      );
      final problems = _audit(tester).problems;
      expect(
        problems.where((p) => p.endsWith('a tappable with no label')),
        hasLength(1),
        reason: 'labels: an unlabelled tappable is reported',
      );
      expect(problems, contains('"Plain": a tappable with no role'));
      expect(problems, contains('"↺" reads a glyph'));
      expect(problems, contains('"NO ADS" reads upper-case display text'));
      expect(
        problems.where((p) => p.endsWith('a button with no label')),
        hasLength(1),
        reason: 'labels: a disabled button still needs its label',
      );
      expect(problems, contains('"Inert": a button nothing can activate'));
      expect(
        problems.where((p) => p.endsWith('a slider with no label')),
        hasLength(1),
        reason: 'labels: an unlabelled slider is reported',
      );
      handle.dispose();
    });
  });

  group('every screen', () {
    for (final c in a11yCases) {
      testWidgets('${c.name}: every control has a label and a role', (
        tester,
      ) async {
        final handle = tester.ensureSemantics();
        _setTall(tester);
        await c.pump(tester);
        final audit = _audit(tester);
        expect(
          audit.problems,
          isEmpty,
          reason: 'labels: ${c.name} has unlabelled or roleless controls',
        );
        expect(
          audit.tappables,
          c.name.startsWith('the splash') ? 0 : greaterThan(0),
          reason: 'labels: the walk reached ${c.name}\'s controls',
        );
        expect(
          audit.squares,
          c.name.startsWith('the board') && !c.covered ? 64 : 0,
          reason:
              'labels: only the board\'s 64 squares are left out, and '
              'none while a card covers them',
        );
        handle.dispose();
      });
    }
  });

  group('glyphs and roles', () {
    testWidgets('the back button, the tools and the links speak words', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      _setTall(tester);
      final board = a11yCases.firstWhere(
        (c) => c.name == 'the board, you to move',
      );
      await board.pump(tester);
      for (final tool in ['Take back', 'Restart', 'Resign', 'New game']) {
        expect(
          _byLabel(tester, tool).flagsCollection.isButton,
          isTrue,
          reason: 'labels: the tool reads "$tool", a button',
        );
      }
      await tester.pumpWidget(const SizedBox());

      await pumpUnderScope(tester, const AboutAppScreen());
      await settleCase(tester);
      expect(_byLabel(tester, 'Back').flagsCollection.isButton, isTrue);
      for (final link in ['Honest Arcade', 'Source on GitHub']) {
        final data = _byLabel(tester, link);
        expect(
          data.flagsCollection.isLink,
          isTrue,
          reason: 'labels: "$link" is a link',
        );
        expect(
          data.hint,
          opensInBrowser,
          reason: 'labels: ↗ is the hint "opens in browser"',
        );
      }
      handle.dispose();
    });

    testWidgets('the tabs read as a tab bar: name, position, selected', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      _setTall(tester);
      await pumpUnderScope(tester, const HowToPlayScreen());
      await settleCase(tester);
      final bars = [
        for (final node in _nodes(tester))
          if (node.getSemanticsData().role == SemanticsRole.tabBar) node,
      ];
      expect(bars, hasLength(1), reason: 'labels: one tab bar');
      final tabs = bars.single
          .debugListChildrenInOrder(DebugSemanticsDumpOrder.traversalOrder)
          .map((n) => n.getSemanticsData())
          .toList();
      expect(
        [for (final t in tabs) t.role],
        [SemanticsRole.tab, SemanticsRole.tab],
        reason: 'labels: the bar holds two tabs',
      );
      expect(
        [for (final t in tabs) t.label],
        ['The pieces, tab, 1 of 2', 'The rules, tab, 2 of 2'],
        reason: 'labels: each tab says its name and its place',
      );
      expect(
        [for (final t in tabs) t.flagsCollection.isSelected],
        [Tristate.isTrue, Tristate.isFalse],
        reason: 'labels: the open tab is selected',
      );
      expect(
        [for (final t in tabs) t.flagsCollection.isButton],
        [false, false],
        reason: 'labels: a tab is a tab, not a button',
      );
      for (final t in tabs) {
        expect(t.flagsCollection.isInMutuallyExclusiveGroup, isTrue);
        expect(t.hasAction(SemanticsAction.tap), isTrue);
      }
      handle.dispose();
    });
  });

  group('M3 and M4 leftovers', () {
    testWidgets('the splash is one "Loading Honest Chess" node, never '
        'announced again as the bar fills', (tester) async {
      final handle = tester.ensureSemantics();
      _setTall(tester);
      final store = GatedStore();
      final settings = SettingsStore();
      final stats = StatsRecorder(store: store);
      final saves = GameSaves(store);
      final loader = AppLoader(
        store: store,
        settings: settings,
        stats: stats,
        saves: saves,
      );
      addTearDown(() {
        loader.dispose();
        saves.dispose();
        stats.dispose();
        settings.dispose();
      });
      final harness = await pumpUnderScope(
        tester,
        SplashScreen(loader: loader),
      );
      await tester.pump(const Duration(milliseconds: 50));
      final seen = <List<String>>[];
      for (final doc in [null, ...StoreDoc.values]) {
        if (doc != null) store.release(doc);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
        if (find.byKey(const Key('splash')).evaluate().isEmpty) break;
        seen.add(_labels(tester));
        final data = _byLabel(tester, splashSemanticsLabel);
        expect(
          data.flagsCollection.isLiveRegion,
          isFalse,
          reason: 'labels: the splash is not a live region',
        );
      }
      expect(seen.length, greaterThan(2), reason: 'test: the bar moved');
      expect(seen.toSet().map((l) => l.join('|')).toSet(), {
        splashSemanticsLabel,
      }, reason: 'labels: one node, one label, while the bar fills');
      expect(
        harness.announcer.spoken,
        isEmpty,
        reason: 'labels: nothing is announced while loading',
      );
      store.releaseAll();
      await tester.pump(const Duration(seconds: 2));
      handle.dispose();
    });

    Future<void> settingsWith(
      WidgetTester tester,
      Future<AppVersion?> Function() answer,
    ) async {
      final platform = FakePlatformChannel()..onAppVersion = answer;
      await pumpUnderScope(tester, const SettingsScreen(), platform: platform);
      await settleCase(tester);
    }

    testWidgets('Settings\' version line reads in words', (tester) async {
      final handle = tester.ensureSemantics();
      _setTall(tester);
      await settingsWith(
        tester,
        () async => const AppVersion(name: '0.1.0', code: 1),
      );
      expect(find.text('v0.1.0 · BUILD 1'), findsOneWidget);
      expect(
        find.bySemanticsLabel('Version 0.1.0, build 1'),
        findsOneWidget,
        reason: 'labels: "Version 0.1.0, build 1"',
      );
      await tester.pumpWidget(const SizedBox());

      await settingsWith(
        tester,
        () async => const AppVersion(name: '0.2.0-beta.1', code: 7),
      );
      expect(
        find.bySemanticsLabel('Version 0.2.0-beta.1, build 7'),
        findsOneWidget,
        reason: 'labels: a prerelease suffix is read as written',
      );
      await tester.pumpWidget(const SizedBox());

      await settingsWith(tester, () async => null);
      expect(find.bySemanticsLabel(versionUnavailable), findsOneWidget);
      await tester.pumpWidget(const SizedBox());

      final pending = Completer<AppVersion?>();
      await settingsWith(tester, () => pending.future);
      expect(
        _labels(tester).where((l) => l.contains('ersion')),
        isEmpty,
        reason: 'labels: the empty line is hidden until Android answers',
      );
      pending.complete(null);
      handle.dispose();
    });

    testWidgets('About the app\'s version line reads in words', (tester) async {
      final handle = tester.ensureSemantics();
      _setTall(tester);
      final platform = FakePlatformChannel()
        ..onAppVersion = () async => const AppVersion(name: '0.1.0', code: 1);
      await pumpUnderScope(tester, const AboutAppScreen(), platform: platform);
      await settleCase(tester);
      expect(find.text('v0.1.0 · OFFLINE'), findsOneWidget);
      expect(
        find.bySemanticsLabel('Version 0.1.0, offline'),
        findsOneWidget,
        reason: 'labels: "Version 0.1.0, offline"',
      );
      await tester.pumpWidget(const SizedBox());

      platform.onAppVersion = () async => null;
      await pumpUnderScope(tester, const AboutAppScreen(), platform: platform);
      await settleCase(tester);
      expect(find.bySemanticsLabel(RegExp(r'^Offline$')), findsOneWidget);
      handle.dispose();
    });

    testWidgets('the loss warning is its own line, right after Start game', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      _setTall(tester);
      await a11yCases
          .firstWhere((c) => c.name.contains('the loss warning'))
          .pump(tester);
      final labels = _labels(tester);
      final start = labels.indexOf('Start game');
      expect(start, isNot(-1));
      expect(
        labels[start + 1],
        'Your current game will count as a loss.',
        reason: 'labels: the warning is read next, on its own',
      );
      handle.dispose();
    });

    testWidgets('the promise chips read their words, the ticks left out', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      _setTall(tester);
      await pumpUnderScope(tester, const AboutAppScreen());
      await settleCase(tester);
      final labels = _labels(tester);
      expect(appPromiseChips, isNotEmpty);
      for (final chip in appPromiseChips) {
        final spoken = chip[0] + chip.substring(1).toLowerCase();
        expect(
          labels,
          contains(spoken),
          reason: 'labels: the chip "$chip" reads "$spoken"',
        );
      }
      expect(
        labels.where((l) => l.contains('✓')),
        isEmpty,
        reason: 'labels: no tick is read',
      );
      handle.dispose();
    });
  });

  group('headings', () {
    Future<List<(int, String)>> headersOf(
      WidgetTester tester,
      String name,
    ) async {
      _setTall(tester);
      await a11yCases.firstWhere((c) => c.name == name).pump(tester);
      return _headers(tester);
    }

    testWidgets('Settings: its title, the board cards, then PLAY, DISPLAY and '
        'SOUND', (tester) async {
      final handle = tester.ensureSemantics();
      expect(await headersOf(tester, 'Settings, a game in progress'), [
        (1, 'Settings'),
        (2, 'Board colour'),
        (2, 'Piece style'),
        (2, 'Board surface'),
        (2, 'Play'),
        (2, 'Display'),
        (2, 'Sound'),
      ], reason: 'labels: Settings\' headings, in order');
      handle.dispose();
    });

    final expected = <String, List<(int, String)>>{
      'the menu': [(1, 'Honest Chess')],
      'the vs-computer setup, Custom, Keep playing and the loss warning': [
        (1, 'New game vs computer'),
        (2, 'Strength'),
        (2, 'Play as'),
        (2, 'Time control'),
      ],
      'the two-player setup, Custom': [
        (1, 'Two players'),
        (2, 'Time control'),
        (2, 'House rules'),
      ],
      'How to play, the rules': [
        (1, 'How to play'),
        (2, 'The goal'),
        (2, 'Check'),
        (2, 'Draws'),
        (2, 'The clock'),
        (2, 'Takeback'),
        (2, 'Gestures'),
      ],
      'About the app': [
        (1, 'About the App'),
        (2, 'What\'s in it'),
        (2, 'The Honest promises'),
      ],
      'About Honest Arcade': [(1, 'About Honest Arcade'), (2, 'Our promises')],
      'Statistics, computer': [(1, 'Statistics'), (2, 'By strength')],
      'Statistics, its reset card': [(2, 'Reset statistics?')],
      'the board, you to move': [],
      'the board, its pause card': [(2, 'Paused')],
      'the board, its promotion card': [(2, 'Promote pawn on E8')],
      'the board, its result card': [(2, 'White wins, Black ran out of time')],
    };
    for (final MapEntry(key: name, value: headers) in expected.entries) {
      testWidgets('$name: titles level 1, section kickers level 2', (
        tester,
      ) async {
        final handle = tester.ensureSemantics();
        expect(
          await headersOf(tester, name),
          headers,
          reason: 'labels: $name\'s headings, in order',
        );
        handle.dispose();
      });
    }

    testWidgets('a mono sub-title under a title is not a heading', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await headersOf(
        tester,
        'the vs-computer setup, Custom, Keep playing and the loss warning',
      );
      final kicker = _byLabel(tester, 'Runs on device, no network');
      expect(
        kicker.flagsCollection.isHeader,
        isFalse,
        reason: 'labels: the sub-title line is read, not a heading',
      );
      handle.dispose();
    });
  });
}
