import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../board/board_view.dart' show designWidth;
import '../theme/palette.dart';

/// What shows when nothing on the phone could open a link.
const noBrowserText = 'No browser found';

/// How long the message stays.
const noBrowserDuration = Duration(seconds: 3);

/// How long a link waits for Android's answer. Past it the link takes taps
/// again and a late answer is dropped: a slow answer most likely means the
/// browser is opening, so "No browser found" could be untrue.
const openUrlWait = Duration(seconds: 5);

/// Draws a link, [pressed] while a finger is down on it.
typedef LinkBuilder = Widget Function(BuildContext context, bool pressed);

/// The one way the app opens a web address: a tap asks Android, through
/// the scope's `PlatformChannel.openUrl`, to open [url] in the phone's
/// browser. The app never fetches it itself. If nothing can open it (or
/// the call fails), [noBrowserText] shows in a floating message; taps are
/// ignored while a call is pending.
class ExternalLink extends StatefulWidget {
  ExternalLink({
    super.key,
    required this.url,
    required this.semanticsLabel,
    required this.builder,
  }) : assert(url.startsWith('https://'), 'links are https: $url');

  final String url;

  /// What a screen reader says: the visible text, with ↗ spoken
  /// "opens in browser".
  final String semanticsLabel;

  final LinkBuilder builder;

  @override
  State<ExternalLink> createState() => _ExternalLinkState();
}

class _ExternalLinkState extends State<ExternalLink> {
  bool _pressed = false;
  bool _pending = false;

  /// Which call is current; an answer to an older one is dropped.
  int _call = 0;
  Timer? _wait;

  @override
  void dispose() {
    _wait?.cancel();
    super.dispose();
  }

  void _setPressed(bool value) {
    if (_pressed != value) setState(() => _pressed = value);
  }

  Future<void> _open() async {
    if (_pending) return;
    final platform = AppScope.of(context).platform;
    final call = ++_call;
    _pending = true;
    _wait = Timer(openUrlWait, () {
      if (call != _call) return;
      _call++;
      _pending = false;
    });
    bool opened;
    try {
      opened = await platform.openUrl(widget.url);
    } catch (error) {
      debugPrint('openUrl failed: $error');
      opened = false;
    }
    if (call != _call) return;
    _wait?.cancel();
    _pending = false;
    if (opened || !mounted) return;
    showNoBrowser(context);
  }

  @override
  Widget build(BuildContext context) => Semantics(
    link: true,
    label: widget.semanticsLabel,
    onTap: _open,
    excludeSemantics: true,
    child: Listener(
      onPointerDown: (_) => _setPressed(true),
      onPointerUp: (_) => _setPressed(false),
      onPointerCancel: (_) => _setPressed(false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _open,
        child: widget.builder(context, _pressed),
      ),
    ),
  );
}

/// Shows [noBrowserText] on the app's messenger, replacing any current
/// message; nothing when [context] has no messenger.
void showNoBrowser(BuildContext context) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  final s = math.min(MediaQuery.sizeOf(context).width, 480.0) / designWidth;
  messenger
    ..removeCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        key: const Key('no-browser'),
        behavior: SnackBarBehavior.floating,
        duration: noBrowserDuration,
        backgroundColor: Palette.cardSurface,
        elevation: 0,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: Palette.cardEdge),
        ),
        content: Text(
          noBrowserText,
          style: TextStyle(
            fontFamily: Fonts.outfit,
            fontWeight: FontWeight.w500,
            fontSize: 13 * s,
            color: const Color(0xFFFFFFFF),
          ),
        ),
      ),
    );
}
