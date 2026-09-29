/// The app's one bridge to Android (#80): the private files directory the
/// store saves into, opening an https link in the browser, and the installed
/// version. It is the app's own channel rather than a plugin, so no third
/// party's manifest joins the build; test/guards/platform_surface_test.dart
/// keeps both sides to exactly these three methods.
library;

import 'dart:async';

import 'package:flutter/services.dart';

/// The channel's name; MainActivity.kt's `CHANNEL` must be the same.
const platformChannelName = 'honestchess/platform';

/// The installed app's `versionName` and `versionCode`.
final class AppVersion {
  const AppVersion({required this.name, required this.code});

  final String name;
  final int code;

  /// The name as screens show it: trimmed, one leading "v" or "V" removed,
  /// null when nothing is left. Every screen formats the version through
  /// this, so none of them strips a "v" of its own.
  String? get displayName {
    var n = name.trim();
    if (n.startsWith('v') || n.startsWith('V')) n = n.substring(1);
    n = n.trim();
    return n.isEmpty ? null : n;
  }

  @override
  bool operator ==(Object other) =>
      other is AppVersion && other.name == name && other.code == code;

  @override
  int get hashCode => Object.hash(name, code);

  @override
  String toString() => 'AppVersion($name, $code)';
}

/// What the app asks of Android. Tests implement it with a fake
/// (test/support/fake_platform_channel.dart).
abstract interface class PlatformChannel {
  /// The app's private files directory, or null when Android does not say.
  Future<String?> filesDir();

  /// Opens [url] in the browser. False when the URL is refused (see
  /// [isOpenableUrl]) or nothing could open it.
  Future<bool> openUrl(String url);

  /// The installed version, or null when it cannot be read.
  Future<AppVersion?> appVersion();

  /// Whether [url] may be opened at all: https with a host. The production
  /// channel and the test fake both refuse anything else before asking.
  static bool isOpenableUrl(String url) {
    final uri = Uri.tryParse(url);
    return uri != null && uri.scheme == 'https' && uri.host.isNotEmpty;
  }
}

/// How long [MethodChannelPlatform.appVersion] waits for Android.
const appVersionTimeout = Duration(seconds: 2);

/// The production [PlatformChannel], over a [MethodChannel] that tests may
/// replace.
final class MethodChannelPlatform implements PlatformChannel {
  MethodChannelPlatform([
    this.channel = const MethodChannel(platformChannelName),
  ]);

  final MethodChannel channel;

  AppVersion? _version;

  @override
  Future<String?> filesDir() async {
    try {
      final path = await channel.invokeMethod<String>('filesDir');
      return path == null || path.trim().isEmpty ? null : path;
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  @override
  Future<bool> openUrl(String url) async {
    if (!PlatformChannel.isOpenableUrl(url)) return false;
    try {
      return await channel.invokeMethod<bool>('openUrl', {'url': url}) ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  @override
  Future<AppVersion?> appVersion() async {
    if (_version case final known?) return known;
    try {
      final answer = await channel
          .invokeMapMethod<String, Object?>('appVersion')
          .timeout(appVersionTimeout);
      final name = answer?['name'];
      final code = answer?['code'];
      if (name is! String || name.trim().isEmpty || code is! int) return null;
      return _version = AppVersion(name: name, code: code);
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    } on TimeoutException {
      return null;
    }
  }
}
