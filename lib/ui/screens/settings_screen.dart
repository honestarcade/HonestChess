import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../engine/engine.dart';
import '../app_scope.dart';
import '../board/board_options.dart';
import '../board/board_view.dart';
import '../theme/palette.dart';
import '../widgets/option_button.dart';
import '../widgets/screen_header.dart';
import '../widgets/section_card.dart';

/// The design's caption under Board colour.
const boardColourCaption = 'Four pairs from the Honest Arcade palette.';

/// The style samples' ink and shadow (`0 1px 2px rgba(0,0,0,.5)`).
const styleSampleInk = Color(0xFFF7F5EF);
const styleSampleShadow = [
  Shadow(color: Color(0x80000000), offset: Offset(0, 1), blurRadius: 2),
];

/// The widest screen the surface samples' stripes scale up to.
const surfaceScaleCapWidth = 480.0;

/// Settings: how the board looks. Every choice applies at once and is kept
/// by the app's `SettingsStore`.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = AppScope.of(context).settings;
    return Scaffold(
      backgroundColor: Palette.navy,
      body: SafeArea(
        child: ValueListenableBuilder<BoardOptions>(
          valueListenable: settings.board,
          builder: (context, options, _) {
            void update(BoardOptions Function(BoardOptions) change) =>
                settings.updateBoard(change);
            final width = MediaQuery.sizeOf(context).width;
            final scale = math.min(width, surfaceScaleCapWidth) / designWidth;
            return ListView(
              key: const Key('settings-list'),
              // The design's 56 dp top padding, less its 44 dp status bar
              // (SafeArea's here).
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 30),
              children: [
                const ScreenHeader(title: 'Settings'),
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
              ],
            );
          },
        ),
      ),
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
            header: true,
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
            Text(
              caption,
              style: const TextStyle(
                fontFamily: Fonts.outfit,
                fontWeight: FontWeight.w400,
                fontSize: 10.5,
                height: 1.35,
                color: Palette.textMuted,
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
