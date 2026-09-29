import 'dart:math';

import 'package:honest_chess/engine/engine.dart';

/// Which kind of game a [GameSetup] starts.
enum GameKind { vsComputer, twoPlayers }

/// Everything a new game is started from, before the computer's seed is
/// drawn: the kind, the computer's [strength] and your [colour] (vs the
/// computer only; a null colour is drawn at random), the time control, and
/// whether the board turns to the side to move (two players only).
typedef GameSetup = ({
  GameKind mode,
  Strength? strength,
  Colour? colour,
  TimeControl timeControl,
  bool rotate,
});

/// The design's default game against the computer: Club, you White,
/// Rapid 10+5 (owner, /n8-plan M3 round one).
const GameSetup vsComputerDefault = (
  mode: GameKind.vsComputer,
  strength: Strength.club,
  colour: Colour.white,
  timeControl: Timed.rapid,
  rotate: false,
);

/// The design's default two-player game: Rapid 10+5, the board not turning.
const GameSetup twoPlayerDefault = (
  mode: GameKind.twoPlayers,
  strength: null,
  colour: null,
  timeControl: Timed.rapid,
  rotate: false,
);

/// The [GameMode] a game from [setup] is played in. Against the computer
/// the seed is [seed], or a fresh [newGameSeed] when null, and a null
/// colour is drawn from [random].
GameMode modeFor(GameSetup setup, {int? seed, Random? random}) =>
    switch (setup.mode) {
      GameKind.twoPlayers => const TwoPlayer(),
      GameKind.vsComputer => VsComputer(
        playerColour:
            setup.colour ??
            ((random ?? Random()).nextBool() ? Colour.white : Colour.black),
        step: setup.strength ?? Strength.club,
        seed: seed ?? newGameSeed(),
      ),
    };
