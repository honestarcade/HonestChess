import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'board/board_options.dart';

/// Whether the app animates: [full], or [off] — every animation the app
/// draws itself is instant then. Route transitions are the platform's own
/// and do not read it.
enum Motion {
  full,
  off;

  /// The motion for [context]: off when Settings' Piece animations is off
  /// ([MotionScope]) or the phone's remove-animations setting is on
  /// ([MediaQuery.disableAnimations]), each read live. Without a scope above
  /// — before the app's settings exist — only the phone's setting counts.
  static Motion of(BuildContext context) => motionFor(
    animations: MotionScope._maybeOf(context)?.animations ?? true,
    disableAnimations: MediaQuery.maybeDisableAnimationsOf(context) ?? false,
  );

  bool get isOff => this == Motion.off;
}

/// The one rule behind [Motion.of]: motion is full only while the app's
/// [animations] setting is on and the phone's [disableAnimations] is not.
Motion motionFor({required bool animations, required bool disableAnimations}) =>
    animations && !disableAnimations ? Motion.full : Motion.off;

/// Publishes Settings' Piece animations below the `MaterialApp`, where
/// [Motion.of] reads it; the app root's `MaterialApp.builder` puts it in.
class MotionScope extends InheritedWidget {
  const MotionScope({
    super.key,
    required this.animations,
    required super.child,
  });

  /// `BoardOptions.animations`.
  final bool animations;

  static MotionScope? _maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<MotionScope>();

  @override
  bool updateShouldNotify(MotionScope oldWidget) =>
      animations != oldWidget.animations;
}

/// A [MotionScope] following [board]'s `animations` as it changes, for the
/// app root's `MaterialApp.builder` and the test harness's.
class SettingsMotion extends StatelessWidget {
  const SettingsMotion({super.key, required this.board, required this.child});

  final ValueListenable<BoardOptions> board;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<BoardOptions>(
      valueListenable: board,
      builder: (context, options, child) =>
          MotionScope(animations: options.animations, child: child!),
      child: child,
    );
  }
}
