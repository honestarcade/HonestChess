import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import '../theme/contrast.dart';

/// The four square colour pairs of the design's `THEMES`, with the
/// coordinate labels drawn on each: the design's rgba(0,0,0,.42) on a light
/// square and rgba(255,255,255,.5) on a dark one, each made just opaque
/// enough to read on its theme's square, and bone's dark square darkened
/// to hold the brand sheet's 4:1 (#99; `Palette.shifts` has the design
/// values).
enum BoardTheme {
  navy(
    light: Color(0xFFDCE9F8),
    dark: Color(0xFF0F3E86),
    labelOnLight: Color(0x8D000000),
    labelOnDark: Color(0x95FFFFFF),
    marksOnDark: (
      selectedRing: Color(0xFF41F1CD),
      lastMoveMark: Color(0xB3FFFFFF),
      moveDot: Color(0x9E76FFDF),
      captureRing: Color(0x999FFFE6),
    ),
  ),
  teal(
    light: Color(0xFFD6F0EB),
    dark: Color(0xFF0B615A),
    labelOnLight: Color(0x8D000000),
    labelOnDark: Color(0xB6FFFFFF),
    marksOnDark: (
      selectedRing: Color(0xFF92FFE4),
      lastMoveMark: Color(0xB3FFFFFF),
      moveDot: Color(0xAAFDFFFE),
      captureRing: Color(0xAAFDFFFE),
    ),
  ),
  violet(
    light: Color(0xFFE4DAFB),
    dark: Color(0xFF3B2076),
    labelOnLight: Color(0x8F000000),
    labelOnDark: Color(0x86FFFFFF),
    marksOnDark: (
      selectedRing: Color(0xFF1DDDBB),
      lastMoveMark: Color(0xB3FFFFFF),
      moveDot: Color(0x9E39EBC8),
      captureRing: Color(0x993FEFCC),
    ),
  ),
  bone(
    light: Color(0xFFF1EFE7),
    dark: Color(0xFF6A7586),
    labelOnLight: Color(0x8C000000),
    labelOnDark: Color(0xFBFFFFFF),
    marksOnDark: (
      selectedRing: Color(0xFF00473B),
      lastMoveMark: Color(0xD5FFFFFF),
      moveDot: Color(0xD6FBFFFE),
      captureRing: Color(0xD6FBFFFE),
    ),
  );

  const BoardTheme({
    required this.light,
    required this.dark,
    required this.labelOnLight,
    required this.labelOnDark,
    required this.marksOnDark,
  });

  final Color light;
  final Color dark;

  /// A coordinate label on a [light] square, and on a [dark] one.
  final Color labelOnLight;
  final Color labelOnDark;

  /// The inks of the board's marks on a [dark] square: each design ink
  /// (`Palette.selectedRing`, `lastMoveMark`, `moveDot`, `captureRing`)
  /// moved by `lightenMark` just far enough to show 3:1 on this theme's
  /// dark square under the tints it sits on (#151), bare or under a band
  /// of either surface's stripes (#157).
  /// test/ui/board_shapes_test.dart re-derives each one.
  final MarkInks marksOnDark;

  /// The coordinate label drawn on a light square when [onLight], else on
  /// a dark one, over the translucent [tint] a highlight lays there
  /// (#149). On a plain square it is the theme's own ink for that square.
  /// Over a tint it is whichever of the two inks, [labelOnLight]'s black or
  /// [labelOnDark]'s white, reads better there when opaque, made just
  /// opaque enough to reach [normalTextRatio]. Throws a [StateError] when
  /// neither ink reaches it even opaque, the case the owner gave a backing.
  Color labelInk({
    required bool onLight,
    Color tint = const Color(0x00000000),
  }) {
    final own = onLight ? labelOnLight : labelOnDark;
    if (tint.a == 0) return own;
    final ground = composite(tint, onLight ? light : dark);
    double opaque(Color ink) => contrastRatio(ink.withValues(alpha: 1), ground);
    final ink = opaque(labelOnLight) >= opaque(labelOnDark)
        ? labelOnLight
        : labelOnDark;
    return raiseAlpha(ink, [
      (background: ground, minRatio: normalTextRatio, opacity: 1),
    ]);
  }

  /// The name Settings shows: NAVY, CLASSIC, FELT….
  String get label => name.toUpperCase();
}

/// A board theme's inks for the marks drawn on one square colour.
typedef MarkInks = ({
  Color selectedRing,
  Color lastMoveMark,
  Color moveDot,
  Color captureRing,
});

/// The design's three piece styles (`GLYPH`).
enum PieceStyle {
  /// The filled chess symbols, for both colours.
  classic,

  /// The hollow chess symbols, for both colours.
  outline,

  /// Upper-case letters in the monospaced face, for both colours.
  flat;

  /// The name Settings shows: NAVY, CLASSIC, FELT….
  String get label => name.toUpperCase();
}

/// One band of a repeating stripe pattern: [width] design px of [colour].
final class StripeBand {
  const StripeBand(this.colour, this.width);

  final Color colour;
  final double width;
}

/// A CSS `repeating-linear-gradient` with hard stops: [bands] repeat along
/// the gradient line, which points [angleDegrees] clockwise from "up".
final class StripePattern {
  const StripePattern(this.angleDegrees, this.bands);

  final double angleDegrees;
  final List<StripeBand> bands;

  /// One repeat, in design px.
  double get period => bands.fold(0, (sum, b) => sum + b.width);
}

/// The design's three board surfaces (`TEX`), drawn over the squares.
enum BoardSurface {
  plain(null),

  /// `repeating-linear-gradient(45deg, rgba(255,255,255,.05) 0 1px,
  /// rgba(0,0,0,.03) 1px 4px)`.
  felt(
    StripePattern(45, [
      StripeBand(Color(0x0DFFFFFF), 1),
      StripeBand(Color(0x08000000), 3),
    ]),
  ),

  /// `repeating-linear-gradient(87deg, rgba(0,0,0,.09) 0 2px,
  /// rgba(255,255,255,.05) 2px 7px)`.
  wood(
    StripePattern(87, [
      StripeBand(Color(0x17000000), 2),
      StripeBand(Color(0x0DFFFFFF), 5),
    ]),
  );

  const BoardSurface(this.pattern);

  /// Null for [plain], which draws nothing over the squares.
  final StripePattern? pattern;

  /// The name Settings shows: NAVY, CLASSIC, FELT….
  String get label => name.toUpperCase();
}

/// How the board looks and behaves: the design's Settings rows that touch
/// the board, edited in Settings and kept by `SettingsStore`
/// (lib/data/settings_store.dart), which holds its codec so this class
/// stays free of persistence.
@immutable
final class BoardOptions {
  const BoardOptions({
    this.theme = BoardTheme.navy,
    this.pieceStyle = PieceStyle.classic,
    this.surface = BoardSurface.felt,
    this.legalMoveDots = true,
    this.lastMoveHighlight = true,
    this.takebackAllowed = true,
    this.autoQueen = false,
    this.rotateEachTurn = false,
    this.animations = true,
    this.sfx = true,
    this.music = false,
    this.haptics = true,
    this.flagCheck = true,
  });

  final BoardTheme theme;
  final PieceStyle pieceStyle;
  final BoardSurface surface;

  /// Mark every square the selected piece can reach.
  final bool legalMoveDots;

  /// Tint the two squares of the move just played.
  final bool lastMoveHighlight;

  /// New games allow takeback (the game fixes it at its start).
  final bool takebackAllowed;

  /// Skip the promotion sheet and take a queen.
  final bool autoQueen;

  /// Two-player only: turn the board to face whoever moves.
  final bool rotateEachTurn;

  /// Slide pieces to their square instead of jumping.
  final bool animations;

  /// Play a sound for each move and for the end of a game.
  final bool sfx;

  /// Play the quiet loop while a game is live on the board.
  final bool music;

  /// A short tick on an illegal tap or drop and on a capture.
  final bool haptics;

  /// Redden the king's square whenever it is in check.
  final bool flagCheck;

  BoardOptions copyWith({
    BoardTheme? theme,
    PieceStyle? pieceStyle,
    BoardSurface? surface,
    bool? legalMoveDots,
    bool? lastMoveHighlight,
    bool? takebackAllowed,
    bool? autoQueen,
    bool? rotateEachTurn,
    bool? animations,
    bool? sfx,
    bool? music,
    bool? haptics,
    bool? flagCheck,
  }) => BoardOptions(
    theme: theme ?? this.theme,
    pieceStyle: pieceStyle ?? this.pieceStyle,
    surface: surface ?? this.surface,
    legalMoveDots: legalMoveDots ?? this.legalMoveDots,
    lastMoveHighlight: lastMoveHighlight ?? this.lastMoveHighlight,
    takebackAllowed: takebackAllowed ?? this.takebackAllowed,
    autoQueen: autoQueen ?? this.autoQueen,
    rotateEachTurn: rotateEachTurn ?? this.rotateEachTurn,
    animations: animations ?? this.animations,
    sfx: sfx ?? this.sfx,
    music: music ?? this.music,
    haptics: haptics ?? this.haptics,
    flagCheck: flagCheck ?? this.flagCheck,
  );

  @override
  bool operator ==(Object other) =>
      other is BoardOptions &&
      other.theme == theme &&
      other.pieceStyle == pieceStyle &&
      other.surface == surface &&
      other.legalMoveDots == legalMoveDots &&
      other.lastMoveHighlight == lastMoveHighlight &&
      other.takebackAllowed == takebackAllowed &&
      other.autoQueen == autoQueen &&
      other.rotateEachTurn == rotateEachTurn &&
      other.animations == animations &&
      other.sfx == sfx &&
      other.music == music &&
      other.haptics == haptics &&
      other.flagCheck == flagCheck;

  @override
  int get hashCode => Object.hash(
    theme,
    pieceStyle,
    surface,
    legalMoveDots,
    lastMoveHighlight,
    takebackAllowed,
    autoQueen,
    rotateEachTurn,
    animations,
    sfx,
    music,
    haptics,
    flagCheck,
  );
}
