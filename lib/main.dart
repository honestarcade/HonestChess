import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:honest_chess/data/app_loader.dart';
import 'package:honest_chess/data/app_store.dart';
import 'package:honest_chess/data/game_saves.dart';
import 'package:honest_chess/data/settings_store.dart';
import 'package:honest_chess/data/stats.dart';
import 'package:honest_chess/data/stats_listener.dart';
import 'package:honest_chess/feedback/clips.dart';
import 'package:honest_chess/feedback/game_feedback.dart';
import 'package:honest_chess/feedback/haptics.dart';
import 'package:honest_chess/feedback/music_controller.dart';
import 'package:honest_chess/feedback/sound_player.dart';
import 'package:honest_chess/platform/platform_channel.dart';
import 'package:honest_chess/ui/app_scope.dart';
import 'package:honest_chess/ui/motion.dart';
import 'package:honest_chess/ui/game/computer_turns.dart';
import 'package:honest_chess/ui/game/game_controller.dart';
import 'package:honest_chess/ui/navigation.dart';
import 'package:honest_chess/ui/screens/menu_screen.dart';
import 'package:honest_chess/ui/screens/splash_screen.dart';
import 'package:honest_chess/ui/theme/palette.dart';

// The launcher-icon guard reads this literal here; Palette.screenBg is the
// same colour for everything else.
const _navy = Color(0xFF05285F);

/// Starts the app on the splash, then the menu. [seed] is every new game's computer seed
/// and [store] replaces the device store, for the device test only: its
/// memory store never shows a leftover saved game.
void main({int? seed, AppStore? store}) {
  registerFontLicences();
  runApp(HonestChessApp(seedOverride: seed, store: store));
}

/// The bundled fonts' OFL texts (assets/fonts/SOURCE.md), each shown on the
/// licence page under the family it covers.
const fontLicences = {
  'Outfit': 'assets/fonts/outfit/OFL.txt',
  'IBM Plex Mono': 'assets/fonts/plexmono/OFL.txt',
  'Noto Sans Symbols 2': 'assets/fonts/pieces/OFL.txt',
};

void registerFontLicences() {
  LicenseRegistry.addLicense(() async* {
    for (final MapEntry(key: family, value: path) in fontLicences.entries) {
      yield LicenseEntryWithLineBreaks([
        family,
      ], await rootBundle.loadString(path));
    }
  });
}

/// The app's theme, shared by the root and test/support/app_harness.dart.
ThemeData appTheme() => ThemeData(
  brightness: Brightness.dark,
  scaffoldBackgroundColor: _navy,
  fontFamily: Fonts.outfit,
);

/// The app root. It owns the store, the settings, the statistics, the
/// saved games and the game controller, and loads the saved data at launch
/// behind the splash, which then hands over to the menu.
class HonestChessApp extends StatefulWidget {
  const HonestChessApp({
    super.key,
    this.computerFactory = ComputerPlayerOpponent.new,
    this.seedOverride,
    this.store,
    this.platform,
    this.sound,
    this.haptics,
    this.skipSplash = false,
  });

  /// The device store; null builds the production one over [platform].
  final AppStore? store;

  /// The Android bridge; null builds the production channel.
  final PlatformChannel? platform;

  /// The sound bridge; null builds the production channel.
  final SoundPlayer? sound;

  /// The haptic port; null ticks through Flutter's own haptic call.
  final HapticsPort? haptics;

  /// Builds the computer for each game against it; tests pass a fake.
  final ComputerFactory computerFactory;

  /// Every new game's computer seed, so the seed saved is the one played;
  /// fresh per game when null. For tests.
  final int? seedOverride;

  /// For tests: load behind a plain navy frame and open straight on the
  /// menu once loaded, with no splash, floor, hold or fade.
  final bool skipSplash;

  @override
  State<HonestChessApp> createState() => HonestChessAppState();
}

class HonestChessAppState extends State<HonestChessApp> {
  /// The board options and setup choices; every change to the board options
  /// reaches the controller and the board at once.
  final settings = SettingsStore();

  /// The navigating flag, observing the app's one navigator.
  final navigation = NavigationGuard();

  /// Random's colour is drawn from the platform's secure source.
  final random = Random.secure();

  /// Built once, never rebuilt: a test injecting only a platform gets a
  /// store resolved through it.
  late final PlatformChannel platform;
  late final AppStore store;
  late final GameController controller;
  late final GameSaves saves;
  late final StatsRecorder stats;
  late final StatsListener _statsListener;
  late final AppLoader _loader;
  late final SoundPlayer sound;
  late final HapticsPort haptics;

  /// False from the moment the app starts leaving the foreground
  /// (inactive, hidden, paused or detached) until it is back.
  final foreground = ValueNotifier<bool>(true);

  /// Whether the board is the page on top, for the music's gate.
  final boardRoutes = BoardRouteObserver();
  late final GameFeedback _feedback;
  late final MusicController music;

  /// Leaving the app pauses the live game, whose pause is saved, and then
  /// waits for the store to write it.
  late final AppLifecycleListener _lifecycle;

  /// Whether the launch load has finished; only [HonestChessApp.skipSplash]
  /// waits for it before building the app.
  bool _launched = false;

  @override
  void initState() {
    super.initState();
    platform = widget.platform ?? MethodChannelPlatform();
    store = widget.store ?? AppStore.onDevice(platform);
    controller = GameController.idle(
      computerFactory: widget.computerFactory,
      options: settings.board.value,
      seed: widget.seedOverride,
    );
    settings.board.addListener(_boardChanged);
    saves = GameSaves(store)..attach(controller.events);
    stats = StatsRecorder(store: store);
    // Before the launch load, so a finished game found there is counted.
    _statsListener = StatsListener(
      controller: controller,
      recorder: stats,
      saves: saves,
    );
    _lifecycle = AppLifecycleListener(onStateChange: _left);
    sound = widget.sound ?? ChannelSoundPlayer();
    // Once, beside the launch load rather than a step of it: a clip that
    // fails to load stays silent, and nothing waits on it.
    unawaited(sound.load(clips));
    haptics = widget.haptics ?? FlutterHaptics();
    _feedback = GameFeedback(
      events: controller.events,
      refusals: controller.refusals,
      board: settings.board,
      foreground: foreground,
      player: sound,
      haptics: haptics,
    );
    music = MusicController(
      controller: controller,
      board: settings.board,
      boardVisible: boardRoutes.visible,
      foreground: foreground,
      player: sound,
    );
    _loader = AppLoader(
      store: store,
      settings: settings,
      stats: stats,
      saves: saves,
    )..start();
    _loader.done.then((_) {
      if (mounted) setState(() => _launched = true);
    });
  }

  void _boardChanged() => controller.options = settings.board.value;

  Future<void> _left(AppLifecycleState state) async {
    foreground.value = state == AppLifecycleState.resumed;
    if (state != AppLifecycleState.inactive &&
        state != AppLifecycleState.hidden) {
      return;
    }
    // A clock already at zero ends the game on time rather than being
    // saved at 0:00.
    controller.checkFlag();
    controller.autoPause();
    await saves.flush();
  }

  @override
  void dispose() {
    music.dispose();
    _feedback.dispose();
    unawaited(sound.dispose());
    boardRoutes.dispose();
    foreground.dispose();
    _lifecycle.dispose();
    _loader.dispose();
    _statsListener.dispose();
    stats.dispose();
    saves.dispose();
    settings.board.removeListener(_boardChanged);
    settings.dispose();
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Without the splash, a plain navy frame while the launch load runs.
    if (widget.skipSplash && !_launched) return const ColoredBox(color: _navy);
    return AppScope(
      store: store,
      platform: platform,
      controller: controller,
      saves: saves,
      stats: stats,
      settings: settings,
      navigation: navigation,
      random: random,
      sound: sound,
      music: music,
      haptics: haptics,
      child: MaterialApp(
        title: 'Honest Chess',
        navigatorObservers: [navigation, boardRoutes],
        debugShowCheckedModeBanner: false,
        theme: appTheme(),
        // One system-bar style for every route; screens set none of their
        // own.
        builder: (context, child) => SettingsMotion(
          board: settings.board,
          child: AnnotatedRegion<SystemUiOverlayStyle>(
            value: appOverlayStyle,
            child: child ?? const SizedBox.shrink(),
          ),
        ),
        home: widget.skipSplash
            ? const MenuScreen()
            : SplashScreen(loader: _loader),
      ),
    );
  }
}
