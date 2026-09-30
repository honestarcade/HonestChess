import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:honest_chess/data/app_store.dart';
import 'package:honest_chess/data/game_event.dart';
import 'package:honest_chess/data/play_mode.dart';
import 'package:honest_chess/data/recorded_state.dart';
import 'package:honest_chess/engine/engine.dart';

/// What Continue would resume: the mode, the computer's step (null for two
/// players), and the fullmove number and side to move of its position.
typedef OfferedGame = ({
  PlayMode mode,
  Strength? step,
  int fullmove,
  Colour sideToMove,
});

/// One step run when a game ends, before its document is deleted. It gets
/// the finished game and the `recorded` map carried with it.
typedef EndStage = Future<void> Function(
  PlayMode mode,
  Game game,
  Map<String, Object?> recorded,
);

/// A saved game held in memory: the decoded game and its `recorded` map.
typedef _Slot = ({Game game, Map<String, Object?> recorded});

/// The two saved games, one per [PlayMode], and which was played last.
///
/// Each mode's document is `{"game": <Game.toJson()>, "recorded": {...}}`;
/// `meta` is `{"lastPlayed": "computer" | "two"}`. A game is written on every
/// change event from the controller (never on a clock tick) and its document
/// is deleted once it ends, so only an unfinished game is ever resumable.
///
/// The in-memory slots are the truth for [load], [recorded] and [offered]:
/// they change as each event is handled, not when the store confirms,
/// because a failed write is ignored and the next event rewrites.
///
/// Each mode's work runs on one serial chain: an event's handling starts
/// only after that mode's previous handling has finished, and a save's
/// handling ends once its writes are queued with the store, whose own
/// per-document queue coalesces bursts.
class GameSaves extends ChangeNotifier {
  /// Saves over [store]. [time] is the time source games loaded at launch
  /// run their clocks on (default a monotonic stopwatch); tests pass a fake.
  GameSaves(this._store, {this._time});

  final AppStore _store;
  final TimeSource? _time;
  final _slots = <PlayMode, _Slot>{};
  final _tails = <PlayMode, Future<void>>{
    for (final mode in PlayMode.values) mode: Future<void>.value(),
  };
  final _endStages = <EndStage>[];
  StreamSubscription<GameEvent>? _subscription;

  /// The mode saved last, as this session knows it; null until a save or a
  /// readable `meta`.
  PlayMode? _lastPlayed;

  /// `meta.lastPlayed` as last written or loaded; `meta` is rewritten only
  /// when a save would change it.
  PlayMode? _storedLastPlayed;
  OfferedGame? _offered;
  bool _disposed = false;

  /// The game Continue would resume: the last-played mode's saved game, or,
  /// with none there, the other mode's; null when neither holds one.
  OfferedGame? get offered => _offered;

  /// The mode played last: the last saved this session, else `meta`'s;
  /// null when neither says.
  PlayMode? get lastPlayed => _lastPlayed;

  /// [mode]'s saved game, from memory; null when it has none.
  Game? load(PlayMode mode) => _slots[mode]?.game;

  /// The `recorded` map saved with [mode]'s game; empty when it has none.
  Map<String, Object?> recorded(PlayMode mode) =>
      _slots[mode]?.recorded ?? const {};

  /// [mode]'s unfinished game, from its in-memory slot — which every save
  /// keeps current, so for the live game it is the live game — with
  /// whether it has been started (#82's sticky flag); null when it has
  /// none. A finished game leaves its slot, so it is never unfinished here.
  ({bool started})? unfinished(PlayMode mode) {
    final slot = _slots[mode];
    if (slot == null || slot.game.isOver) return null;
    return (started: RecordedState.fromJson(slot.recorded, slot.game).started);
  }

  /// Listens to the controller's [events]; [dispose] stops listening.
  void attach(Stream<GameEvent> events) {
    _subscription?.cancel();
    _subscription = events.listen(_handle);
  }

  /// Adds a step to run, in registration order, when a game ends and
  /// before its document is deleted; [first] puts it ahead of those
  /// already added.
  void addEndStage(EndStage stage, {bool first = false}) =>
      first ? _endStages.insert(0, stage) : _endStages.add(stage);

  void removeEndStage(EndStage stage) => _endStages.remove(stage);

  void _handle(GameEvent event) {
    switch (event) {
      case GameStarted() ||
          GameMoved() ||
          GameTookBack() ||
          GamePaused() ||
          GameResumed():
        // A move that ends the game is followed by its [GameEnded].
        save(event.game, event.recorded).ignore();
      case GameEnded():
        _ended(PlayMode.of(event.game.mode), event.game, event.recorded);
      case GameRestored() || GameAbandoned() || GameDrawDeclined():
        break;
    }
  }

  /// Saves [game] with [recorded] to its mode's document and makes that
  /// mode the last played. Completes once the writes are queued. A finished
  /// game is not saved: it is never resumable.
  Future<void> save(Game game, Map<String, Object?> recorded) {
    if (game.isOver) return Future.value();
    final mode = PlayMode.of(game.mode);
    final kept = Map<String, Object?>.unmodifiable(recorded);
    return _enqueue(mode, () async {
      _slots[mode] = (game: game, recorded: kept);
      _lastPlayed = mode;
      _changed();
      _store.write(mode.doc, {
        'game': game.toJson(),
        'recorded': kept,
      }).ignore();
      if (_storedLastPlayed != mode) {
        _storedLastPlayed = mode;
        _store.write(StoreDoc.meta, {'lastPlayed': mode.name}).ignore();
      }
    });
  }

  /// A finished game is no longer resumable: it leaves its slot at once,
  /// then the end stages run and its document is deleted.
  void _ended(PlayMode mode, Game game, Map<String, Object?> recorded) {
    final kept = Map<String, Object?>.unmodifiable(recorded);
    _enqueue(mode, () async {
      if (_slots.remove(mode) != null) _changed();
      await _runEndStages(mode, game, kept);
    }).ignore();
  }

  Future<void> _runEndStages(
    PlayMode mode,
    Game game,
    Map<String, Object?> recorded,
  ) async {
    for (final stage in List.of(_endStages)) {
      try {
        await stage(mode, game, recorded);
      } on Object catch (e) {
        // The document is kept: the next launch runs the stages again.
        debugPrint('game-saves: an end stage failed for ${mode.name}: $e');
        return;
      }
    }
    await _store.delete(mode.doc);
  }

  /// Reads, decodes and holds [mode]'s saved game. A document the engine
  /// refuses is quarantined (with the store's notice) and loads as none; a
  /// finished one has its end stages and delete queued on its mode's chain,
  /// without holding the launch for them, and is never offered.
  Future<void> loadSlot(PlayMode mode) async {
    final read = await _store.read(mode.doc);
    if (read is! Loaded) return;
    final _Slot slot;
    try {
      slot = _decode(mode, read.data);
    } on Object catch (e) {
      await _store.quarantine(mode.doc, '$e');
      return;
    }
    if (slot.game.isOver) {
      _enqueue(
        mode,
        () => _runEndStages(mode, slot.game, slot.recorded),
      ).ignore();
      return;
    }
    _slots[mode] = slot;
    _changed();
  }

  _Slot _decode(PlayMode mode, Map<String, Object?> data) {
    final json = data['game'];
    if (json is! Map<String, Object?>) {
      throw const FormatException('game-saves: "game" is not a map');
    }
    final game = Game.fromJson(json, time: _time);
    if (PlayMode.of(game.mode) != mode) {
      throw FormatException(
        'game-saves: a ${PlayMode.of(game.mode).name} game in the '
        '${mode.name} slot',
      );
    }
    final recorded = data['recorded'];
    return (
      game: game,
      recorded: recorded is Map<String, Object?>
          ? Map.unmodifiable(recorded)
          : const {},
    );
  }

  /// Reads which mode was played last. A missing, damaged or unknown value
  /// leaves it unset, which prefers the computer's game.
  Future<void> loadMeta() async {
    final read = await _store.read(StoreDoc.meta);
    final value = read is Loaded ? read.data['lastPlayed'] : null;
    final mode = PlayMode.values.asNameMap()[value];
    _storedLastPlayed = mode;
    _lastPlayed ??= mode;
    _changed();
  }

  /// Both saved games and `meta`, read together.
  Future<void> loadAll() => Future.wait([
    loadSlot(PlayMode.computer),
    loadSlot(PlayMode.two),
    loadMeta(),
  ]);

  /// Completes when both modes' chains are empty and the store has written
  /// everything queued.
  Future<void> flush() async {
    for (;;) {
      final tails = [for (final mode in PlayMode.values) _tails[mode]!];
      await Future.wait(tails);
      if (PlayMode.values.every((m) => identical(_tails[m], tails[m.index]))) {
        break;
      }
    }
    await _store.flush();
  }

  Future<void> _enqueue(PlayMode mode, Future<void> Function() work) {
    final next = _tails[mode]!.then((_) => work()).catchError((Object e) {
      debugPrint('game-saves: ${mode.name}: $e');
    });
    _tails[mode] = next;
    return next;
  }

  void _changed() {
    final preferred = _lastPlayed ?? PlayMode.computer;
    final mode = _slots.containsKey(preferred) ? preferred : preferred.other;
    final game = _slots[mode]?.game;
    _offered = game == null
        ? null
        : (
            mode: mode,
            step: switch (game.mode) {
              VsComputer(:final step) => step,
              TwoPlayer() => null,
            },
            fullmove: game.position.fullmoveNumber,
            sideToMove: game.sideToMove,
          );
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _subscription?.cancel();
    super.dispose();
  }
}
