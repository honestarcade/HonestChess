import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../data/app_loader.dart';
import '../board/board_view.dart' show designWidth;
import '../brand/honest_mark.dart';
import '../theme/palette.dart';
import '../widgets/screen_background.dart';
import 'menu_screen.dart';

/// The splash's texts, as the design writes them.
const splashBylineText = 'BY HONEST ARCADE';
const splashSemanticsLabel = 'Loading Honest Chess';

/// The shortest the splash shows, from its first frame, so it never
/// flashes for a frame on a fast phone.
const splashFloor = Duration(milliseconds: 600);

/// How long READY holds, on screen, before the menu fades in.
const readyHold = Duration(milliseconds: 250);

/// The menu's fade in over the splash.
const splashFade = Duration(milliseconds: 300);

/// The bar's glide to each new value.
const barGlide = Duration(milliseconds: 200);

/// The gradient's fade in over the flat navy of the first frame.
const gradientFadeIn = Duration(milliseconds: 150);

/// The splash scales by the width over the design's 390, capped here.
const splashScaleCapWidth = 480.0;

/// The label under the bar for the fraction of load steps finished, at
/// the design's thresholds: below 45%, below 85%, and from there.
String splashLabel(double fraction) => fraction < .45
    ? 'SETTING UP'
    : fraction < .85
    ? 'SORTING PIECES'
    : 'READY';

/// The app's first route: the mark, the wordmark and a bar following the
/// launch [loader]. It shows for at least [splashFloor]; once the load is
/// done and the floor has passed it holds READY for [readyHold] while it is
/// in view, then replaces itself with the menu, fading it in over
/// [splashFade]. Back is ignored while it shows.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key, required this.loader});

  final AppLoader loader;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _gradient = AnimationController(
    vsync: this,
    duration: gradientFadeIn,
  );
  late final AppLifecycleListener _lifecycle;
  late final Timer _floor;
  Timer? _hold;
  bool _floorPassed = false;
  bool _loaded = false;
  bool _handedOver = false;
  bool _motionChecked = false;

  /// Whether the splash is on screen: false once the app is hidden or
  /// paused, true again only when it is resumed. `inactive` (the
  /// notification shade, a system dialog) leaves the splash in view.
  bool _inView = true;

  @override
  void initState() {
    super.initState();
    final state = WidgetsBinding.instance.lifecycleState;
    _inView = !_away(state);
    _lifecycle = AppLifecycleListener(onStateChange: _lifecycleChanged);
    _floor = Timer(splashFloor, () {
      _floorPassed = true;
      _maybeHold();
    });
    widget.loader.done.then((_) {
      if (!mounted) return;
      _loaded = true;
      _maybeHold();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_motionChecked) return;
    _motionChecked = true;
    if (MediaQuery.disableAnimationsOf(context)) {
      _gradient.value = 1;
    } else {
      _gradient.forward();
    }
  }

  static bool _away(AppLifecycleState? state) =>
      state == AppLifecycleState.hidden ||
      state == AppLifecycleState.paused ||
      state == AppLifecycleState.detached;

  void _lifecycleChanged(AppLifecycleState state) {
    if (_away(state)) {
      _inView = false;
      _hold?.cancel();
      _hold = null;
    } else if (state == AppLifecycleState.resumed && !_inView) {
      _inView = true;
      _maybeHold();
    }
  }

  void _maybeHold() {
    if (!mounted || _handedOver || _hold != null) return;
    if (!_loaded || !_floorPassed || !_inView) return;
    _hold = Timer(readyHold, _handOver);
  }

  void _handOver() {
    if (!mounted || _handedOver) return;
    _handedOver = true;
    final instant = MediaQuery.disableAnimationsOf(context);
    Navigator.of(context).pushReplacement(
      PageRouteBuilder<void>(
        transitionDuration: instant ? Duration.zero : splashFade,
        reverseTransitionDuration: instant ? Duration.zero : splashFade,
        pageBuilder: (context, animation, secondaryAnimation) =>
            const MenuScreen(),
        transitionsBuilder: (context, animation, secondaryAnimation, child) =>
            FadeTransition(
              opacity: CurvedAnimation(
                parent: animation,
                curve: Curves.easeOut,
              ),
              child: child,
            ),
      ),
    );
  }

  @override
  void dispose() {
    _floor.cancel();
    _hold?.cancel();
    _lifecycle.dispose();
    _gradient.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final instant = MediaQuery.disableAnimationsOf(context);
    return PopScope(
      canPop: false,
      // Screen text ignores the system text scale, as the board does, until
      // M5's accessibility work.
      child: MediaQuery.withNoTextScaling(
        child: Material(
          type: MaterialType.transparency,
          child: Stack(
            fit: StackFit.expand,
            children: [
              const ColoredBox(
                key: Key('splash-navy'),
                color: Palette.screenBg,
              ),
              FadeTransition(
                key: const Key('splash-gradient'),
                opacity: CurvedAnimation(
                  parent: _gradient,
                  curve: Curves.easeOut,
                ),
                child: const ScreenBackground(gradient: ScreenGradient.splash),
              ),
              LayoutBuilder(
                builder: (context, constraints) {
                  final s =
                      math.min(constraints.maxWidth, splashScaleCapWidth) /
                      designWidth;
                  return SafeArea(
                    child: Center(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Semantics(
                          key: const Key('splash'),
                          container: true,
                          label: splashSemanticsLabel,
                          excludeSemantics: true,
                          child: _SplashColumn(
                            scale: s,
                            progress: widget.loader.progress,
                            instant: instant,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A CSS `font: <weight> <size>/1` at [scale], letter-spaced [em].
TextStyle _font(
  String family,
  FontWeight weight,
  double size,
  Color colour,
  double scale, {
  double em = 0,
}) => TextStyle(
  fontFamily: family,
  fontWeight: weight,
  fontSize: size * scale,
  height: 1,
  leadingDistribution: TextLeadingDistribution.even,
  letterSpacing: em * size * scale,
  color: colour,
);

class _SplashColumn extends StatelessWidget {
  const _SplashColumn({
    required this.scale,
    required this.progress,
    required this.instant,
  });

  final double scale;
  final ValueListenable<double> progress;
  final bool instant;

  @override
  Widget build(BuildContext context) {
    final s = scale;
    final wordmark = _font(
      Fonts.outfit,
      FontWeight.w700,
      40,
      const Color(0xFFFFFFFF),
      s,
      em: -.03,
    );
    final gap = SizedBox(height: 30 * s);
    return ValueListenableBuilder<double>(
      valueListenable: progress,
      builder: (context, fraction, _) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          HonestMark.chess(132 * s, key: const Key('splash-mark')),
          gap,
          Text.rich(
            key: const Key('splash-wordmark'),
            TextSpan(
              text: 'Honest',
              style: wordmark,
              children: [
                TextSpan(
                  text: 'Chess',
                  style: wordmark.copyWith(color: Palette.teal),
                ),
              ],
            ),
          ),
          SizedBox(height: 14 * s),
          Text(
            splashBylineText,
            key: const Key('splash-byline'),
            style: _font(
              Fonts.plexMono,
              FontWeight.w500,
              11,
              Palette.textDim,
              s,
              em: .28,
            ),
          ),
          gap,
          _Bar(fraction: fraction, scale: s, instant: instant),
          gap,
          Text(
            splashLabel(fraction),
            key: const Key('splash-label'),
            style: _font(
              Fonts.plexMono,
              FontWeight.w500,
              10,
              Palette.textLabel,
              s,
              em: .2,
            ),
          ),
        ],
      ),
    );
  }
}

/// The 220 × 5 track and its teal-to-blue fill, gliding to [fraction] over
/// [barGlide], or jumping when [instant].
class _Bar extends StatelessWidget {
  const _Bar({
    required this.fraction,
    required this.scale,
    required this.instant,
  });

  final double fraction;
  final double scale;
  final bool instant;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(3 * scale);
    return ClipRRect(
      key: const Key('splash-bar'),
      borderRadius: radius,
      child: Container(
        width: 220 * scale,
        height: 5 * scale,
        decoration: BoxDecoration(
          color: Palette.borderSoft,
          borderRadius: radius,
        ),
        alignment: Alignment.centerLeft,
        child: TweenAnimationBuilder<double>(
          tween: Tween(end: fraction),
          duration: instant ? Duration.zero : barGlide,
          curve: Curves.easeOut,
          builder: (context, value, _) => FractionallySizedBox(
            key: const Key('splash-bar-fill'),
            widthFactor: value,
            heightFactor: 1,
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: radius,
                gradient: const LinearGradient(
                  colors: [Palette.teal, Palette.brandBlue],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
