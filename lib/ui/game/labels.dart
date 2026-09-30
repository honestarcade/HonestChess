import 'package:honest_chess/engine/engine.dart';

/// The step's name as the design writes it: "Club".
extension StrengthLabel on Strength {
  String get label => '${name[0].toUpperCase()}${name.substring(1)}';
}

/// The declined-draw card's words, which TalkBack also speaks as the card
/// comes up: "Club declined the draw".
String declineText(Strength step) => '${step.label} declined the draw';

/// "White" or "Black".
extension ColourLabel on Colour {
  String get label => this == Colour.white ? 'White' : 'Black';
}

/// The time control as a panel's sub-line writes it: "RAPID 10+5",
/// "CUSTOM 15+10", "UNTIMED". A custom control that matches a preset's
/// values is that preset.
extension TimeControlLabel on TimeControl {
  String get label => switch (this) {
    Untimed() => 'UNTIMED',
    final Timed t =>
      '${t.preset?.name.toUpperCase() ?? 'CUSTOM'} '
          '${t.minutes}+${t.incrementSeconds}',
  };
}

/// The status chip's word for how a game ended. Every draw — agreed,
/// forced, or a resignation or flag against a side that could not mate —
/// reads DRAWN.
extension EndingWord on GameStatus {
  String? get endingWord => switch (this) {
    Ongoing() => null,
    Win(reason: GameEndReason.checkmate) => 'CHECKMATE',
    Win(reason: GameEndReason.flag) => 'FLAG FALL',
    Win() => 'RESIGNED',
    Draw(reason: GameEndReason.stalemate) => 'STALEMATE',
    Draw() => 'DRAWN',
  };
}

/// The milliseconds under which a clock shows tenths.
const int tenthsBelowMs = 10000;

/// The milliseconds under which a clock turns red.
const int lowTimeMs = 30000;

int _ceilDiv(int a, int b) => (a + b - 1) ~/ b;

/// A clock's text for [ms] remaining (null: untimed, "∞"). It rounds up,
/// so it reads 0:01 until the time is truly gone: m:ss, or m:ss.t in
/// tenths below [tenthsBelowMs].
String clockText(int? ms) {
  if (ms == null) return '∞';
  if (ms <= 0) return '0:00.0';
  if (ms < tenthsBelowMs) {
    final tenths = _ceilDiv(ms, 100);
    final seconds = tenths ~/ 10;
    return '0:${seconds.toString().padLeft(2, '0')}.${tenths % 10}';
  }
  final seconds = _ceilDiv(ms, 1000);
  return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
}

String _plural(int n, String unit) => '$n $unit${n == 1 ? '' : 's'}';

/// What a screen reader says for a clock: [who], then the time as the
/// clock rounds it — "You, 4 minutes 12 seconds", "White, 9.4 seconds",
/// "Club, no clock".
String clockSemantics(String who, int? ms) {
  if (ms == null) return '$who, no clock';
  if (ms <= 0) return '$who, 0 seconds';
  if (ms < tenthsBelowMs) {
    final tenths = _ceilDiv(ms, 100);
    return '$who, ${tenths ~/ 10}.${tenths % 10} seconds';
  }
  final seconds = _ceilDiv(ms, 1000);
  final minutes = seconds ~/ 60, rest = seconds % 60;
  return [
    '$who,',
    if (minutes > 0) _plural(minutes, 'minute'),
    if (rest > 0 || minutes == 0) _plural(rest, 'second'),
  ].join(' ');
}

/// The words [spokenCaps] keeps capitalised: the sides, the steps and the
/// names.
final Map<String, String> _properWords = {
  for (final colour in Colour.values) colour.label.toLowerCase(): colour.label,
  for (final step in Strength.values) step.name: step.label,
  'honest': 'Honest',
  'arcade': 'Arcade',
  'chess': 'Chess',
  'github': 'GitHub',
};

/// Upper-case display text as a screen reader should hear it: sentence
/// case, names kept ("Honest Arcade", "White", "Club"), and each " · "
/// read as a comma pause — "MOVE 12 · WHITE" → "Move 12, White". A line
/// opening with "vs" or a web address keeps it lower case. Text already
/// in mixed case keeps its case.
String spokenCaps(String text) {
  final pauses = text.split(' · ').join(', ');
  if (pauses.contains(RegExp('[a-z]'))) return pauses;
  final words = pauses
      .split(' ')
      .map((word) {
        final lower = word.toLowerCase();
        final bare = lower.replaceAll(RegExp(r'[^a-z]'), '');
        final proper = _properWords[bare];
        return proper == null ? lower : lower.replaceFirst(bare, proper);
      })
      .join(' ');
  if (words.isEmpty ||
      words.startsWith('vs ') ||
      words.split(' ').first.contains('.')) {
    return words;
  }
  return words[0].toUpperCase() + words.substring(1);
}
