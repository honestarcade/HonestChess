import 'package:honest_chess/data/game_saves.dart';
import 'package:honest_chess/data/play_mode.dart';
import 'package:honest_chess/data/recorded_state.dart';
import 'package:honest_chess/data/stats.dart';
import 'package:honest_chess/engine/engine.dart';
import 'package:honest_chess/ui/game/game_controller.dart';

// The top-level rule, under a name the listener's own [isAbandonable] does
// not hide.
bool _abandonable(Game game, RecordedState recorded) =>
    isAbandonable(game, recorded);

/// Turns the controller's games into statistics.
///
/// A game that ends is recorded by an end stage put first on [saves], so
/// the count is made before the saved document is deleted. A game left
/// unfinished for a new one is recorded by a replace stage on
/// [controller], which the new game waits for: the live game when the new
/// game is of its mode, or — for a new game against the computer while the
/// board holds none — the saved computer game it will overwrite.
///
/// A plain object, not a widget: the app root creates it before the saved
/// games are loaded, so a finished game found at launch is counted, and
/// disposes it with itself. It holds no stream subscription.
class StatsListener {
  StatsListener({
    required this._controller,
    required this._recorder,
    required this._saves,
  }) {
    _controller.addReplaceStage(_replacing);
    _saves.addEndStage(_ended, first: true);
  }

  final GameController _controller;
  final StatsRecorder _recorder;
  final GameSaves _saves;

  /// Whether leaving [mode]'s game now would count as a loss: the live game
  /// when it is of [mode], otherwise [mode]'s saved game. For the new-game
  /// warning and the Restart message.
  bool isAbandonable(PlayMode mode) {
    if (!_controller.isIdle && PlayMode.of(_controller.game.mode) == mode) {
      final game = _controller.game;
      return _abandonable(
        game,
        RecordedState.fromJson(_controller.recorded, game),
      );
    }
    final saved = _savedState(mode);
    return saved != null && _abandonable(saved.game, saved.recorded);
  }

  ({Game game, RecordedState recorded})? _savedState(PlayMode mode) {
    final game = _saves.load(mode);
    if (game == null) return null;
    return (
      game: game,
      recorded: RecordedState.fromJson(_saves.recorded(mode), game),
    );
  }

  Future<void> _replacing(
    Game? outgoing,
    RecordedState? outgoingRecorded,
    PlayMode incoming,
  ) async {
    if (outgoing != null && PlayMode.of(outgoing.mode) == incoming) {
      if (outgoingRecorded != null &&
          _abandonable(outgoing, outgoingRecorded)) {
        await _recorder.recordAbandon(outgoing, outgoingRecorded);
      }
      return;
    }
    // A new game of the other mode never touches this mode's saved game,
    // except that a new game against the computer overwrites its slot.
    if (incoming == PlayMode.computer) await _abandonSaved(PlayMode.computer);
  }

  Future<void> _abandonSaved(PlayMode mode) async {
    final saved = _savedState(mode);
    if (saved == null || !_abandonable(saved.game, saved.recorded)) return;
    await _recorder.recordAbandon(saved.game, saved.recorded);
  }

  Future<void> _ended(
    PlayMode mode,
    Game game,
    Map<String, Object?> recorded,
  ) async {
    final state = RecordedState.fromJson(recorded, game);
    final outcome = await _recorder.recordResult(game, state);
    if (outcome != RecordOutcome.invalid) _controller.markRecorded(state.id);
  }

  void dispose() {
    _controller.removeReplaceStage(_replacing);
    _saves.removeEndStage(_ended);
  }
}
