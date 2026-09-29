import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:honest_chess/data/app_store.dart';
import 'package:honest_chess/data/settings_store.dart';
import 'package:honest_chess/engine/engine.dart';
import 'package:honest_chess/ui/board/board_options.dart';
import 'package:honest_chess/ui/game/defaults.dart';

/// Every field away from its default.
const _board = BoardOptions(
  theme: BoardTheme.bone,
  pieceStyle: PieceStyle.flat,
  surface: BoardSurface.wood,
  legalMoveDots: false,
  lastMoveHighlight: false,
  takebackAllowed: false,
  autoQueen: true,
  rotateEachTurn: true,
  animations: false,
  flagCheck: false,
);

final _setup = SetupChoices(
  computer: const ComputerChoices(
    step: Strength.master,
    colour: ColourChoice.random,
    time: TimeChoice.custom,
  ),
  two: const TwoPlayerChoices(time: TimeChoice.untimed),
  custom: const CustomTime(minutes: 90, increment: 0),
);

Future<SettingsStore> _loaded(AppStore store) async {
  final settings = SettingsStore();
  addTearDown(settings.dispose);
  await settings.load(store);
  return settings;
}

Map<String, Object?> _saved(AppStore store) =>
    (jsonDecode(store.rawText(StoreDoc.settings)!) as Map)['data']
        as Map<String, Object?>;

String _section(AppStore store, String key) => jsonEncode(_saved(store)[key]);

void main() {
  test('a store that was never loaded starts on the defaults', () {
    final settings = SettingsStore();
    addTearDown(settings.dispose);
    expect(
      settings.board.value,
      const BoardOptions(),
      reason: 'settings-store: fresh board options are the defaults',
    );
    expect(
      settings.setup.value,
      SetupChoices.initial,
      reason: 'settings-store: fresh setup choices are the initial ones',
    );
    expect(
      SetupChoices.initial,
      SetupChoices(
        computer: const ComputerChoices(
          step: Strength.club,
          colour: ColourChoice.white,
          time: TimeChoice.rapid,
        ),
        two: const TwoPlayerChoices(time: TimeChoice.rapid),
        custom: const CustomTime(minutes: 10, increment: 5),
      ),
      reason:
          'settings-store: first-time choices are Club, White, Rapid '
          'and Rapid, custom 10+5',
    );
  });

  test('every board field and setup choice survives a relaunch', () async {
    final store = AppStore.memory();
    final first = await _loaded(store);
    first.updateBoard((_) => _board);
    first.updateSetup((_) => _setup);
    await store.flush();

    final second = await _loaded(store);
    expect(
      second.board.value,
      _board,
      reason: 'settings-store: every BoardOptions field round-trips',
    );
    expect(
      second.setup.value,
      _setup,
      reason: 'settings-store: every SetupChoices field round-trips',
    );
  });

  test('each enum value round-trips by its exact name', () async {
    for (final theme in BoardTheme.values) {
      for (final style in PieceStyle.values) {
        for (final surface in BoardSurface.values) {
          final options = BoardOptions(
            theme: theme,
            pieceStyle: style,
            surface: surface,
          );
          expect(
            decodeBoard(jsonDecode(jsonEncode(encodeBoard(options)))),
            options,
            reason: 'settings-store: $theme/$style/$surface round-trips',
          );
        }
      }
    }
    for (final step in Strength.values) {
      for (final colour in ColourChoice.values) {
        for (final time in TimeChoice.values) {
          final choices = SetupChoices.initial.copyWith(
            computer: ComputerChoices(step: step, colour: colour, time: time),
            two: TwoPlayerChoices(time: time),
          );
          expect(
            decodeSetup(jsonDecode(jsonEncode(encodeSetup(choices)))),
            choices,
            reason: 'settings-store: $step/$colour/$time round-trips',
          );
        }
      }
    }
    expect(
      encodeBoard(const BoardOptions())['theme'],
      'navy',
      reason: 'settings-store: enum values are stored by name',
    );
  });

  test('an update to one section leaves the other byte-identical', () async {
    final store = AppStore.memory(
      documents: {
        StoreDoc.settings: {
          'setup': {
            'future': [1, 2],
            'custom': {'increment': 3, 'minutes': 7, 'x': true},
            'computer': {'time': 'blitz', 'step': 'strong', 'colour': 'black'},
          },
          'board': {'theme': 'teal', 'shiny': 'yes'},
          'later': {'a': 1},
        },
      },
    );
    final settings = await _loaded(store);
    final setupBefore = jsonEncode(
      (jsonDecode(store.rawText(StoreDoc.settings)!) as Map)['data']['setup'],
    );
    settings.updateBoard((o) => o.copyWith(pieceStyle: PieceStyle.outline));
    await store.flush();
    expect(
      _section(store, 'setup'),
      setupBefore,
      reason: 'settings-store: a board update writes setup back as read',
    );
    expect(
      settings.setup.value.computer.step,
      Strength.strong,
      reason: 'settings-store: a board update leaves the setup value alone',
    );
    expect(_saved(store).keys, [
      'board',
      'setup',
      'later',
    ], reason: 'settings-store: board, setup, then unknown top-level keys');

    final boardBefore = _section(store, 'board');
    settings.updateSetup(
      (s) => s.copyWith(two: const TwoPlayerChoices(time: TimeChoice.blitz)),
    );
    await store.flush();
    expect(
      _section(store, 'board'),
      boardBefore,
      reason: 'settings-store: a setup update writes board back as written',
    );
    expect(
      settings.board.value,
      const BoardOptions(
        theme: BoardTheme.teal,
        pieceStyle: PieceStyle.outline,
      ),
      reason: 'settings-store: a setup update leaves the board value alone',
    );
    expect(
      jsonEncode(_saved(store)['later']),
      '{"a":1}',
      reason: 'settings-store: unknown top-level keys survive every write',
    );
  });

  test(
    'unknown keys are carried at every level, after the known ones',
    () async {
      final store = AppStore.memory(
        documents: {
          StoreDoc.settings: {
            'board': {'zz': 1, 'theme': 'violet'},
            'setup': {
              'yy': 2,
              'computer': {'c': 3, 'step': 'casual'},
              'two': {'t': 4},
              'custom': {'u': 5},
            },
          },
        },
      );
      final settings = await _loaded(store);
      settings.updateBoard((o) => o.copyWith(autoQueen: true));
      settings.updateSetup(
        (s) => s.copyWith(custom: const CustomTime(minutes: 20, increment: 1)),
      );
      await store.flush();
      final data = _saved(store);
      final board = data['board']! as Map;
      expect(
        board.keys.toList(),
        [...encodeBoard(const BoardOptions()).keys, 'zz'],
        reason: 'settings-store: board keys in field order, then unknown ones',
      );
      expect(board['zz'], 1, reason: 'settings-store: board unknown kept');
      final setup = data['setup']! as Map;
      expect(setup.keys.toList(), [
        'computer',
        'two',
        'custom',
        'yy',
      ], reason: 'settings-store: setup keys in order, then unknown ones');
      expect((setup['computer']! as Map).keys.toList(), [
        'step',
        'colour',
        'time',
        'c',
      ], reason: 'settings-store: computer keys in order, then unknown ones');
      expect(
        (setup['two']! as Map)['t'],
        4,
        reason: 'settings-store: two-player unknown kept',
      );
      expect((setup['custom']! as Map).keys.toList(), [
        'minutes',
        'increment',
        'u',
      ], reason: 'settings-store: custom keys in order, then unknown ones');
    },
  );

  test('a damaged document gives the defaults and raises the notice', () async {
    for (final text in ['{not json', '[1, 2]', '{"format": 1, "data": 3}']) {
      final store = AppStore.memory()..putRaw(StoreDoc.settings, text);
      final settings = await _loaded(store);
      expect(
        settings.board.value,
        const BoardOptions(),
        reason: 'settings-store: damaged "$text" gives the default board',
      );
      expect(
        settings.setup.value,
        SetupChoices.initial,
        reason: 'settings-store: damaged "$text" gives the initial setup',
      );
      expect(
        store.corruptionNotices.value,
        contains(StoreDoc.settings),
        reason: 'settings-store: damaged "$text" raises the notice',
      );
    }
  });

  test('a missing document is not written until the first change', () async {
    final store = AppStore.memory();
    final settings = await _loaded(store);
    settings.updateBoard((o) => o);
    settings.updateSetup((s) => s.copyWith());
    await store.flush();
    expect(
      store.rawText(StoreDoc.settings),
      isNull,
      reason: 'settings-store: an unchanged value is not written',
    );
    var notified = 0;
    settings.board.addListener(() => notified++);
    settings.updateBoard((o) => o.copyWith(theme: BoardTheme.navy));
    expect(
      notified,
      0,
      reason: 'settings-store: an unchanged value is not announced',
    );
    settings.updateBoard((o) => o.copyWith(theme: BoardTheme.teal));
    await store.flush();
    expect(notified, 1, reason: 'settings-store: a change is announced');
    expect(_saved(store).keys, [
      'board',
    ], reason: 'settings-store: a section never read stays absent');
  });

  test('a bad section or field falls back alone, silently', () async {
    final setup = encodeSetup(_setup);
    final store = AppStore.memory(
      documents: {
        StoreDoc.settings: {'board': 5, 'setup': setup},
      },
    );
    final settings = await _loaded(store);
    expect(
      settings.board.value,
      const BoardOptions(),
      reason: 'settings-store: a non-object board reads as the defaults',
    );
    expect(
      settings.setup.value,
      _setup,
      reason: 'settings-store: the saved setup loads beside a bad board',
    );
    expect(
      store.corruptionNotices.value,
      isEmpty,
      reason: 'settings-store: a bad section raises no notice',
    );

    final fields = AppStore.memory(
      documents: {
        StoreDoc.settings: {
          'board': {
            ...encodeBoard(_board),
            'theme': 'green',
            'legalMoveDots': 'no',
          },
          'setup': {
            'computer': {'step': 'Master', 'colour': 'black', 'time': 7},
            'two': 'rapid',
            'custom': {'minutes': 120, 'increment': 10.5},
          },
        },
      },
    );
    final mixed = await _loaded(fields);
    expect(
      mixed.board.value,
      _board.copyWith(theme: BoardTheme.navy, legalMoveDots: true),
      reason:
          'settings-store: an unknown or wrong-typed field takes its '
          'default and the rest load',
    );
    expect(
      mixed.setup.value,
      SetupChoices(
        computer: const ComputerChoices(
          step: Strength.club,
          colour: ColourChoice.black,
          time: TimeChoice.rapid,
        ),
        two: const TwoPlayerChoices(time: TimeChoice.rapid),
        custom: const CustomTime(minutes: 90, increment: 5),
      ),
      reason:
          'settings-store: names are case-sensitive, 120 minutes clamps '
          'to 90 and a 10.5 increment takes the default',
    );
    expect(
      decodeSetup({
        'custom': {'minutes': 10.0, 'increment': -4},
      }).custom,
      const CustomTime(minutes: 10, increment: 0),
      reason: 'settings-store: 10.0 is not an integer; -4 clamps to 0',
    );

    mixed.updateBoard((o) => o.copyWith(autoQueen: false));
    await fields.flush();
    expect(
      (_saved(fields)['board']! as Map)['theme'],
      'navy',
      reason:
          'settings-store: an unrecognised value is replaced by the '
          'default the app shows',
    );
  });

  test('TimeChoice.of and ColourChoice.of map setups to choices', () {
    expect(TimeChoice.of(const Untimed()), TimeChoice.untimed);
    expect(TimeChoice.of(Timed.blitz), TimeChoice.blitz);
    expect(TimeChoice.of(Timed.rapid), TimeChoice.rapid);
    expect(TimeChoice.of(Timed.classical), TimeChoice.classical);
    expect(
      TimeChoice.of(Timed(15, 10)),
      TimeChoice.custom,
      reason: 'settings-store: a non-preset control is custom',
    );
    expect(ColourChoice.of(Colour.white), ColourChoice.white);
    expect(ColourChoice.of(Colour.black), ColourChoice.black);
    expect(ColourChoice.of(null), ColourChoice.random);
  });
}
