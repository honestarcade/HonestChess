import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../engine/engine.dart';
import '../../feedback/clips.dart';
import '../../platform/platform_channel.dart';
import '../app_scope.dart';
import '../board/board_options.dart';
import '../board/board_view.dart';
import '../game/labels.dart';
import '../theme/palette.dart';
import '../widgets/option_button.dart';
import '../widgets/screen_header.dart';
import '../widgets/section_card.dart';
import '../widgets/setting_row.dart';
import '../widgets/setting_slider.dart';

/// The design's caption under Board colour.
const boardColourCaption = 'Four pairs from the Honest Arcade palette.';

/// The style samples' ink and shadow (`0 1px 2px rgba(0,0,0,.5)`).
const styleSampleInk = Color(0xFFF7F5EF);
const styleSampleShadow = [
  Shadow(color: Color(0x80000000), offset: Offset(0, 1), blurRadius: 2),
];

/// The widest screen the surface samples' stripes scale up to.
const surfaceScaleCapWidth = 480.0;

/// Takeback's description while a game is in progress: the game keeps the
/// rule it started with.
const takebackNextGame = 'Applies from your next game.';

/// The note's kicker and text: the design's, reworded to stay true under
/// Android's system backup.
const storedNoteKicker = 'STORED ON THIS PHONE';
const storedNoteText =
    'Games, statistics and settings are kept on this phone. No account, '
    'no sync, no server — the app sends nothing anywhere.';

/// The version line when the installed version cannot be read.
const versionUnavailable = 'Version unavailable';

/// The version line for [version]: `v<name> · BUILD <code>`, or
/// [versionUnavailable] when there is no version, its code is below 1 or
/// its name is blank.
String versionLine(AppVersion? version) {
  final name = version?.displayName;
  if (version == null || version.code < 1 || name == null) {
    return versionUnavailable;
  }
  return 'v$name · BUILD ${version.code}';
}

/// What a screen reader says for [versionLine]'s line: "Version 0.1.0,
/// build 1", or [versionUnavailable] as written.
String versionSpeech(AppVersion? version) {
  final line = versionLine(version);
  if (line == versionUnavailable) return line;
  return 'Version ${version!.displayName}, build ${version.code}';
}

/// One on/off row: [id] is its key's suffix, [read] and [write] its
/// `BoardOptions` field.
typedef _Toggle = ({
  String id,
  String group,
  String label,
  String description,
  bool Function(BoardOptions) read,
  BoardOptions Function(BoardOptions, bool) write,
});

/// The design's `SETTING_ROWS`.
final List<_Toggle> _toggles = [
  (
    id: 'dots',
    group: 'PLAY',
    label: 'Legal-move dots',
    description: 'Mark every square the selected piece can reach.',
    read: (o) => o.legalMoveDots,
    write: (o, v) => o.copyWith(legalMoveDots: v),
  ),
  (
    id: 'last-move',
    group: 'PLAY',
    label: 'Last-move highlight',
    description: 'Tint the two squares of the move just played.',
    read: (o) => o.lastMoveHighlight,
    write: (o, v) => o.copyWith(lastMoveHighlight: v),
  ),
  (
    id: 'takeback',
    group: 'PLAY',
    label: 'Takeback allowed',
    description: 'Undo the last move — both yours and the reply.',
    read: (o) => o.takebackAllowed,
    write: (o, v) => o.copyWith(takebackAllowed: v),
  ),
  (
    id: 'auto-queen',
    group: 'PLAY',
    label: 'Auto-promote to queen',
    description: 'Skip the promotion sheet and take a queen.',
    read: (o) => o.autoQueen,
    write: (o, v) => o.copyWith(autoQueen: v),
  ),
  (
    id: 'rotate',
    group: 'PLAY',
    label: 'Rotate board each turn',
    description: 'Two-player only. Faces the board at whoever moves.',
    read: (o) => o.rotateEachTurn,
    write: (o, v) => o.copyWith(rotateEachTurn: v),
  ),
  (
    id: 'anim',
    group: 'DISPLAY',
    label: 'Piece animations',
    description: 'Slide pieces to their square instead of jumping.',
    read: (o) => o.animations,
    write: (o, v) => o.copyWith(animations: v),
  ),
  (
    id: 'check-flag',
    group: 'DISPLAY',
    label: 'Flag check on the board',
    description: 'Redden the king square whenever it is in check.',
    read: (o) => o.flagCheck,
    write: (o, v) => o.copyWith(flagCheck: v),
  ),
  (
    id: 'sfx',
    group: 'SOUND',
    label: 'Sound effects',
    description: sfxDescription,
    read: (o) => o.sfx,
    write: (o, v) => o.copyWith(sfx: v),
  ),
  (
    id: 'music',
    group: 'SOUND',
    label: 'Background music',
    description: 'Quiet loop while you play.',
    read: (o) => o.music,
    write: (o, v) => o.copyWith(music: v),
  ),
  (
    id: 'haptics',
    group: 'SOUND',
    label: 'Haptics',
    description: 'A short tick on an illegal tap or a capture.',
    read: (o) => o.haptics,
    write: (o, v) => o.copyWith(haptics: v),
  ),
];

/// The computer's minimum turn: PLAY's one row that is not a switch
/// (#181), a slider over [minTurnChoices].
const minTurnRowLabel = "Computer's minimum turn";
const minTurnDescription =
    "The least time before the computer's move appears. Its moves stay the "
    'same.';

/// A minimum turn as its row shows it: "Off", "3 s".
String minTurnShown(int seconds) => seconds == 0 ? 'Off' : '$seconds s';

/// A minimum turn as a screen reader says it: "Off", "1 second",
/// "3 seconds".
String minTurnSpoken(int seconds) => switch (seconds) {
  0 => 'Off',
  1 => '1 second',
  _ => '$seconds seconds',
};

/// Sound effects' description, reworded from the design's to name what
/// plays: there is no separate piece tap or mate chime (#96).
const sfxDescription =
    'Moves, captures, castling, check and the end of a game.';

/// Settings: how the board looks, the switches it obeys, where the data
/// lives and which version this is. Every choice applies at once, except
/// takeback, which each game fixes at its start, and is kept by the app's
/// `SettingsStore`.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  /// Asked once per visit; null when Android could not say.
  Future<AppVersion?>? _version;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _version ??= AppScope.of(context).platform
        .appVersion()
        .then((version) => version, onError: (Object _) => null);
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final settings = scope.settings;
    final controller = scope.controller;
    return Scaffold(
      backgroundColor: Palette.screenBg,
      body: SafeArea(
        child: ListenableBuilder(
          listenable: Listenable.merge([settings.board, controller]),
          builder: (context, _) {
            final options = settings.board.value;
            void update(BoardOptions Function(BoardOptions) change) =>
                settings.updateBoard(change);
            // The controller's live game, from its start or restore until
            // it ends; a saved game sitting in its slot is not one.
            final inProgress = !controller.isIdle && !controller.game.isOver;
            final width = MediaQuery.sizeOf(context).width;
            final scale = math.min(width, surfaceScaleCapWidth) / designWidth;
            return ListView(
              key: const Key('settings-list'),
              // The design's 56 dp top padding, less its 44 dp status bar
              // (SafeArea's here).
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 30),
              children: [
                const ScreenHeader(title: 'Settings', keyPrefix: 'settings'),
                const SizedBox(height: 12),
                _Section(
                  title: 'Board colour',
                  caption: boardColourCaption,
                  children: [
                    for (final theme in BoardTheme.values)
                      OptionButton(
                        key: Key('settings-theme-${theme.name}'),
                        selected: options.theme == theme,
                        onPressed: () =>
                            update((o) => o.copyWith(theme: theme)),
                        padding: const EdgeInsets.all(9),
                        child: _Labelled(
                          label: theme.label,
                          labelSize: 9,
                          child: _Swatch(theme),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                _Section(
                  title: 'Piece style',
                  children: [
                    for (final style in PieceStyle.values)
                      OptionButton(
                        key: Key('settings-style-${style.name}'),
                        selected: options.pieceStyle == style,
                        onPressed: () =>
                            update((o) => o.copyWith(pieceStyle: style)),
                        padding: const EdgeInsets.symmetric(
                          vertical: 11,
                          horizontal: 8,
                        ),
                        look: OptionLook.settingsFilled,
                        child: _Labelled(
                          label: style.label,
                          labelSize: 9.5,
                          child: PieceGlyph(
                            piece: Piece.whiteKnight,
                            style: style,
                            fontSize: 22,
                            colour: styleSampleInk,
                            shadows: styleSampleShadow,
                            textKey: Key('settings-style-sample-${style.name}'),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                _Section(
                  title: 'Board surface',
                  children: [
                    for (final surface in BoardSurface.values)
                      OptionButton(
                        key: Key('settings-surface-${surface.name}'),
                        selected: options.surface == surface,
                        onPressed: () =>
                            update((o) => o.copyWith(surface: surface)),
                        padding: const EdgeInsets.all(9),
                        child: _Labelled(
                          label: surface.label,
                          labelSize: 9.5,
                          child: _SurfaceStrip(
                            surface: surface,
                            base: options.theme.dark,
                            scale: scale,
                          ),
                        ),
                      ),
                  ],
                ),
                for (final group in ['PLAY', 'DISPLAY', 'SOUND']) ...[
                  const SizedBox(height: 12),
                  _Group(
                    title: group,
                    rows: [
                      for (final t in _toggles.where((t) => t.group == group))
                        SettingRow(
                          key: Key('settings-toggle-${t.id}'),
                          label: t.label,
                          description: t.id == 'takeback' && inProgress
                              ? takebackNextGame
                              : t.description,
                          value: t.read(options),
                          onChanged: () {
                            final before = options;
                            update((o) => t.write(o, !t.read(o)));
                            final after = settings.board.value;
                            // Turning effects on plays a sample of them;
                            // turning haptics on ticks one.
                            if (!before.sfx && after.sfx) {
                              scope.sound.play(Clip.move);
                            }
                            if (!before.haptics && after.haptics) {
                              unawaited(scope.haptics.tick());
                            }
                          },
                        ),
                      if (group == 'PLAY')
                        SettingSlider(
                          key: const Key('settings-min-turn'),
                          id: 'settings-min-turn',
                          label: minTurnRowLabel,
                          description: minTurnDescription,
                          steps: minTurnChoices,
                          value: options.minTurnSeconds,
                          shown: minTurnShown,
                          spoken: minTurnSpoken,
                          onChanged: (seconds) => update(
                            (o) => o.copyWith(minTurnSeconds: seconds),
                          ),
                        ),
                    ],
                  ),
                ],
                const SizedBox(height: 12),
                const _StoredNote(),
                const SizedBox(height: 12),
                _VersionLine(_version!),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// A group of setting rows under its Plex Mono kicker, 8 dp apart.
class _Group extends StatelessWidget {
  const _Group({required this.title, required this.rows});

  final String title;
  final List<Widget> rows;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 3),
          child: Semantics(
            container: true,
            header: true,
            headingLevel: 2,
            child: Text(
              title,
              semanticsLabel: spokenCaps(title),
              style: const TextStyle(
                fontFamily: Fonts.plexMono,
                fontWeight: FontWeight.w500,
                fontSize: 9.5,
                height: 1,
                letterSpacing: 9.5 * .16,
                color: Palette.kicker,
              ),
            ),
          ),
        ),
        for (final row in rows) ...[const SizedBox(height: 8), row],
      ],
    );
  }
}

/// Where the data lives.
class _StoredNote extends StatelessWidget {
  const _StoredNote();

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      key: const Key('settings-note'),
      fill: Palette.optionFill,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            storedNoteKicker,
            semanticsLabel: spokenCaps(storedNoteKicker),
            style: const TextStyle(
              fontFamily: Fonts.plexMono,
              fontWeight: FontWeight.w500,
              fontSize: 9,
              height: 1,
              letterSpacing: 9 * .16,
              color: Palette.kicker,
            ),
          ),
          const SizedBox(height: 9),
          const Text(
            storedNoteText,
            style: TextStyle(
              fontFamily: Fonts.outfit,
              fontWeight: FontWeight.w400,
              fontSize: 11,
              height: 1.5,
              color: Palette.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}

/// The installed version in Plex Mono; empty, at its full height, until
/// Android answers.
class _VersionLine extends StatelessWidget {
  const _VersionLine(this.version);

  final Future<AppVersion?> version;

  static const _size = 9.5;
  static const _lineHeight = 1.6;

  @override
  Widget build(BuildContext context) {
    // One forced line height, so the empty line and the answered one are
    // the same height, and the box is the text's own at every text size.
    return FutureBuilder<AppVersion?>(
      future: version,
      builder: (context, snapshot) {
        final answered = snapshot.connectionState == ConnectionState.done;
        return Text(
          answered ? versionLine(snapshot.data) : '',
          key: const Key('settings-version'),
          semanticsLabel: answered ? versionSpeech(snapshot.data) : '',
          maxLines: 1,
          strutStyle: const StrutStyle(
            fontFamily: Fonts.plexMono,
            fontSize: _size,
            height: _lineHeight,
            forceStrutHeight: true,
          ),
          style: const TextStyle(
            fontFamily: Fonts.plexMono,
            fontWeight: FontWeight.w500,
            fontSize: _size,
            height: _lineHeight,
            letterSpacing: _size * .14,
            color: Palette.textFaint,
          ),
        );
      },
    );
  }
}

/// A Settings card: its title (a heading), an optional caption, and a row
/// of equal-width choices 9 dp apart.
class _Section extends StatelessWidget {
  const _Section({required this.title, this.caption, required this.children});

  final String title;
  final String? caption;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final caption = this.caption;
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            container: true,
            header: true,
            headingLevel: 2,
            child: Text(
              title,
              style: const TextStyle(
                fontFamily: Fonts.outfit,
                fontWeight: FontWeight.w600,
                fontSize: 13,
                height: 1,
                color: Color(0xFFFFFFFF),
              ),
            ),
          ),
          if (caption != null) ...[
            const SizedBox(height: 6),
            // Its own node, so a screen reader reads it after the
            // heading (#147).
            Semantics(
              container: true,
              child: Text(
                caption,
                style: const TextStyle(
                  fontFamily: Fonts.outfit,
                  fontWeight: FontWeight.w400,
                  fontSize: 10.5,
                  height: 1.35,
                  color: Palette.textMuted,
                ),
              ),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < children.length; i++) ...[
                if (i > 0) const SizedBox(width: 9),
                Expanded(child: children[i]),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// A choice's sample over its Plex Mono label, 8 dp apart; the label takes
/// its colour from the [OptionButton].
class _Labelled extends StatelessWidget {
  const _Labelled({
    required this.label,
    required this.labelSize,
    required this.child,
  });

  final String label;
  final double labelSize;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        child,
        const SizedBox(height: 8),
        Text(
          label,
          semanticsLabel: spokenCaps(label),
          maxLines: 1,
          overflow: TextOverflow.visible,
          softWrap: false,
          style: TextStyle(
            fontFamily: Fonts.plexMono,
            fontWeight: FontWeight.w500,
            fontSize: labelSize,
            height: 1,
          ),
        ),
      ],
    );
  }
}

/// A theme's 2×2 of 15 dp squares, light on the diagonal.
class _Swatch extends StatelessWidget {
  const _Swatch(this.theme);

  final BoardTheme theme;

  static const cell = 15.0;

  @override
  Widget build(BuildContext context) {
    Widget square(Color colour) => SizedBox.square(
      dimension: cell,
      child: ColoredBox(color: colour),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [square(theme.light), square(theme.dark)],
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [square(theme.dark), square(theme.light)],
          ),
        ],
      ),
    );
  }
}

/// A 26 dp strip of the theme's dark colour under [surface]'s pattern.
class _SurfaceStrip extends StatelessWidget {
  const _SurfaceStrip({
    required this.surface,
    required this.base,
    required this.scale,
  });

  final BoardSurface surface;
  final Color base;
  final double scale;

  @override
  Widget build(BuildContext context) {
    final pattern = surface.pattern;
    return ClipRRect(
      key: Key('settings-surface-strip-${surface.name}'),
      borderRadius: BorderRadius.circular(5),
      child: SizedBox(
        height: 26,
        width: double.infinity,
        child: ColoredBox(
          color: base,
          child: pattern == null
              ? null
              : CustomPaint(painter: SurfacePainter(pattern, scale)),
        ),
      ),
    );
  }
}
