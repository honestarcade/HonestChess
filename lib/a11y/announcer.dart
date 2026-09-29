/// Spoken announcements for TalkBack (#102): one door for every
/// `SemanticsService.sendAnnouncement` in the app (the announcer scan keeps
/// it that way), speaking only while a screen reader is on, and injectable
/// so tests read what would have been said. Honest Solitaire's shape.
library;

import 'dart:async';

import 'package:flutter/semantics.dart';
import 'package:flutter/widgets.dart';

/// Speaks a sentence to the screen reader.
abstract interface class Announcer {
  /// Speaks [text], after anything already being spoken: announcements are
  /// polite, so the screen reader's own queue orders them and none cuts
  /// another off.
  void announce(String text);
}

/// Speaks through the platform, from the context [context] returns, and
/// only while that context's `accessibleNavigation` is on (a screen
/// reader): nobody else hears an announcement, and no context, or an
/// unmounted one, says nothing.
class FlutterAnnouncer implements Announcer {
  const FlutterAnnouncer(this.context);

  final BuildContext? Function() context;

  @override
  void announce(String text) {
    final from = context();
    if (from == null || !from.mounted) return;
    if (!MediaQuery.accessibleNavigationOf(from)) return;
    unawaited(
      SemanticsService.sendAnnouncement(
        View.of(from),
        text,
        Directionality.maybeOf(from) ?? TextDirection.ltr,
      ),
    );
  }
}

/// Records what would have been said, for tests and the device test.
class RecordingAnnouncer implements Announcer {
  final List<String> spoken = [];

  @override
  void announce(String text) => spoken.add(text);
}

/// Says nothing: a board shown with no screen reader wired to it.
class NoAnnouncer implements Announcer {
  const NoAnnouncer();

  @override
  void announce(String text) {}
}
