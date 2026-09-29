import 'dart:math';

import 'package:flutter/foundation.dart';

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

/// The setup screens' five time choices.
enum TimeChoice {
  untimed,
  blitz,
  rapid,
  classical,
  custom;

  /// The choice that shows [control]: its preset when it has one, custom
  /// for any other timed control.
  static TimeChoice of(TimeControl control) => switch (control) {
    Untimed() => untimed,
    Timed(:final preset) => switch (preset) {
      TimePreset.blitz => blitz,
      TimePreset.rapid => rapid,
      TimePreset.classical => classical,
      null => custom,
    },
  };

  /// The time control this choice starts: [minutes] and [increment] are
  /// the custom pair, used only by [custom].
  TimeControl toTimeControl(int minutes, int increment) => switch (this) {
    untimed => const Untimed(),
    blitz => Timed.blitz,
    rapid => Timed.rapid,
    classical => Timed.classical,
    custom => Timed(minutes, increment),
  };
}

/// Play as White, Black, or drawn at random each game.
enum ColourChoice {
  white,
  black,
  random;

  /// The choice for a setup's colour, where null means random.
  static ColourChoice of(Colour? colour) => switch (colour) {
    Colour.white => white,
    Colour.black => black,
    null => random,
  };
}

/// The custom time's bounds, which are [Timed]'s: the steppers and the
/// settings codec clamp to them.
const customMinutesMin = Timed.minMinutes;
const customMinutesMax = Timed.maxMinutes;
const customIncrementMin = 0;
const customIncrementMax = Timed.maxIncrementSeconds;

/// The design's first custom time (`custom:{min:10,inc:5}`).
const customTimeDefault = (minutes: 10, increment: 5);

/// The computer setup screen's last choices.
@immutable
final class ComputerChoices {
  const ComputerChoices({
    required this.step,
    required this.colour,
    required this.time,
  });

  final Strength step;
  final ColourChoice colour;
  final TimeChoice time;

  ComputerChoices copyWith({
    Strength? step,
    ColourChoice? colour,
    TimeChoice? time,
  }) => ComputerChoices(
    step: step ?? this.step,
    colour: colour ?? this.colour,
    time: time ?? this.time,
  );

  @override
  bool operator ==(Object other) =>
      other is ComputerChoices &&
      other.step == step &&
      other.colour == colour &&
      other.time == time;

  @override
  int get hashCode => Object.hash(step, colour, time);
}

/// The two-player setup screen's last choice.
@immutable
final class TwoPlayerChoices {
  const TwoPlayerChoices({required this.time});

  final TimeChoice time;

  TwoPlayerChoices copyWith({TimeChoice? time}) =>
      TwoPlayerChoices(time: time ?? this.time);

  @override
  bool operator ==(Object other) =>
      other is TwoPlayerChoices && other.time == time;

  @override
  int get hashCode => time.hashCode;
}

/// The custom time both setup screens share: [minutes] per side and
/// [increment] seconds per move, within the custom bounds.
@immutable
final class CustomTime {
  const CustomTime({required this.minutes, required this.increment})
    : assert(minutes >= customMinutesMin && minutes <= customMinutesMax),
      assert(
        increment >= customIncrementMin && increment <= customIncrementMax,
      );

  final int minutes;
  final int increment;

  CustomTime copyWith({int? minutes, int? increment}) => CustomTime(
    minutes: minutes ?? this.minutes,
    increment: increment ?? this.increment,
  );

  @override
  bool operator ==(Object other) =>
      other is CustomTime &&
      other.minutes == minutes &&
      other.increment == increment;

  @override
  int get hashCode => Object.hash(minutes, increment);
}

/// What the setup screens remember between games.
@immutable
final class SetupChoices {
  const SetupChoices({
    required this.computer,
    required this.two,
    required this.custom,
  });

  /// The first-time choices: the two default games' own, and the design's
  /// custom time.
  static final initial = SetupChoices(
    computer: ComputerChoices(
      step: vsComputerDefault.strength!,
      colour: ColourChoice.of(vsComputerDefault.colour),
      time: TimeChoice.of(vsComputerDefault.timeControl),
    ),
    two: TwoPlayerChoices(time: TimeChoice.of(twoPlayerDefault.timeControl)),
    custom: CustomTime(
      minutes: customTimeDefault.minutes,
      increment: customTimeDefault.increment,
    ),
  );

  final ComputerChoices computer;
  final TwoPlayerChoices two;
  final CustomTime custom;

  /// The game against the computer these choices start, with you playing
  /// [colour] — random already resolved by the screen.
  GameSetup computerSetup(Colour colour) => (
    mode: GameKind.vsComputer,
    strength: computer.step,
    colour: colour,
    timeControl: computer.time.toTimeControl(custom.minutes, custom.increment),
    rotate: false,
  );

  /// The two-player game these choices start.
  GameSetup twoPlayerSetup({bool rotate = false}) => (
    mode: GameKind.twoPlayers,
    strength: null,
    colour: null,
    timeControl: two.time.toTimeControl(custom.minutes, custom.increment),
    rotate: rotate,
  );

  SetupChoices copyWith({
    ComputerChoices? computer,
    TwoPlayerChoices? two,
    CustomTime? custom,
  }) => SetupChoices(
    computer: computer ?? this.computer,
    two: two ?? this.two,
    custom: custom ?? this.custom,
  );

  @override
  bool operator ==(Object other) =>
      other is SetupChoices &&
      other.computer == computer &&
      other.two == two &&
      other.custom == custom;

  @override
  int get hashCode => Object.hash(computer, two, custom);
}
