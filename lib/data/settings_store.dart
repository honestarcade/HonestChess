import 'package:flutter/foundation.dart';

import '../engine/engine.dart';
import '../ui/board/board_options.dart';
import '../ui/game/defaults.dart';
import 'app_store.dart';

/// The board's look and switches and the setup screens' last choices, kept
/// in the `settings` document:
///
/// `{"board": {"theme": "navy", "pieceStyle": "classic", …},
///   "setup": {"computer": {"step", "colour", "time"}, "two": {"time"},
///             "custom": {"minutes", "increment"}}}`
///
/// Fields are keyed by their Dart names and enum values by exact name. A
/// missing, wrong-typed or unknown value reads as that field's default; keys
/// this build does not know are written back where they were, so a newer
/// version's settings survive an older one.
///
/// It starts on the defaults; [load] fills it in place. Each update writes
/// the whole document through the store's queue (a failed write keeps the
/// value: the store's policy), and a missing or damaged document is not
/// rewritten until the first change.
class SettingsStore {
  SettingsStore();

  final _board = ValueNotifier<BoardOptions>(const BoardOptions());
  final _setup = ValueNotifier<SetupChoices>(SetupChoices.initial);

  ValueListenable<BoardOptions> get board => _board;
  ValueListenable<SetupChoices> get setup => _setup;

  AppStore? _store;

  /// The document as last read or written; each update rebuilds only its
  /// own section and writes the rest back as it is here.
  Map<String, Object?> _document = const {};

  /// Reads the `settings` document from [store], which every later update
  /// writes to.
  Future<void> load(AppStore store) async {
    _store = store;
    final read = await store.read(StoreDoc.settings);
    _document = switch (read) {
      Loaded(:final data) => data,
      Absent() => const {},
    };
    _board.value = decodeBoard(_document['board']);
    _setup.value = decodeSetup(_document['setup']);
  }

  /// Applies [change] to the board options; an unchanged value is neither
  /// written nor announced.
  void updateBoard(BoardOptions Function(BoardOptions) change) {
    final next = change(_board.value);
    if (next == _board.value) return;
    _board.value = next;
    _write('board', encodeBoard(next, _document['board']));
  }

  /// Applies [change] to the setup choices; an unchanged value is neither
  /// written nor announced.
  void updateSetup(SetupChoices Function(SetupChoices) change) {
    final next = change(_setup.value);
    if (next == _setup.value) return;
    _setup.value = next;
    _write('setup', encodeSetup(next, _document['setup']));
  }

  void _write(String section, Map<String, Object?> value) {
    final before = _document;
    _document = {
      for (final key in _sections)
        if (key == section)
          key: value
        else if (before.containsKey(key))
          key: before[key],
      for (final entry in before.entries)
        if (!_sections.contains(entry.key)) entry.key: entry.value,
    };
    _store?.write(StoreDoc.settings, _document).ignore();
  }

  void dispose() {
    _board.dispose();
    _setup.dispose();
  }
}

const _sections = ['board', 'setup'];

/// [raw] when it is a JSON object, else an empty one.
Map<String, Object?> _object(Object? raw) =>
    raw is Map<String, Object?> ? raw : const {};

/// [known] in its order, then [raw]'s keys it does not name, in read order.
Map<String, Object?> _withUnknown(Map<String, Object?> known, Object? raw) => {
  ...known,
  for (final entry in _object(raw).entries)
    if (!known.containsKey(entry.key)) entry.key: entry.value,
};

T _enum<T extends Enum>(List<T> values, Object? raw, T fallback) {
  for (final value in values) {
    if (value.name == raw) return value;
  }
  return fallback;
}

bool _bool(Object? raw, bool fallback) => raw is bool ? raw : fallback;

/// A JSON integer clamped to [min]–[max]; anything else is [fallback].
int _int(Object? raw, int fallback, int min, int max) =>
    raw is int ? raw.clamp(min, max) : fallback;

/// The board options in [raw], field by field over the defaults.
BoardOptions decodeBoard(Object? raw) {
  final json = _object(raw);
  const d = BoardOptions();
  return BoardOptions(
    theme: _enum(BoardTheme.values, json['theme'], d.theme),
    pieceStyle: _enum(PieceStyle.values, json['pieceStyle'], d.pieceStyle),
    surface: _enum(BoardSurface.values, json['surface'], d.surface),
    legalMoveDots: _bool(json['legalMoveDots'], d.legalMoveDots),
    lastMoveHighlight: _bool(json['lastMoveHighlight'], d.lastMoveHighlight),
    takebackAllowed: _bool(json['takebackAllowed'], d.takebackAllowed),
    autoQueen: _bool(json['autoQueen'], d.autoQueen),
    rotateEachTurn: _bool(json['rotateEachTurn'], d.rotateEachTurn),
    animations: _bool(json['animations'], d.animations),
    sfx: _bool(json['sfx'], d.sfx),
    music: _bool(json['music'], d.music),
    flagCheck: _bool(json['flagCheck'], d.flagCheck),
  );
}

/// [options] as the `board` section, carrying [raw]'s unknown keys.
Map<String, Object?> encodeBoard(BoardOptions options, [Object? raw]) =>
    _withUnknown({
      'theme': options.theme.name,
      'pieceStyle': options.pieceStyle.name,
      'surface': options.surface.name,
      'legalMoveDots': options.legalMoveDots,
      'lastMoveHighlight': options.lastMoveHighlight,
      'takebackAllowed': options.takebackAllowed,
      'autoQueen': options.autoQueen,
      'rotateEachTurn': options.rotateEachTurn,
      'animations': options.animations,
      'sfx': options.sfx,
      'music': options.music,
      'flagCheck': options.flagCheck,
    }, raw);

/// The setup choices in [raw], field by field over [SetupChoices.initial].
SetupChoices decodeSetup(Object? raw) {
  final json = _object(raw);
  final d = SetupChoices.initial;
  final computer = _object(json['computer']);
  final two = _object(json['two']);
  final custom = _object(json['custom']);
  return SetupChoices(
    computer: ComputerChoices(
      step: _enum(Strength.values, computer['step'], d.computer.step),
      colour: _enum(ColourChoice.values, computer['colour'], d.computer.colour),
      time: _enum(TimeChoice.values, computer['time'], d.computer.time),
    ),
    two: TwoPlayerChoices(
      time: _enum(TimeChoice.values, two['time'], d.two.time),
    ),
    custom: CustomTime(
      minutes: _int(
        custom['minutes'],
        d.custom.minutes,
        customMinutesMin,
        customMinutesMax,
      ),
      increment: _int(
        custom['increment'],
        d.custom.increment,
        customIncrementMin,
        customIncrementMax,
      ),
    ),
  );
}

/// [choices] as the `setup` section, carrying [raw]'s unknown keys at each
/// level.
Map<String, Object?> encodeSetup(SetupChoices choices, [Object? raw]) {
  final json = _object(raw);
  return _withUnknown({
    'computer': _withUnknown({
      'step': choices.computer.step.name,
      'colour': choices.computer.colour.name,
      'time': choices.computer.time.name,
    }, json['computer']),
    'two': _withUnknown({'time': choices.two.time.name}, json['two']),
    'custom': _withUnknown({
      'minutes': choices.custom.minutes,
      'increment': choices.custom.increment,
    }, json['custom']),
  }, json);
}
