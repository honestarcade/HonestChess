import 'package:flutter_test/flutter_test.dart';

import 'package:honest_chess/data/play_mode.dart';
import 'package:honest_chess/data/stats.dart';
import 'package:honest_chess/engine/engine.dart';
import 'package:honest_chess/ui/content/stats_view.dart';
import 'package:honest_chess/ui/format.dart';
import 'package:honest_chess/ui/theme/palette.dart';

StepStats _step(int won, int played) => StepStats(played: played, won: won);

/// The design's sample numbers, with a longest game and a custom clock.
const _computer = ComputerStats(
  played: 212,
  won: 96,
  drawn: 24,
  lost: 92,
  streak: 3,
  longestMoves: 86,
  steps: {
    Strength.beginner: StepStats(played: 42, won: 41),
    Strength.casual: StepStats(played: 48, won: 33),
    Strength.club: StepStats(played: 61, won: 18),
    Strength.strong: StepStats(played: 44, won: 4),
    Strength.master: StepStats(played: 17),
  },
);

const _two = TwoPlayerStats(
  played: 64,
  whiteWins: 30,
  blackWins: 27,
  drawn: 7,
  longestMoves: 1234,
  clocks: {
    StatsClock.untimed: 21,
    StatsClock.blitz: 19,
    StatsClock.rapid: 18,
    StatsClock.classical: 6,
    StatsClock.custom: 0,
  },
);

const _sample = StatsDocument(computer: _computer, two: _two);

Map<String, StatCard> _cards(StatsView view) => {
  for (final card in view.cards) card.name: card,
};

Map<String, StatRow> _rows(StatsView view) => {
  for (final row in view.rows) row.name: row,
};

void main() {
  group('format', () {
    test('counts group in threes with a comma, whatever the size', () {
      expect(formatCount(0), '0');
      expect(formatCount(999), '999');
      expect(formatCount(1000), '1,000');
      expect(formatCount(1234), '1,234');
      expect(formatCount(1234567), '1,234,567');
    });

    test('percentages round an exact half up, in integers', () {
      expect(percentHalfUp(1, 8), 13);
      expect(percentHalfUp(3, 8), 38);
      expect(percentHalfUp(1, 200), 1);
      expect(percentHalfUp(0, 17), 0);
      expect(percentHalfUp(17, 17), 100);
      expect(percentHalfUp(18, 61), 30);
      // Every n/d below 100: the exact rule, never a double's rounding.
      for (var d = 1; d <= 100; d++) {
        for (var n = 0; n <= d; n++) {
          final exact = 100 * n / d;
          final floor = (100 * n) ~/ d;
          final remainder2 = 2 * (100 * n - floor * d);
          expect(
            percentHalfUp(n, d),
            remainder2 >= d ? floor + 1 : floor,
            reason: '$n of $d = $exact%',
          );
        }
      }
    });
  });

  group('opening tab', () {
    test('the asked tab, else the mode played last, else vs Computer', () {
      expect(openingTab(PlayMode.two, PlayMode.computer), PlayMode.two);
      expect(openingTab(PlayMode.computer, PlayMode.two), PlayMode.computer);
      expect(openingTab(null, PlayMode.two), PlayMode.two);
      expect(openingTab(null, null), PlayMode.computer);
    });
  });

  group('empty', () {
    const empty = StatsDocument.empty();

    test('vs Computer: a dash in every card, nothing in any row', () {
      final view = statsView(empty, PlayMode.computer);
      expect(view.breakdownTitle, 'BY STRENGTH');
      expect(
        [for (final c in view.cards) c.name],
        [
          'games-played',
          'win-rate',
          'draws',
          'current-streak',
          'usual-level',
          'longest-game',
        ],
      );
      expect([for (final c in view.cards) c.value], everyElement('—'));
      expect(
        [for (final c in view.cards) c.caption],
        [
          'Since install',
          '— won',
          'Agreed or forced',
          'Consecutive wins',
          'Most games played',
          'Moves',
        ],
      );
      expect(
        [for (final r in view.rows) r.name],
        ['beginner', 'casual', 'club', 'strong', 'master'],
      );
      expect(
        [for (final r in view.rows) r.label],
        ['Beginner', 'Casual', 'Club', 'Strong', 'Master'],
      );
      expect([for (final r in view.rows) r.value], everyElement('0 / 0 · —'));
      expect([for (final r in view.rows) r.fraction], everyElement(0));
      expect(_rows(view)['club']!.spoken, 'Club, no games');
      expect(_cards(view)['win-rate']!.spoken, 'Win rate, no games');
      expect(
        _cards(view)['games-played']!.spoken,
        'Games played, no games, Since install',
      );
    });

    test('Two players: a dash in every card, "0 games" in every row', () {
      final view = statsView(empty, PlayMode.two);
      expect(view.breakdownTitle, 'BY TIME CONTROL');
      expect(
        [for (final c in view.cards) c.name],
        [
          'games-played',
          'white-wins',
          'black-wins',
          'draws',
          'usual-clock',
          'longest-game',
        ],
      );
      expect([for (final c in view.cards) c.value], everyElement('—'));
      expect(
        [for (final c in view.cards) c.caption],
        [
          'Since install',
          '—% of games',
          '—% of games',
          '—% of games',
          'Most games played',
          'Moves',
        ],
      );
      expect(
        [for (final r in view.rows) r.label],
        ['Untimed', 'Blitz 5+0', 'Rapid 10+5', 'Classical 30+0', 'Custom'],
      );
      expect([for (final r in view.rows) r.value], everyElement('0 games'));
      expect([for (final r in view.rows) r.fraction], everyElement(0));
      expect(_rows(view)['rapid']!.spoken, 'Rapid 10+5, no games');
      expect(_cards(view)['white-wins']!.spoken, 'White wins, no games');
    });

    test('no card is highlighted on Two players; only WIN RATE is on vs '
        'Computer', () {
      expect(
        [
          for (final c in statsView(empty, PlayMode.computer).cards)
            if (c.highlighted) c.name,
        ],
        ['win-rate'],
      );
      expect([
        for (final c in statsView(empty, PlayMode.two).cards)
          if (c.highlighted) c.name,
      ], isEmpty);
    });

    test('"Since reset" on both tabs once reset', () {
      final reset = const StatsDocument.empty().reset(1000);
      for (final mode in PlayMode.values) {
        expect(
          _cards(statsView(reset, mode))['games-played']!.caption,
          'Since reset',
        );
      }
    });
  });

  group('sample', () {
    test('vs Computer cards', () {
      final cards = _cards(statsView(_sample, PlayMode.computer));
      expect(cards['games-played']!.value, '212');
      expect(cards['win-rate']!.value, '45%');
      expect(cards['win-rate']!.caption, '96 won');
      expect(cards['win-rate']!.spoken, 'Win rate, 45%, 96 won');
      expect(cards['draws']!.value, '24');
      expect(cards['current-streak']!.value, '3');
      expect(cards['usual-level']!.value, 'Club');
      expect(cards['longest-game']!.value, '86');
    });

    test('BY STRENGTH rows: won / played · %, bar at the exact share', () {
      final view = statsView(_sample, PlayMode.computer);
      final rows = _rows(view);
      expect(rows['beginner']!.value, '41 / 42 · 98%');
      expect(rows['casual']!.value, '33 / 48 · 69%');
      expect(rows['club']!.value, '18 / 61 · 30%');
      expect(rows['club']!.spoken, 'Club, 18 won of 61, 30%');
      expect(rows['strong']!.value, '4 / 44 · 9%');
      expect(rows['master']!.value, '0 / 17 · 0%');
      expect(rows['beginner']!.fraction, closeTo(41 / 42, 1e-9));
      expect(rows['club']!.fraction, closeTo(18 / 61, 1e-9));
      expect(rows['strong']!.fraction, closeTo(4 / 44, 1e-9));
      // A 0% row with games still draws the sliver.
      expect(rows['master']!.fraction, closeTo(minBarFraction, 1e-9));
      expect(
        [for (final r in view.rows) r.colour],
        [
          Palette.teal,
          Palette.brandBlue,
          Palette.violet,
          Palette.skyBlue,
          Palette.barRed,
        ],
      );
      expect(
        [for (final c in barColours) c.toARGB32()],
        [0xFF00D6B4, 0xFF0076F1, 0xFF8448FC, 0xFF7DB9FF, 0xFFC6483D],
      );
    });

    test('Two players cards: shares of games played, thousands grouped', () {
      final cards = _cards(statsView(_sample, PlayMode.two));
      expect(cards['games-played']!.value, '64');
      expect(cards['white-wins']!.value, '30');
      expect(cards['white-wins']!.caption, '47% of games');
      expect(cards['black-wins']!.value, '27');
      expect(cards['black-wins']!.caption, '42% of games');
      expect(cards['draws']!.value, '7');
      expect(cards['draws']!.caption, '11% of games');
      expect(cards['usual-clock']!.value, 'Untimed');
      expect(cards['longest-game']!.value, '1,234');
      expect(cards['longest-game']!.spoken, 'Longest game, 1,234, Moves');
    });

    test('BY TIME CONTROL rows: games, bar at the share of all five', () {
      final rows = _rows(statsView(_sample, PlayMode.two));
      expect(rows['untimed']!.value, '21 games');
      expect(rows['rapid']!.spoken, 'Rapid 10+5, 18 games');
      expect(rows['custom']!.value, '0 games');
      expect(rows['untimed']!.fraction, closeTo(21 / 64, 1e-9));
      expect(rows['classical']!.fraction, closeTo(6 / 64, 1e-9));
      expect(rows['custom']!.fraction, 0);
    });

    test('one game is "1 game"; a tiny share draws the sliver', () {
      final doc = StatsDocument(
        two: TwoPlayerStats(
          played: 201,
          whiteWins: 201,
          clocks: {
            for (final c in StatsClock.values) c: 0,
            StatsClock.untimed: 200,
            StatsClock.custom: 1,
          },
        ),
      );
      final rows = _rows(statsView(doc, PlayMode.two));
      expect(rows['custom']!.value, '1 game');
      expect(rows['custom']!.spoken, 'Custom, 1 game');
      expect(rows['custom']!.fraction, closeTo(minBarFraction, 1e-9));
      expect(rows['untimed']!.fraction, closeTo(200 / 201, 1e-9));
    });

    test('clock shares add to 1 even when games played disagrees', () {
      final doc = StatsDocument(
        two: TwoPlayerStats(
          played: 100,
          clocks: {
            StatsClock.untimed: 10,
            StatsClock.blitz: 20,
            StatsClock.rapid: 30,
            StatsClock.classical: 4,
            StatsClock.custom: 0,
          },
        ),
      );
      final rows = statsView(doc, PlayMode.two).rows;
      expect(rows.fold(0.0, (sum, r) => sum + r.fraction), closeTo(1, 1e-9));
    });
  });

  group('usual', () {
    test('a tie goes to the stronger step', () {
      final doc = StatsDocument(
        computer: ComputerStats(
          played: 10,
          steps: {
            for (final s in Strength.values) s: const StepStats(),
            Strength.casual: _step(0, 5),
            Strength.strong: _step(0, 5),
          },
        ),
      );
      expect(
        _cards(statsView(doc, PlayMode.computer))['usual-level']!.value,
        'Strong',
      );
    });

    test('a clock tie goes to the later row; custom reads "Custom"', () {
      final doc = StatsDocument(
        two: TwoPlayerStats(
          played: 6,
          clocks: {
            for (final c in StatsClock.values) c: 0,
            StatsClock.blitz: 3,
            StatsClock.custom: 3,
          },
        ),
      );
      expect(
        _cards(statsView(doc, PlayMode.two))['usual-clock']!.value,
        'Custom',
      );
    });

    test('no games at any step or clock: a dash', () {
      const doc = StatsDocument(
        computer: ComputerStats(played: 3),
        two: TwoPlayerStats(played: 3),
      );
      expect(
        _cards(statsView(doc, PlayMode.computer))['usual-level']!.value,
        '—',
      );
      expect(_cards(statsView(doc, PlayMode.two))['usual-clock']!.value, '—');
    });
  });

  test('White, Black and draw shares add to 100, give or take rounding', () {
    for (var played = 1; played <= 40; played++) {
      for (var white = 0; white <= played; white++) {
        for (var black = 0; white + black <= played; black++) {
          final drawn = played - white - black;
          final doc = StatsDocument(
            two: TwoPlayerStats(
              played: played,
              whiteWins: white,
              blackWins: black,
              drawn: drawn,
            ),
          );
          final cards = _cards(statsView(doc, PlayMode.two));
          int share(String name) =>
              int.parse(cards[name]!.caption.split('%').first);
          final sum =
              share('white-wins') + share('black-wins') + share('draws');
          expect(
            (sum - 100).abs(),
            lessThanOrEqualTo(1),
            reason: '$white/$black/$drawn of $played',
          );
        }
      }
    }
  });
}
