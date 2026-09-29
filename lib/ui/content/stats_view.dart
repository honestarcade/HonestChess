import 'dart:ui' show Color;

import 'package:flutter/foundation.dart';

import '../../data/play_mode.dart';
import '../../data/stats.dart';
import '../../engine/engine.dart';
import '../format.dart';
import '../game/defaults.dart';
import '../game/labels.dart';
import '../theme/palette.dart';
import '../widgets/time_control_picker.dart';

/// What every card and bar shows in place of a number with no games behind
/// it.
const noValue = '—';

/// The screen's title, its tabs, its two breakdown titles and its reset
/// texts.
const statsTitle = 'Statistics';
const computerTabLabel = 'vs Computer';
const twoTabLabel = 'Two players';
const byStrengthTitle = 'BY STRENGTH';
const byClockTitle = 'BY TIME CONTROL';
const resetButtonText = 'Reset statistics';
const resetTitle = 'Reset statistics?';

/// The confirmation's body, reworded from the design's so it stays true
/// when Android's own backup holds a copy of the app's files.
const resetBody =
    'Clears every recorded game, streak and result for both the computer '
    'and pass-and-play. Nothing was ever uploaded by this app, so it keeps '
    'no other copy.';
const resetCancelText = 'Cancel';
const resetConfirmText = 'Reset';
const resetFailedText = 'Couldn\'t reset — try again';
const resetDoneText = 'Statistics reset';

/// The scrim's spoken label: tapping it cancels.
const resetScrimLabel = 'Cancel reset';

/// The narrowest bar a row with games draws, as a share of its track: the
/// design's Master row, 0 wins, still shows a sliver.
const minBarFraction = 0.02;

/// The bars' colours, by row position, in the design's order.
const barColours = <Color>[
  Palette.teal,
  Palette.brandBlue,
  Palette.violet,
  Palette.skyBlue,
  Palette.barRed,
];

/// One card of the two-column grid.
@immutable
final class StatCard {
  const StatCard({
    required this.name,
    required this.kicker,
    required this.value,
    required this.caption,
    required this.highlighted,
    required this.spoken,
  });

  /// The key suffix: the kicker kebab-cased (`win-rate`).
  final String name;
  final String kicker;
  final String value;
  final String caption;

  /// Drawn in teal on a teal wash: vs Computer's WIN RATE.
  final bool highlighted;

  /// The card's one screen-reader label.
  final String spoken;
}

/// One breakdown row: a strength step or a time control.
@immutable
final class StatRow {
  const StatRow({
    required this.name,
    required this.label,
    required this.value,
    required this.fraction,
    required this.colour,
    required this.spoken,
  });

  /// The key suffix: the step's or the control's enum name.
  final String name;
  final String label;
  final String value;

  /// How much of the track the bar fills, 0 to 1: the exact share, raised
  /// to [minBarFraction] for a row with games; 0 for a row with none.
  final double fraction;
  final Color colour;
  final String spoken;
}

/// Everything one tab shows.
@immutable
final class StatsView {
  const StatsView({
    required this.cards,
    required this.breakdownTitle,
    required this.rows,
  });

  final List<StatCard> cards;
  final String breakdownTitle;
  final List<StatRow> rows;
}

/// The tab Statistics opens on: the one asked for, else the mode played
/// last, else vs Computer.
PlayMode openingTab(PlayMode? openOn, PlayMode? lastPlayed) =>
    openOn ?? lastPlayed ?? PlayMode.computer;

/// [document]'s numbers for [mode]'s tab.
StatsView statsView(StatsDocument document, PlayMode mode) {
  final since = document.resetAt == null ? 'Since install' : 'Since reset';
  return switch (mode) {
    PlayMode.computer => _computer(document.computer, since),
    PlayMode.two => _two(document.two, since),
  };
}

StatsView _computer(ComputerStats stats, String since) {
  final played = stats.played;
  final none = played == 0;
  String count(int n) => none ? noValue : formatCount(n);
  Strength? usual;
  for (final step in Strength.values) {
    final games = stats.steps[step]!.played;
    // `>=`: a tie goes to the stronger step, which comes later.
    if (games > 0 &&
        games >= (usual == null ? 0 : stats.steps[usual]!.played)) {
      usual = step;
    }
  }
  return StatsView(
    cards: [
      _card('GAMES PLAYED', count(played), since),
      _card(
        'WIN RATE',
        none ? noValue : '${percentHalfUp(stats.won, played)}%',
        '${count(stats.won)} won',
        highlighted: true,
      ),
      _card('DRAWS', count(stats.drawn), 'Agreed or forced'),
      _card('CURRENT STREAK', count(stats.streak), 'Consecutive wins'),
      _card('USUAL LEVEL', usual?.label ?? noValue, 'Most games played'),
      _card('LONGEST GAME', count(stats.longestMoves), 'Moves'),
    ],
    breakdownTitle: byStrengthTitle,
    rows: [
      for (final (i, step) in Strength.values.indexed)
        _stepRow(i, step, stats.steps[step]!),
    ],
  );
}

StatsView _two(TwoPlayerStats stats, String since) {
  final played = stats.played;
  final none = played == 0;
  String count(int n) => none ? noValue : formatCount(n);
  String share(int n) =>
      '${none ? noValue : percentHalfUp(n, played)}% of games';
  StatsClock? usual;
  for (final clock in StatsClock.values) {
    final games = stats.clocks[clock]!;
    // `>=`: a tie goes to the later row.
    if (games > 0 && games >= (usual == null ? 0 : stats.clocks[usual]!)) {
      usual = clock;
    }
  }
  final total = StatsClock.values.fold(0, (sum, c) => sum + stats.clocks[c]!);
  return StatsView(
    cards: [
      _card('GAMES PLAYED', count(played), since),
      _card('WHITE WINS', count(stats.whiteWins), share(stats.whiteWins)),
      _card('BLACK WINS', count(stats.blackWins), share(stats.blackWins)),
      _card('DRAWS', count(stats.drawn), share(stats.drawn)),
      _card(
        'USUAL CLOCK',
        usual == null ? noValue : clockLabel(usual),
        'Most games played',
      ),
      _card('LONGEST GAME', count(stats.longestMoves), 'Moves'),
    ],
    breakdownTitle: byClockTitle,
    rows: [
      for (final (i, clock) in StatsClock.values.indexed)
        _clockRow(i, clock, stats.clocks[clock]!, total),
    ],
  );
}

/// A time control's name as the rows and USUAL CLOCK show it: the setup
/// screens' names, "Custom" for every custom control.
String clockLabel(StatsClock clock) =>
    TimeChoice.values.byName(clock.name).label;

StatCard _card(
  String kicker,
  String value,
  String caption, {
  bool highlighted = false,
}) {
  final spokenCaption = caption.contains(noValue) ? null : caption;
  return StatCard(
    name: kicker.toLowerCase().replaceAll(' ', '-'),
    kicker: kicker,
    value: value,
    caption: caption,
    highlighted: highlighted,
    spoken: [
      _sentenceCase(kicker),
      value == noValue ? 'no games' : value,
      ?spokenCaption,
    ].join(', '),
  );
}

StatRow _stepRow(int index, Strength step, StepStats stats) {
  final played = stats.played;
  if (played == 0) {
    return StatRow(
      name: step.name,
      label: step.label,
      value: '0 / 0 · $noValue',
      fraction: 0,
      colour: barColours[index],
      spoken: '${step.label}, no games',
    );
  }
  final won = formatCount(stats.won);
  final games = formatCount(played);
  final percent = '${percentHalfUp(stats.won, played)}%';
  return StatRow(
    name: step.name,
    label: step.label,
    value: '$won / $games · $percent',
    fraction: _bar(stats.won / played),
    colour: barColours[index],
    spoken: '${step.label}, $won won of $games, $percent',
  );
}

StatRow _clockRow(int index, StatsClock clock, int games, int total) {
  final label = clockLabel(clock);
  final value = '${formatCount(games)} ${games == 1 ? 'game' : 'games'}';
  return StatRow(
    name: clock.name,
    label: label,
    value: value,
    fraction: games == 0 ? 0 : _bar(games / total),
    colour: barColours[index],
    spoken: games == 0 ? '$label, no games' : '$label, $value',
  );
}

double _bar(double share) => share < minBarFraction ? minBarFraction : share;

String _sentenceCase(String kicker) =>
    '${kicker[0]}${kicker.substring(1).toLowerCase()}';
