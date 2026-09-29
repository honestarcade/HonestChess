import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:honest_chess/data/app_store.dart';
import 'package:honest_chess/data/settings_store.dart';
import 'package:honest_chess/engine/engine.dart';
import 'package:honest_chess/feedback/clips.dart';
import 'package:honest_chess/platform/platform_channel.dart';
import 'package:honest_chess/ui/board/board_options.dart';
import 'package:honest_chess/ui/game/defaults.dart';
import 'package:honest_chess/ui/game/game_controller.dart';
import 'package:honest_chess/ui/screens/settings_screen.dart';
import 'package:honest_chess/ui/theme/palette.dart';
import 'package:honest_chess/ui/widgets/setting_row.dart';
import 'package:honest_chess/ui/widgets/toggle_switch.dart';

import '../support/app_harness.dart';
import 'game/fake_computer.dart';

/// Each row as the design writes it, with the field it switches.
final _rows =
    <
      ({
        String key,
        String label,
        String description,
        bool Function(BoardOptions) read,
      })
    >[
      (
        key: 'settings-toggle-dots',
        label: 'Legal-move dots',
        description: 'Mark every square the selected piece can reach.',
        read: (o) => o.legalMoveDots,
      ),
      (
        key: 'settings-toggle-last-move',
        label: 'Last-move highlight',
        description: 'Tint the two squares of the move just played.',
        read: (o) => o.lastMoveHighlight,
      ),
      (
        key: 'settings-toggle-takeback',
        label: 'Takeback allowed',
        description: 'Undo the last move — both yours and the reply.',
        read: (o) => o.takebackAllowed,
      ),
      (
        key: 'settings-toggle-auto-queen',
        label: 'Auto-promote to queen',
        description: 'Skip the promotion sheet and take a queen.',
        read: (o) => o.autoQueen,
      ),
      (
        key: 'settings-toggle-rotate',
        label: 'Rotate board each turn',
        description: 'Two-player only. Faces the board at whoever moves.',
        read: (o) => o.rotateEachTurn,
      ),
      (
        key: 'settings-toggle-check-flag',
        label: 'Flag check on the board',
        description: 'Redden the king square whenever it is in check.',
        read: (o) => o.flagCheck,
      ),
      (
        key: 'settings-toggle-sfx',
        label: 'Sound effects',
        description: 'Moves, captures, castling, check and the end of a game.',
        read: (o) => o.sfx,
      ),
      (
        key: 'settings-toggle-music',
        label: 'Background music',
        description: 'Quiet loop while you play.',
        read: (o) => o.music,
      ),
    ];

const _untimedTwo = (
  mode: GameKind.twoPlayers,
  strength: null,
  colour: null,
  timeControl: Untimed(),
);

void _tallView(WidgetTester tester) {
  tester.view.physicalSize = const Size(390, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

/// Settings alone under the harness, over [store] with its settings loaded.
Future<AppHarness> _pumpSettings(
  WidgetTester tester, {
  AppStore? store,
  FakePlatformChannel? platform,
  GameController? controller,
}) async {
  _tallView(tester);
  final theStore = store ?? AppStore.memory();
  final settings = SettingsStore();
  addTearDown(settings.dispose);
  await settings.load(theStore);
  final harness = await pumpUnderScope(
    tester,
    const SettingsScreen(),
    store: theStore,
    platform: platform,
    controller: controller,
    settings: settings,
  );
  await tester.pump();
  return harness;
}

Future<void> _toggle(WidgetTester tester, String key) async {
  await tester.ensureVisible(find.byKey(Key(key)));
  await tester.tap(find.byKey(Key(key)));
  await tester.pump();
}

String _description(WidgetTester tester, String key) =>
    tester.widget<SettingRow>(find.byKey(Key(key))).description;

Future<BoardOptions> _saved(AppStore store) async {
  await store.flush();
  return decodeBoard(
    (await store.read(StoreDoc.settings) as Loaded).data['board'],
  );
}

String _version(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(const Key('settings-version'))).data!;

/// An untimed two-player game's board, with Settings pushed over it.
Future<AppHarness> _boardAndSettings(WidgetTester tester) async {
  _tallView(tester);
  final harness = await pumpBoard(
    tester,
    setup: _untimedTwo,
    computerFactory: FakeComputers().call,
  );
  await _openSettings(tester);
  return harness;
}

Future<void> _openSettings(WidgetTester tester) async {
  Navigator.of(tester.element(find.byKey(const Key('board'))))
      .push(MaterialPageRoute<void>(builder: (_) => const SettingsScreen()));
  await tester.pumpAndSettle();
}

Future<void> _back(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('settings-back')));
  await tester.pumpAndSettle();
}

void _move(GameController c, String uci) => expect(
  c.move(Square.parse(uci.substring(0, 2)), Square.parse(uci.substring(2))),
  isTrue,
  reason: 'test: $uci is playable',
);

void main() {
  testWidgets(
    'the PLAY, DISPLAY and SOUND rows read as the design writes them',
    (tester) async {
      await _pumpSettings(tester);
      for (final kicker in ['PLAY', 'DISPLAY', 'SOUND']) {
        expect(find.text(kicker), findsOneWidget, reason: 'settings: $kicker');
      }
      const defaults = BoardOptions();
      for (final row in _rows) {
        final widget = tester.widget<SettingRow>(find.byKey(Key(row.key)));
        expect(
          (widget.label, widget.description, widget.value),
          (row.label, row.description, row.read(defaults)),
          reason: 'settings-options: ${row.key} reads as the design',
        );
        expect(
          tester.getSemantics(find.byKey(Key(row.key))),
          isSemantics(
            label: '${row.label}, ${row.description}',
            hasToggledState: true,
            isToggled: row.read(defaults),
            hasTapAction: true,
          ),
          reason: 'settings-options: ${row.key} is one toggled node',
        );
      }
      expect(
        tester.getTopLeft(find.text('Flag check on the board')).dy,
        greaterThan(tester.getTopLeft(find.text('DISPLAY')).dy),
        reason: 'settings-options: check flag sits under DISPLAY',
      );
      expect(
        tester.getTopLeft(find.text('Sound effects')).dy,
        greaterThan(tester.getTopLeft(find.text('SOUND')).dy),
        reason: 'settings-options: the sound rows sit under SOUND',
      );
      expect(
        tester.getTopLeft(find.text('SOUND')).dy,
        greaterThan(tester.getTopLeft(find.text('Flag check on the board')).dy),
        reason: 'settings-options: SOUND comes after DISPLAY',
      );
      for (final hidden in ['Piece animations', 'Haptics']) {
        expect(
          find.textContaining(hidden),
          findsNothing,
          reason: 'settings-options: "$hidden" is not built yet',
        );
      }
    },
  );

  testWidgets('each toggle flips its field, draws it and keeps it', (
    tester,
  ) async {
    final store = AppStore.memory();
    final harness = await _pumpSettings(tester, store: store);
    var expected = const BoardOptions();
    for (final row in _rows) {
      final before = row.read(expected);
      await _toggle(tester, row.key);
      final now = harness.settings.board.value;
      expect(
        row.read(now),
        !before,
        reason: 'settings-options: ${row.key} flips its field',
      );
      expected = now;
      await tester.pump(ToggleSwitch.slideDuration);
      final track = find.descendant(
        of: find.byKey(Key(row.key)),
        matching: find.byType(ToggleSwitch),
      );
      expect(tester.widget<ToggleSwitch>(track).value, !before);
      expect(
        tester
                .getTopLeft(
                  find.descendant(
                    of: track,
                    matching: find.byKey(ToggleSwitch.knobKey),
                  ),
                )
                .dx -
            tester.getTopLeft(track).dx,
        !before ? ToggleSwitch.knobOn : ToggleSwitch.knobOff,
        reason: 'settings-options: ${row.key}\'s knob follows the value',
      );
      expect(
        await _saved(store),
        now,
        reason: 'settings-options: ${row.key} is saved at once',
      );
    }
    // Only its own field moved each time: the whole walk flipped them all.
    expect(
      harness.settings.board.value,
      const BoardOptions(
        legalMoveDots: false,
        lastMoveHighlight: false,
        takebackAllowed: false,
        autoQueen: true,
        rotateEachTurn: true,
        flagCheck: false,
        sfx: false,
        music: true,
      ),
      reason: 'settings-options: the toggles touch nothing else',
    );
  });

  testWidgets('turning Sound effects on plays one sample move; nothing else '
      'does', (tester) async {
    final store = AppStore.memory(
      documents: {
        StoreDoc.settings: {
          'board': encodeBoard(const BoardOptions(sfx: true, music: true)),
        },
      },
    );
    final harness = await _pumpSettings(tester, store: store);
    expect(
      harness.sound.played,
      isEmpty,
      reason: 'settings-sound: the launch restore plays no sample',
    );
    await _toggle(tester, 'settings-toggle-sfx');
    expect(harness.settings.board.value.sfx, isFalse);
    expect(
      harness.sound.played,
      isEmpty,
      reason: 'settings-sound: turning effects off plays nothing',
    );
    await _toggle(tester, 'settings-toggle-sfx');
    expect(harness.settings.board.value.sfx, isTrue);
    expect(harness.sound.played, [
      Clip.move,
    ], reason: 'settings-sound: turning effects on plays one sample move');
    await _toggle(tester, 'settings-toggle-music');
    await _toggle(tester, 'settings-toggle-music');
    await _toggle(tester, 'settings-toggle-dots');
    expect(harness.sound.played, [
      Clip.move,
    ], reason: 'settings-sound: no other switch plays the sample');
    expect(await _saved(store), harness.settings.board.value);
  });

  testWidgets('every tap counts, even mid-slide', (tester) async {
    final store = AppStore.memory();
    final harness = await _pumpSettings(tester, store: store);
    const key = Key('settings-toggle-dots');
    await tester.tap(find.byKey(key));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.byKey(key));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.byKey(key));
    await tester.pumpAndSettle();
    expect(
      harness.settings.board.value.legalMoveDots,
      isFalse,
      reason: 'settings-options: three taps leave dots off',
    );
    expect((await _saved(store)).legalMoveDots, isFalse);
    // A tap on the drawn switch is one tap, not two.
    await tester.tap(
      find.descendant(of: find.byKey(key), matching: find.byType(ToggleSwitch)),
    );
    await tester.pumpAndSettle();
    expect(
      harness.settings.board.value.legalMoveDots,
      isTrue,
      reason: 'settings-options: a tap on the switch toggles once',
    );
  });

  testWidgets('the switch jumps when animations are off', (tester) async {
    final settings = SettingsStore();
    addTearDown(settings.dispose);
    _tallView(tester);
    await pumpUnderScope(
      tester,
      const MediaQuery(
        data: MediaQueryData(disableAnimations: true),
        child: SettingsScreen(),
      ),
      settings: settings,
    );
    await tester.pump();
    await _toggle(tester, 'settings-toggle-auto-queen');
    expect(
      tester.binding.transientCallbackCount,
      0,
      reason: 'settings-options: no slide with animations off',
    );
    final track = find.descendant(
      of: find.byKey(const Key('settings-toggle-auto-queen')),
      matching: find.byType(ToggleSwitch),
    );
    expect(
      tester
              .getTopLeft(
                find.descendant(
                  of: track,
                  matching: find.byKey(ToggleSwitch.knobKey),
                ),
              )
              .dx -
          tester.getTopLeft(track).dx,
      ToggleSwitch.knobOn,
    );
  });

  testWidgets('with dots off a selected piece shows no dot; on, it does', (
    tester,
  ) async {
    final root = await _boardAndSettings(tester);
    await _back(tester);
    await tester.tap(find.byKey(const Key('cell-e2')));
    await tester.pump();
    expect(find.byKey(const Key('selected-e2')), findsOneWidget);
    expect(find.byKey(const Key('dot-e4')), findsOneWidget);

    await _openSettings(tester);
    await _toggle(tester, 'settings-toggle-dots');
    expect(root.controller.options.legalMoveDots, isFalse);
    await _back(tester);
    expect(find.byKey(const Key('selected-e2')), findsOneWidget);
    expect(
      find.byKey(const Key('dot-e4')),
      findsNothing,
      reason: 'settings-options: dots off draws no dot at once',
    );

    await _openSettings(tester);
    await _toggle(tester, 'settings-toggle-dots');
    await _back(tester);
    expect(
      find.byKey(const Key('dot-e4')),
      findsOneWidget,
      reason: 'settings-options: dots on draws the dot again',
    );
  });

  testWidgets('check flag and last move apply at once', (tester) async {
    final root = await _boardAndSettings(tester);
    final c = root.controller;
    for (final uci in ['f2f3', 'e7e5', 'g2g4', 'd8h4']) {
      _move(c, uci);
    }
    await tester.pump();
    expect(c.state.tintAt(Square.parse('e1')), SquareTint.check);
    await _toggle(tester, 'settings-toggle-check-flag');
    expect(
      c.state.tintAt(Square.parse('e1')),
      SquareTint.none,
      reason: 'settings-options: flag check off clears the king\'s tint',
    );
    expect(c.state.tintAt(Square.parse('h4')), SquareTint.lastMove);
    await _toggle(tester, 'settings-toggle-last-move');
    expect(
      c.state.tintAt(Square.parse('h4')),
      SquareTint.none,
      reason: 'settings-options: last move off clears its tint',
    );
  });

  testWidgets('takeback off applies from the next game, and back on too', (
    tester,
  ) async {
    final root = await _boardAndSettings(tester);
    final c = root.controller;
    const row = 'settings-toggle-takeback';
    expect(
      _description(tester, row),
      takebackNextGame,
      reason: 'settings-options: mid-game, takeback says when it applies',
    );

    await _toggle(tester, row);
    expect(root.settings.board.value.takebackAllowed, isFalse);
    _move(c, 'e2e4');
    expect(
      c.takeBack(),
      isTrue,
      reason: 'settings-options: this game keeps takeback',
    );

    expect(await c.newGame(_untimedTwo), isTrue);
    await tester.pump();
    _move(c, 'e2e4');
    expect(
      c.takeBack(),
      isFalse,
      reason: 'settings-options: the next game has no takeback',
    );

    await _toggle(tester, row);
    expect(
      c.takeBack(),
      isFalse,
      reason: 'settings-options: turning it back on waits too',
    );
    expect(await c.restart(), isTrue);
    await tester.pump();
    _move(c, 'e2e4');
    expect(
      c.takeBack(),
      isTrue,
      reason: 'settings-options: a restart reads the switch afresh',
    );
    await _back(tester);
  });

  testWidgets('"Applies from your next game." shows only while a game is '
      'in progress', (tester) async {
    final controller = GameController.idle();
    addTearDown(controller.dispose);
    await _pumpSettings(tester, controller: controller);
    const row = 'settings-toggle-takeback';
    final design = _rows[2].description;
    expect(
      _description(tester, row),
      design,
      reason: 'settings-options: no game, the design\'s description',
    );
    expect(find.text(takebackNextGame), findsNothing);

    await controller.newGame(_untimedTwo);
    await tester.pump();
    expect(
      _description(tester, row),
      takebackNextGame,
      reason: 'settings-options: a live game shows when it applies',
    );
    expect(find.text(takebackNextGame), findsOneWidget);
    expect(
      tester.getSemantics(find.byKey(const Key(row))),
      isSemantics(label: 'Takeback allowed, $takebackNextGame'),
    );

    expect(controller.resign(), isTrue);
    await tester.pump();
    expect(
      _description(tester, row),
      design,
      reason: 'settings-options: an ended game is not in progress',
    );
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('the note says where the data lives, word for word', (
    tester,
  ) async {
    await _pumpSettings(tester);
    final note = find.byKey(const Key('settings-note'));
    await tester.ensureVisible(note);
    expect(
      find.descendant(of: note, matching: find.text('STORED ON THIS PHONE')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: note,
        matching: find.text(
          'Games, statistics and settings are kept on this phone. No '
          'account, no sync, no server — the app sends nothing anywhere.',
        ),
      ),
      findsOneWidget,
      reason: 'settings-options: the note\'s reworded text',
    );
    expect(find.textContaining('never leave'), findsNothing);
  });

  group('the version line', () {
    Future<void> show(
      WidgetTester tester,
      Future<AppVersion?> Function() answer,
    ) async {
      final platform = FakePlatformChannel()..onAppVersion = answer;
      await _pumpSettings(tester, platform: platform);
      await tester.pump();
    }

    testWidgets('reads the installed version in Plex Mono', (tester) async {
      await show(
        tester,
        () async => const AppVersion(name: '1.2.3', code: 1034),
      );
      expect(_version(tester), 'v1.2.3 · BUILD 1034');
      final style = tester
          .widget<Text>(find.byKey(const Key('settings-version')))
          .style!;
      expect(style.fontFamily, Fonts.plexMono);
      expect(style.color, Palette.textFaint);
      expect(
        tester.getSemantics(find.byKey(const Key('settings-version'))),
        isSemantics(label: 'v1.2.3 · BUILD 1034'),
      );
    });

    testWidgets('strips one leading v from the name', (tester) async {
      await show(
        tester,
        () async => const AppVersion(name: ' v0.1.0', code: 1),
      );
      expect(_version(tester), 'v0.1.0 · BUILD 1');
    });

    for (final (why, answer) in <(String, Future<AppVersion?> Function())>[
      ('the channel fails', () async => throw PlatformException(code: 'x')),
      ('there is no answer', () async => null),
      ('the code is 0', () async => const AppVersion(name: '1.0', code: 0)),
      ('the name is blank', () async => const AppVersion(name: ' v ', code: 3)),
    ]) {
      testWidgets('reads "Version unavailable" when $why', (tester) async {
        await show(tester, answer);
        expect(
          _version(tester),
          versionUnavailable,
          reason: 'settings-options: $why gives no half version',
        );
        expect(find.textContaining('BUILD'), findsNothing);
      });
    }

    testWidgets('keeps its height, empty, while Android has not answered', (
      tester,
    ) async {
      var asked = 0;
      await show(tester, () {
        asked++;
        return Completer<AppVersion?>().future;
      });
      expect(_version(tester), '');
      expect(
        tester.getSize(find.byKey(const Key('settings-version'))).height,
        closeTo(9.5 * 1.6, .01),
      );
      await _toggle(tester, 'settings-toggle-dots');
      expect(asked, 1, reason: 'settings-options: asked once per visit');
    });
  });
}
