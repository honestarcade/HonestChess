import 'package:honest_chess/data/app_store.dart';
import 'package:honest_chess/engine/engine.dart';

/// The two kinds of game, each with one saved game of its own, so a
/// two-player game never touches the game against the computer. Its [name]
/// is the value `meta.lastPlayed` stores.
enum PlayMode {
  computer,
  two;

  static PlayMode of(GameMode mode) => switch (mode) {
    VsComputer() => PlayMode.computer,
    TwoPlayer() => PlayMode.two,
  };

  /// The document holding this mode's saved game.
  StoreDoc get doc => switch (this) {
    PlayMode.computer => StoreDoc.gameComputer,
    PlayMode.two => StoreDoc.gameTwo,
  };

  /// The other mode.
  PlayMode get other => switch (this) {
    PlayMode.computer => PlayMode.two,
    PlayMode.two => PlayMode.computer,
  };
}
