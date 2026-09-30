// Large text (#101): the phone's text size, clamped to 1.0–1.3× at the app
// root, reaches every screen. On a 360 × 640 dp phone and on the smallest
// the app supports, 320 × 568 dp, at 1.3× — and at 2.0×, which must render
// exactly as 1.3× — no screen overflows or cuts text short (the panel names
// alone may ellipsize) or breaks a word across lines (#176); below 1.0×
// nothing shrinks; the board's coordinates, its pieces and the clocks'
// digits keep their size at every scale; and the game screen fits without
// scrolling, its board giving up the room the grown panels take.
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:honest_chess/data/app_loader.dart';
import 'package:honest_chess/data/app_store.dart';
import 'package:honest_chess/data/game_saves.dart';
import 'package:honest_chess/data/play_mode.dart';
import 'package:honest_chess/data/settings_store.dart';
import 'package:honest_chess/data/stats.dart';
import 'package:honest_chess/engine/engine.dart';
import 'package:honest_chess/ui/board/board_options.dart';
import 'package:honest_chess/ui/board/board_view.dart' show BoardView;
import 'package:honest_chess/ui/board/promotion_sheet.dart';
import 'package:honest_chess/ui/game/defaults.dart';
import 'package:honest_chess/ui/game/game_controller.dart';
import 'package:honest_chess/ui/game/game_screen.dart';
import 'package:honest_chess/ui/game/tool_row.dart' show ToolRow;
import 'package:honest_chess/ui/screens/about_app_screen.dart';
import 'package:honest_chess/ui/screens/about_arcade_screen.dart';
import 'package:honest_chess/ui/screens/computer_setup_screen.dart';
import 'package:honest_chess/ui/screens/how_to_play_screen.dart';
import 'package:honest_chess/ui/screens/menu_screen.dart';
import 'package:honest_chess/ui/screens/settings_screen.dart';
import 'package:honest_chess/ui/screens/splash_screen.dart';
import 'package:honest_chess/ui/screens/stats_screen.dart';
import 'package:honest_chess/ui/screens/two_player_setup_screen.dart';

import '../support/app_harness.dart';
import 'game/fake_computer.dart';

/// A small phone: 360 × 640 dp, a 24 dp status bar and a 48 dp gesture bar.
const _phone = Size(360, 640);

/// The smallest phone the app supports, with the same bars.
const _smallest = Size(320, 568);

/// The phones every case is swept on.
const _phones = [_phone, _smallest];

String _named(Size size) => '${size.width.round()} × ${size.height.round()}';
const _insets = FakeViewPadding(top: 24, bottom: 48);

Finder _key(String key) => find.byKey(Key(key));

/// The keys of the only text allowed to ellipsize: the panels' names.
const _mayEllipsize = {'name-white', 'name-black'};

/// The longest step name, with a custom 90+60 clock: the widest names,
/// sub-lines and time labels the screens show.
const _worstStep = Strength.beginner;
final _worstClock = Timed(customMinutesMax, customIncrementMax);

/// Every counter in the thousands: the widest statistics.
StatsDocument get _fullStats => StatsDocument(
  computer: ComputerStats(
    played: 98765,
    won: 43210,
    drawn: 12345,
    lost: 43210,
    streak: 4321,
    longestMoves: 9876,
    steps: {
      for (final step in Strength.values)
        step: const StepStats(played: 19753, won: 8642),
    },
  ),
  two: TwoPlayerStats(
    played: 98765,
    whiteWins: 43210,
    blackWins: 43210,
    drawn: 12345,
    longestMoves: 9876,
    clocks: {for (final c in StatsClock.values) c: 19753},
  ),
);

/// One screen in one state, pumped from nothing at the scale the test set.
typedef _Case = ({String name, Future<void> Function(WidgetTester) pump});

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));
  await tester.pump();
}

Future<void> _screen(WidgetTester tester, Widget screen) async {
  await pumpUnderScope(tester, screen);
  await _settle(tester);
}

/// The settings store with the worst-case setup choices.
SettingsStore _worstSettings() {
  final settings = SettingsStore();
  settings.updateSetup(
    (c) => c.copyWith(
      computer: c.computer.copyWith(step: _worstStep, time: TimeChoice.custom),
      two: c.two.copyWith(time: TimeChoice.custom),
      custom: CustomTime(
        minutes: customMinutesMax,
        increment: customIncrementMax,
      ),
    ),
  );
  return settings;
}

/// A board of [controller]'s game under the harness, as the app shows it.
Future<GameController> _board(
  WidgetTester tester,
  GameController controller,
) async {
  addTearDown(controller.dispose);
  await pumpUnderScope(
    tester,
    GameScreen(options: const BoardOptions(), controller: controller),
    controller: controller,
  );
  await _settle(tester);
  return controller;
}

/// Against the computer at [_worstStep] on [_worstClock], you as Black, a
/// move in, so both clocks show and the computer's panel is lit.
GameController _worstGame({String? fen}) => GameController(
  fen: fen,
  mode: const VsComputer(playerColour: Colour.black, step: _worstStep, seed: 1),
  timeControl: _worstClock,
);

final _cases = <_Case>[
  (
    name: 'the menu, with Continue and the damaged-data banner',
    pump: (tester) async {
      final store = AppStore.memory();
      await seedSavedGame(store, Game.start(const TwoPlayer(), _worstClock));
      final saves = GameSaves(store);
      addTearDown(saves.dispose);
      await saves.loadAll();
      await pumpUnderScope(
        tester,
        const MenuScreen(),
        store: store,
        saves: saves,
      );
      store.corruptionNotices.value = {StoreDoc.settings};
      await _settle(tester);
      expect(_key('menu-banner'), findsOneWidget);
      expect(_key('menu-continue'), findsOneWidget);
    },
  ),
  (
    name: 'the vs-computer setup',
    pump: (tester) async {
      final settings = _worstSettings();
      addTearDown(settings.dispose);
      await pumpUnderScope(
        tester,
        const ComputerSetupScreen(),
        settings: settings,
      );
      await _settle(tester);
    },
  ),
  (
    name: 'the two-player setup',
    pump: (tester) async {
      final settings = _worstSettings();
      addTearDown(settings.dispose);
      await pumpUnderScope(
        tester,
        const TwoPlayerSetupScreen(),
        settings: settings,
      );
      await _settle(tester);
    },
  ),
  (
    name: 'Settings, with a game in progress',
    pump: (tester) async {
      final controller = _worstGame();
      addTearDown(controller.dispose);
      await pumpUnderScope(
        tester,
        const SettingsScreen(),
        controller: controller,
      );
      await _settle(tester);
    },
  ),
  (
    name: 'How to play, the pieces',
    pump: (tester) => _screen(tester, const HowToPlayScreen()),
  ),
  (
    name: 'How to play, the rules',
    pump: (tester) =>
        _screen(tester, const HowToPlayScreen(initialTab: HowToTab.rules)),
  ),
  (
    name: 'About the app',
    pump: (tester) => _screen(tester, const AboutAppScreen()),
  ),
  (
    name: 'About Honest Arcade',
    pump: (tester) => _screen(tester, const AboutArcadeScreen()),
  ),
  for (final mode in PlayMode.values)
    (
      name: 'Statistics, ${mode.name}',
      pump: (tester) async {
        final store = AppStore.memory();
        await store.write(StoreDoc.stats, _fullStats.toJson());
        final stats = StatsRecorder(store: store);
        addTearDown(stats.dispose);
        await stats.load();
        await pumpUnderScope(
          tester,
          StatsScreen(openOn: mode),
          store: store,
          stats: stats,
        );
        await _settle(tester);
      },
    ),
  (
    name: 'Statistics, its reset card',
    pump: (tester) async {
      await pumpUnderScope(tester, const StatsScreen());
      await _settle(tester);
      final reset = _key('stats-reset');
      await tester.scrollUntilVisible(
        reset,
        100,
        scrollable: find.descendant(
          of: _key('stats-scroll'),
          matching: find.byType(Scrollable),
        ),
      );
      // Clear of the bottom inset.
      await Scrollable.ensureVisible(tester.element(reset), alignment: .5);
      await tester.pump();
      await tester.tap(reset);
      await _settle(tester);
      expect(_key('stats-reset-card'), findsOneWidget);
    },
  ),
  (
    name: 'the splash',
    pump: (tester) async {
      final store = AppStore.memory();
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
      await pumpUnderScope(tester, SplashScreen(loader: loader));
      await tester.pump(const Duration(milliseconds: 200));
      expect(_key('splash-label'), findsOneWidget);
    },
  ),
  (
    name: 'the board',
    pump: (tester) async {
      final c = await _board(tester, _worstGame());
      expect(c.game.mode, isA<VsComputer>());
    },
  ),
  (
    name: 'the board, two players',
    pump: (tester) async {
      await _board(
        tester,
        GameController(mode: const TwoPlayer(), timeControl: _worstClock),
      );
    },
  ),
  (
    name: 'the board, its pause card',
    pump: (tester) async {
      await _board(tester, _worstGame());
      await tester.tap(_key('pause-pill'));
      await _settle(tester);
      expect(_key('pause-card'), findsOneWidget);
    },
  ),
  (
    name: 'the board, its declined-draw card',
    pump: (tester) async {
      final fakes = FakeComputers();
      final c = await _board(
        tester,
        GameController(
          mode: const VsComputer(
            playerColour: Colour.white,
            step: _worstStep,
            seed: 1,
          ),
          timeControl: _worstClock,
          computer: fakes.call,
        ),
      );
      c.move(Square.parse('e2'), Square.parse('e4'));
      await tester.pump();
      fakes.current.last.move('e7e5');
      await _settle(tester);
      expect(c.pause(), isTrue);
      final offer = c.offerDraw();
      await tester.pump();
      fakes.current.draws.single.decline();
      await offer;
      await _settle(tester);
      expect(_key('declined-card'), findsOneWidget);
    },
  ),
  (
    name: 'the board in check',
    pump: (tester) async {
      final c = await _board(
        tester,
        GameController(
          fen: 'k7/8/8/8/8/8/8/K6r w - - 0 1',
          timeControl: _worstClock,
        ),
      );
      expect(c.state.inCheck, isNotNull);
    },
  ),
  (
    name: 'the board, its promotion card',
    pump: (tester) async {
      final c = await _board(
        tester,
        GameController(
          fen: '3r3k/4P3/8/8/8/8/8/K7 w - - 0 1',
          timeControl: _worstClock,
        ),
      );
      c.move(Square.parse('e7'), Square.parse('e8'));
      await tester.pump();
      await tester.pump(promotionEnterDuration);
      await tester.pump();
      expect(_key('promo-card'), findsOneWidget);
    },
  ),
  (
    name: 'the board, the computer could not move',
    pump: (tester) async {
      final fakes = FakeComputers();
      final c = GameController(
        mode: const VsComputer(
          playerColour: Colour.black,
          step: _worstStep,
          seed: 1,
        ),
        timeControl: _worstClock,
        computer: fakes.call,
      );
      await _board(tester, c);
      // It fails, and fails again on its one retry.
      fakes.current.last.fail();
      await tester.pump();
      fakes.current.last.fail();
      await _settle(tester);
      expect(c.state.computerFailed, isTrue);
    },
  ),
  for (final bar in [false, true])
    (
      name: bar ? 'the board, its result bar' : 'the board, its result card',
      pump: (tester) async {
        // A lone white king against a queen: Black's flag falls with
        // White unable to mate, the longest result title.
        var now = 0;
        final c = await _board(
          tester,
          GameController(
            fen: 'kq6/8/8/8/8/8/8/K7 w - - 0 1',
            timeControl: _worstClock,
            now: () => now,
          ),
        );
        c.move(Square.parse('a1'), Square.parse('a2'));
        now += _worstClock.initialMs + 1;
        c.checkFlag();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 1500));
        expect(_key('result-card'), findsOneWidget);
        if (bar) {
          // On the shortest screen at the largest text the card scrolls.
          await tester.ensureVisible(_key('result-view-board'));
          await tester.pump();
          await tester.tap(_key('result-view-board'));
          await _settle(tester);
          expect(_key('result-bar'), findsOneWidget);
        }
      },
    ),
];

/// One paragraph as drawn: its text, its rendered height, whether it ran
/// past its line limit and whether it is one allowed to, and whether its
/// lines are taller than the box it was given, so the box clips them.
typedef _Paragraph = ({
  String text,
  double height,
  bool exceeded,
  bool mayEllipsize,
  bool clipped,
  Set<String> split,
});

/// A word: letters and digits, with any apostrophes inside it.
final _word = RegExp(r"[\p{L}\p{N}]+(?:['’][\p{L}\p{N}]+)*", unicode: true);

/// How far apart two boxes' tops may be and still be on one line.
const _lineTolerance = 1.0;

/// The top of the line [render] draws the character at [index] on, or null
/// when it draws none (a character past an ellipsis).
double? _lineTop(RenderParagraph render, int index) {
  final boxes = render.getBoxesForSelection(
    TextSelection(baseOffset: index, extentOffset: index + 1),
  );
  return boxes.isEmpty ? null : boxes.first.top;
}

bool _sameLine(double? a, double? b) =>
    a != null && b != null && (a - b).abs() <= _lineTolerance;

/// Each word [render] breaks across lines.
Set<String> _splitIn(RenderParagraph render, String text) => {
  for (final m in _word.allMatches(text))
    if (m.end - m.start > 1 &&
        !_sameLine(_lineTop(render, m.start), _lineTop(render, m.end - 1)))
      'the word "${m[0]}" broken across lines in "$text"',
};

/// Whether [p] is cut short: past its line limit when it may not ellipsize,
/// or clipped by its box, which no text may be.
bool _isCut(_Paragraph p) => (p.exceeded && !p.mayEllipsize) || p.clipped;

/// How far a paragraph's lines may run past its box before they count as
/// clipped: rounding, not a cut.
const _clipTolerance = .01;

List<_Paragraph> _paragraphs(WidgetTester tester) {
  final out = <_Paragraph>[];
  for (final element in find.byType(RichText).evaluate()) {
    final render = element.renderObject;
    if (render is! RenderParagraph || !render.attached) continue;
    var mayEllipsize = false;
    element.visitAncestorElements((a) {
      final key = a.widget.key;
      if (key is ValueKey<String> && _mayEllipsize.contains(key.value)) {
        mayEllipsize = true;
        return false;
      }
      return true;
    });
    final text = render.text.toPlainText();
    out.add((
      text: text,
      height: render.size.height,
      exceeded: render.didExceedMaxLines,
      mayEllipsize: mayEllipsize,
      clipped: render.textSize.height - render.size.height > _clipTolerance,
      split: _splitIn(render, text),
    ));
  }
  return out;
}

/// Every error the frames reported, drained.
List<Object> _errors(WidgetTester tester) => [
  for (var e = tester.takeException(); e != null; e = tester.takeException()) e,
];

/// What one pump of a case showed: the paragraphs of its first frame, and
/// every overflow, cut-short text and word broken across lines found while
/// scrolling each vertical scrollable to its end.
typedef _Seen = ({
  List<_Paragraph> first,
  List<Object> errors,
  Set<String> cut,
  Set<String> split,
});

/// Every word broken across lines in [paragraphs].
Set<String> _splits(WidgetTester tester, List<_Paragraph> paragraphs) => {
  for (final p in paragraphs)
    if (!p.mayEllipsize && !p.exceeded) ...p.split,
};

void _setPhone(WidgetTester tester, double scale, [Size phone = _phone]) {
  tester.view.physicalSize = phone;
  tester.view.devicePixelRatio = 1;
  tester.view.padding = _insets;
  tester.view.viewPadding = _insets;
  tester.platformDispatcher.textScaleFactorTestValue = scale;
}

Future<_Seen> _pumpAt(
  WidgetTester tester,
  _Case c,
  double scale, [
  Size phone = _phone,
]) async {
  await tester.pumpWidget(const SizedBox());
  _setPhone(tester, scale, phone);
  await c.pump(tester);
  final errors = _errors(tester);
  final first = _paragraphs(tester);
  final cut = {
    for (final p in first)
      if (_isCut(p)) p.text,
  };
  final split = _splits(tester, first);
  final scrollables = find.byType(Scrollable);
  for (var i = 0; i < scrollables.evaluate().length; i++) {
    final state = tester.state<ScrollableState>(scrollables.at(i));
    if (state.position.axis != Axis.vertical) continue;
    while (state.position.pixels < state.position.maxScrollExtent) {
      state.position.jumpTo(
        (state.position.pixels + 200).clamp(0, state.position.maxScrollExtent),
      );
      await tester.pump();
      errors.addAll(_errors(tester));
      final paragraphs = _paragraphs(tester);
      cut.addAll([
        for (final p in paragraphs)
          if (_isCut(p)) p.text,
      ]);
      split.addAll(_splits(tester, paragraphs));
    }
  }
  return (first: first, errors: errors, cut: cut, split: split);
}

/// The sizes a pump drew, text by text, for comparing two scales.
List<(String, double)> _sizes(_Seen seen) => [
  for (final p in seen.first) (p.text, p.height),
];

void main() {
  for (final phone in _phones) {
    group('at ${_named(phone)}', () => _sweep(phone));
  }

  fixedAndFitted();
}

/// Every case on [phone].
void _sweep(Size phone) {
  final at = _named(phone);
  for (final c in _cases) {
    testWidgets('${c.name}: fits at 1.3×, and 2.0× draws as 1.3×', (
      tester,
    ) async {
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final at13 = await _pumpAt(tester, c, 1.3, phone);
      expect(
        MediaQuery.textScalerOf(tester.element(find.byType(Navigator)))
            .scale(10),
        closeTo(13, 1e-9),
        reason: 'large text: the root clamp lets 1.3× through',
      );
      expect(
        at13.errors,
        isEmpty,
        reason: 'large text: ${c.name} overflows at 1.3×: ${at13.errors}',
      );
      expect(
        at13.cut,
        isEmpty,
        reason: 'large text: ${c.name} cuts text short at 1.3×',
      );
      expect(
        at13.split,
        isEmpty,
        reason:
            'large text: ${c.name} breaks a word across lines at '
            '1.3× on $at',
      );
      final at20 = await _pumpAt(tester, c, 2, phone);
      expect(
        at20.errors,
        isEmpty,
        reason: 'large text: ${c.name} overflows at 2.0×: ${at20.errors}',
      );
      expect(
        _sizes(at20),
        _sizes(at13),
        reason: 'large text: at 2.0× ${c.name} draws as at 1.3× (the cap)',
      );
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('${c.name}: nothing shrinks below the design at 0.85×', (
      tester,
    ) async {
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final at10 = await _pumpAt(tester, c, 1, phone);
      expect(at10.errors, isEmpty, reason: 'large text: ${c.name} at 1.0×');
      expect(
        at10.cut,
        isEmpty,
        reason: 'large text: ${c.name} cuts text short at 1.0×',
      );
      expect(
        at10.split,
        isEmpty,
        reason:
            'large text: ${c.name} breaks a word across lines at '
            '1.0× on $at',
      );
      final at085 = await _pumpAt(tester, c, .85, phone);
      expect(
        _sizes(at085),
        _sizes(at10),
        reason: 'large text: at 0.85× ${c.name} draws as at 1.0× (the floor)',
      );
      await tester.pumpWidget(const SizedBox());
    });
  }
}

/// The rendered height of the paragraph under the first widget whose key
/// starts with [prefix].
double _textHeight(WidgetTester tester, String prefix) {
  final keyed = find.byWidgetPredicate((w) {
    final key = w.key;
    return key is ValueKey<String> && key.value.startsWith(prefix);
  });
  final paragraph = find.descendant(
    of: keyed.first,
    matching: find.byType(RichText),
  );
  return tester.renderObject<RenderParagraph>(paragraph.first).size.height;
}

void fixedAndFitted() {
  testWidgets('the board, its labels, its pieces and the clocks keep their '
      'size at 1.3× while the panels grow', (tester) async {
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    // A tall phone, where the board is as wide as the screen at both
    // scales, so only the text scale differs.
    Future<Map<String, double>> measure(double scale) async {
      await tester.pumpWidget(const SizedBox());
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      await _board(tester, _worstGame());
      return {
        'board': tester.getSize(find.byType(BoardView)).height,
        for (final key in [
          'rank-',
          'file-',
          'clock-white',
          'clock-black',
          'name-white',
          'sub-white',
        ])
          key: _textHeight(tester, key),
        'piece': _textHeight(tester, 'piece-'),
      };
    }

    final at10 = await measure(1);
    final at13 = await measure(1.3);
    expect(
      at13['board'],
      at10['board'],
      reason: 'large text: on a tall phone the board keeps its size',
    );
    for (final key in ['rank-', 'file-', 'clock-white', 'clock-black']) {
      expect(
        at13[key],
        at10[key],
        reason: 'large text: $key keeps its size at 1.3×',
      );
    }
    expect(
      at13['piece'],
      at10['piece'],
      reason: 'large text: the pieces keep their size at 1.3×',
    );
    for (final key in ['name-white', 'sub-white']) {
      expect(
        at13[key]!,
        greaterThan(at10[key]!),
        reason: 'large text: the panel text $key grows at 1.3×',
      );
    }
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('on a small phone the board shrinks just enough, and the game '
      'screen never scrolls', (tester) async {
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    Future<
      ({double board, double toolsTop, double toolsBottom, double panelBottom})
    >
    measure(double scale) async {
      await tester.pumpWidget(const SizedBox());
      _setPhone(tester, scale);
      await _board(tester, _worstGame());
      expect(
        find.descendant(
          of: find.byType(GameScreen),
          matching: find.byType(Scrollable),
        ),
        findsNothing,
        reason: 'large text: the game screen never scrolls',
      );
      return (
        board: tester.getSize(find.byType(BoardView)).height,
        toolsTop: tester.getTopLeft(find.byType(ToolRow)).dy,
        toolsBottom: tester.getBottomLeft(find.byType(ToolRow)).dy,
        panelBottom: tester.getBottomLeft(_key('panel-black')).dy,
      );
    }

    final at10 = await measure(1);
    final at13 = await measure(1.3);
    final safeBottom = _phone.height - _insets.bottom;
    expect(
      at13.toolsBottom,
      lessThanOrEqualTo(safeBottom),
      reason: 'large text: at 1.3× the tool row is on screen',
    );
    expect(
      at13.board,
      lessThan(at10.board),
      reason: 'large text: at 1.3× the board gives up room to the panels',
    );
    // Just enough: the tool row ends at the safe area's edge, and the gap
    // above it is at its least, so the board took no more than the grown
    // panels and tool row needed.
    expect(
      at13.toolsBottom,
      closeTo(safeBottom, 1e-6),
      reason: 'large text: at 1.3× the board shrinks only as far as needed',
    );
    expect(
      at13.toolsTop - at13.panelBottom,
      closeTo(minBoardGap, 1e-6),
      reason: 'large text: at 1.3× the gaps give way before the board',
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the sweep catches an overflow, text cut short, text '
      'clipped by its box and a broken word', (tester) async {
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final overflowing = (
      name: 'a fixed row too short for its text',
      pump: (WidgetTester tester) => _screen(
        tester,
        const Scaffold(
          body: SizedBox(
            height: 20,
            child: Column(
              children: [Text('Grows', style: TextStyle(fontSize: 18))],
            ),
          ),
        ),
      ),
    );
    final cut = (
      name: 'a one-line label too narrow',
      pump: (WidgetTester tester) => _screen(
        tester,
        const Scaffold(
          body: SizedBox(
            width: 60,
            child: Text(
              'A label that cannot fit',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      ),
    );
    final clipped = (
      name: 'a fixed-height box shorter than its scaled line',
      pump: (WidgetTester tester) => _screen(
        tester,
        const Scaffold(
          body: SizedBox(
            height: 17,
            child: Center(
              child: Text('Clipped', style: TextStyle(fontSize: 17)),
            ),
          ),
        ),
      ),
    );
    final broken = (
      name: 'a word wider than its box',
      pump: (WidgetTester tester) => _screen(
        tester,
        const Scaffold(body: SizedBox(width: 40, child: Text('Random'))),
      ),
    );
    final seenOverflow = await _pumpAt(tester, overflowing, 1.3);
    expect(
      seenOverflow.errors,
      isNotEmpty,
      reason: 'large text: the sweep reports an overflow',
    );
    final seenCut = await _pumpAt(tester, cut, 1.3);
    expect(seenCut.cut, {
      'A label that cannot fit',
    }, reason: 'large text: the sweep reports text cut short');
    final seenClipped = await _pumpAt(tester, clipped, 1.3);
    expect(seenClipped.errors, isEmpty);
    expect(seenClipped.cut, {
      'Clipped',
    }, reason: 'large text: the sweep reports text its box clips');
    final seenBroken = await _pumpAt(tester, broken, 1.3);
    expect(seenBroken.split, {
      'the word "Random" broken across lines in "Random"',
    }, reason: 'large text: the sweep reports a word broken across lines');
    await tester.pumpWidget(const SizedBox());
  });
}
