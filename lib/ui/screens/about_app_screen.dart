import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../board/board_view.dart' show designWidth;
import '../brand/honest_mark.dart';
import '../brand/links.dart';
import '../content/about_content.dart';
import '../theme/palette.dart';
import '../widgets/external_link.dart';
import '../widgets/screen_header.dart';
import 'about_arcade_screen.dart';

/// The version line's text when no version name is known: the design's
/// "3.6 MB" is left out, since no fixed size would stay true.
const offlineText = 'OFFLINE';

/// The smallest height a tappable takes.
const _minTouch = 48.0;

/// About the App: what Honest Chess is, what's in it, the Honest promises
/// at a glance, and links to the studio and this app's source.
class AboutAppScreen extends StatefulWidget {
  const AboutAppScreen({super.key});

  /// The route the menu pushes.
  static Route<void> route() =>
      MaterialPageRoute<void>(builder: (_) => const AboutAppScreen());

  @override
  State<AboutAppScreen> createState() => _AboutAppScreenState();
}

class _AboutAppScreenState extends State<AboutAppScreen> {
  /// The installed version's display name, asked once per visit; null when
  /// it cannot be read.
  Future<String?>? _versionName;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final platform = AppScope.of(context).platform;
    _versionName ??= Future.sync(platform.appVersion)
        .then((version) => version?.displayName, onError: (Object _) => null);
  }

  @override
  Widget build(BuildContext context) {
    // Screen text ignores the system text scale, as the board does, until
    // M5's accessibility work.
    return MediaQuery.withNoTextScaling(
      child: Scaffold(
        backgroundColor: Palette.screenBg,
        resizeToAvoidBottomInset: false,
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final s =
                  math.min(constraints.maxWidth, aboutScaleCapWidth) /
                  designWidth;
              final gap = 13 * s;
              // The links' 48 dp touch height is centred on their line
              // (9.5 × 1.7), eating into the gap above and the padding
              // below so the drawn spacing stays the design's.
              final linkLine = 9.5 * 1.7 * s;
              final linkSpill = math.max(0.0, (_minTouch - linkLine) / 2);
              return SingleChildScrollView(
                key: const Key('aboutapp-scroll'),
                // The design's 56 dp top padding, less its 44 dp status bar
                // (SafeArea's here).
                padding: EdgeInsets.fromLTRB(
                  20 * s,
                  12,
                  20 * s,
                  math.max(0.0, 30 * s - linkSpill),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const ScreenHeader(
                      title: aboutAppTitle,
                      keyPrefix: 'aboutapp',
                    ),
                    SizedBox(height: gap),
                    _AppCard(scale: s, versionName: _versionName!),
                    SizedBox(height: gap),
                    Text(
                      appDescription,
                      key: const Key('aboutapp-description'),
                      style: _font(
                        Fonts.outfit,
                        FontWeight.w400,
                        13.5,
                        1.65,
                        Palette.textLead,
                        s,
                      ),
                    ),
                    SizedBox(height: gap),
                    _Features(scale: s),
                    SizedBox(height: gap),
                    _PromisesPanel(scale: s),
                    SizedBox(height: math.max(0.0, gap - linkSpill)),
                    _MadeBy(scale: s, height: linkLine + 2 * linkSpill),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// A CSS `font: <weight> <size>/<line-height>` at [scale], with CSS's
/// half-leading so the line boxes match the design's; a null [lineHeight]
/// is the font's own content height.
TextStyle _font(
  String family,
  FontWeight weight,
  double size,
  double? lineHeight,
  Color colour,
  double scale, {
  double letterSpacingEm = 0,
}) => TextStyle(
  fontFamily: family,
  fontWeight: weight,
  fontSize: size * scale,
  height: lineHeight,
  leadingDistribution: lineHeight == null ? null : TextLeadingDistribution.even,
  letterSpacing: letterSpacingEm * size * scale,
  color: colour,
);

/// The design's section kicker: Plex Mono, spaced, read as a header.
Widget _kicker(String text, Color colour, double size, double s, Key key) =>
    Semantics(
      header: true,
      child: Text(
        text,
        key: key,
        style: _font(
          Fonts.plexMono,
          FontWeight.w500,
          size,
          1,
          colour,
          s,
          letterSpacingEm: .16,
        ),
      ),
    );

class _AppCard extends StatelessWidget {
  const _AppCard({required this.scale, required this.versionName});

  final double scale;
  final Future<String?> versionName;

  @override
  Widget build(BuildContext context) {
    final s = scale;
    return Container(
      key: const Key('aboutapp-card'),
      padding: EdgeInsets.all(16 * s),
      decoration: BoxDecoration(
        color: Palette.cardFill,
        borderRadius: BorderRadius.circular(16 * s),
      ),
      child: Row(
        children: [
          Container(
            key: const Key('aboutapp-mark-tile'),
            width: 62 * s,
            height: 62 * s,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Palette.onTeal,
              borderRadius: BorderRadius.circular(15 * s),
            ),
            child: HonestMark.chess(48 * s, key: const Key('aboutapp-mark')),
          ),
          SizedBox(width: 14 * s),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Honest Chess',
                  key: const Key('aboutapp-name'),
                  style: _font(
                    Fonts.outfit,
                    FontWeight.w700,
                    20,
                    1,
                    const Color(0xFFFFFFFF),
                    s,
                  ),
                ),
                SizedBox(height: 7 * s),
                FutureBuilder<String?>(
                  future: versionName,
                  builder: (context, snapshot) {
                    final name = snapshot.data;
                    return Text(
                      name == null ? offlineText : 'v$name · $offlineText',
                      key: const Key('aboutapp-version'),
                      style: _font(
                        Fonts.plexMono,
                        FontWeight.w500,
                        10,
                        1,
                        Palette.textDim,
                        s,
                        letterSpacingEm: .14,
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Features extends StatelessWidget {
  const _Features({required this.scale});

  final double scale;

  @override
  Widget build(BuildContext context) {
    final s = scale;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _kicker(
          featuresKicker,
          Palette.kicker,
          9.5,
          s,
          const Key('aboutapp-features-kicker'),
        ),
        for (final feature in features) ...[
          SizedBox(height: 8 * s),
          MergeSemantics(
            child: Container(
              padding: EdgeInsets.symmetric(
                vertical: 11 * s,
                horizontal: 13 * s,
              ),
              decoration: BoxDecoration(
                color: Palette.cardFill,
                borderRadius: BorderRadius.circular(11 * s),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: EdgeInsets.only(top: 6 * s),
                    child: Container(
                      width: 6 * s,
                      height: 6 * s,
                      decoration: const BoxDecoration(
                        color: Palette.teal,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                  SizedBox(width: 10 * s),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          feature.title,
                          style: _font(
                            Fonts.outfit,
                            FontWeight.w600,
                            12,
                            1,
                            const Color(0xFFFFFFFF),
                            s,
                          ),
                        ),
                        SizedBox(height: 5 * s),
                        Text(
                          feature.body,
                          style: _font(
                            Fonts.outfit,
                            FontWeight.w400,
                            11,
                            1.4,
                            Palette.textBody,
                            s,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _PromisesPanel extends StatelessWidget {
  const _PromisesPanel({required this.scale});

  final double scale;

  @override
  Widget build(BuildContext context) {
    final s = scale;
    // The button's 48 dp touch height is centred on its drawn box, eating
    // into the gap above it and the panel's padding below.
    final buttonDrawn = (12 + 12.5 + 12) * s + 2;
    final buttonSpill = math.max(0.0, (_minTouch - buttonDrawn) / 2);
    final rows = <List<String>>[
      for (var i = 0; i < appPromiseChips.length; i += 2)
        appPromiseChips.sublist(i, math.min(i + 2, appPromiseChips.length)),
    ];
    return Container(
      key: const Key('aboutapp-promises-panel'),
      padding: EdgeInsets.fromLTRB(
        15 * s,
        14 * s,
        15 * s,
        math.max(0.0, 14 * s - buttonSpill),
      ),
      decoration: BoxDecoration(
        color: Palette.tealPanelFill,
        borderRadius: BorderRadius.circular(13 * s),
        // A Flutter border is drawn inside the box, as the design's inset
        // shadow ring is.
        border: Border.all(color: Palette.tealPanelRing),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _kicker(
            appPromisesKicker,
            Palette.teal,
            9,
            s,
            const Key('aboutapp-promises-kicker'),
          ),
          SizedBox(height: 11 * s),
          for (final (r, row) in rows.indexed) ...[
            if (r > 0) SizedBox(height: 7 * s),
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: _Chip(label: row[0], scale: s),
                  ),
                  SizedBox(width: 7 * s),
                  Expanded(
                    child: row.length > 1
                        ? _Chip(label: row[1], scale: s)
                        : const SizedBox.shrink(),
                  ),
                ],
              ),
            ),
          ],
          SizedBox(height: math.max(0.0, 14 * s - buttonSpill)),
          _PromisesButton(
            scale: s,
            drawnHeight: buttonDrawn,
            height: buttonDrawn + 2 * buttonSpill,
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.scale});

  final String label;
  final double scale;

  @override
  Widget build(BuildContext context) {
    final s = scale;
    return Container(
      padding: EdgeInsets.symmetric(vertical: 7 * s, horizontal: 10 * s),
      decoration: BoxDecoration(
        color: Palette.statusFill,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        children: [
          ExcludeSemantics(
            child: Text(
              '✓',
              style: _font(
                Fonts.outfit,
                FontWeight.w600,
                10,
                1,
                Palette.teal,
                s,
              ),
            ),
          ),
          SizedBox(width: 6 * s),
          Expanded(
            child: Text(
              label,
              style: _font(
                Fonts.plexMono,
                FontWeight.w500,
                10,
                1.2,
                Palette.textPale,
                s,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The design's outlined "Honest Arcade Promises" button: its border turns
/// full teal while pressed, and a tap opens About Honest Arcade through the
/// app's navigation guard, so a double tap opens it once.
class _PromisesButton extends StatefulWidget {
  const _PromisesButton({
    required this.scale,
    required this.drawnHeight,
    required this.height,
  });

  final double scale;
  final double drawnHeight;

  /// The touch height, the drawn box centred in it.
  final double height;

  @override
  State<_PromisesButton> createState() => _PromisesButtonState();
}

class _PromisesButtonState extends State<_PromisesButton> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed != value) setState(() => _pressed = value);
  }

  void _open() {
    final navigator = Navigator.of(context);
    unawaited(
      AppScope.of(context).navigation.run(() {
        unawaited(navigator.push(AboutArcadeScreen.route()));
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.scale;
    return Semantics(
      button: true,
      label: appPromisesButtonText,
      onTap: _open,
      excludeSemantics: true,
      child: Listener(
        onPointerDown: (_) => _setPressed(true),
        onPointerUp: (_) => _setPressed(false),
        onPointerCancel: (_) => _setPressed(false),
        child: GestureDetector(
          key: const Key('aboutapp-promises'),
          behavior: HitTestBehavior.opaque,
          onTap: _open,
          child: SizedBox(
            height: widget.height,
            child: Center(
              child: Container(
                key: const Key('aboutapp-promises-box'),
                height: widget.drawnHeight,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(11 * s),
                  border: Border.all(
                    color: _pressed ? Palette.teal : Palette.accentEdge,
                  ),
                ),
                child: Text(
                  appPromisesButtonText,
                  style: _font(
                    Fonts.outfit,
                    FontWeight.w600,
                    12.5,
                    1,
                    Palette.teal,
                    s,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MadeBy extends StatelessWidget {
  const _MadeBy({required this.scale, required this.height});

  final double scale;

  /// The row's touch height, the design's line centred in it.
  final double height;

  @override
  Widget build(BuildContext context) {
    final s = scale;
    TextStyle style(Color colour) => _font(
      Fonts.plexMono,
      FontWeight.w500,
      9.5,
      null,
      colour,
      s,
      letterSpacingEm: .12,
    );
    Widget link(String key, String url, String text) => ExternalLink(
      key: Key('aboutapp-link-$key'),
      url: url,
      semanticsLabel: '$text, opens in browser',
      builder: (context, pressed) => SizedBox(
        height: height,
        child: Center(
          child: DecoratedBox(
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Palette.linkUnderline)),
            ),
            child: Text(
              '$text ↗',
              key: Key('aboutapp-link-$key-text'),
              style: style(pressed ? Palette.teal : Palette.textDim),
            ),
          ),
        ),
      ),
    );
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 8 * s,
      children: [
        Text(madeByText, style: style(Palette.textFaint)),
        link('arcade', Links.site, arcadeLinkText),
        ExcludeSemantics(child: Text('·', style: style(Palette.textFaint))),
        link('source', appSourceUrl, githubLinkText),
      ],
    );
  }
}
