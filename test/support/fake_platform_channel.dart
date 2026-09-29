import 'package:honest_chess/platform/platform_channel.dart';

/// A [PlatformChannel] with settable answers. Its `openUrl` surface is the
/// only one widget tests use: later stories reuse it and add nothing to it.
class FakePlatformChannel implements PlatformChannel {
  /// Answers `filesDir`; null makes an on-device store fall back to memory.
  Future<String?> Function() onFilesDir = () async => null;

  /// Answers `appVersion`; a test may answer null or a pending future.
  Future<AppVersion?> Function() onAppVersion = () async =>
      const AppVersion(name: '1.2.3', code: 1034);

  /// Answers an openable `openUrl`; a test may answer false, throw or never
  /// complete.
  Future<bool> Function(String url) onOpenUrl = (_) async => true;

  /// Every URL `openUrl` was asked to open, refused ones included.
  final List<String> openUrlCalls = [];

  @override
  Future<String?> filesDir() => onFilesDir();

  @override
  Future<AppVersion?> appVersion() => onAppVersion();

  @override
  Future<bool> openUrl(String url) {
    openUrlCalls.add(url);
    if (!PlatformChannel.isOpenableUrl(url)) return Future.value(false);
    return onOpenUrl(url);
  }
}
