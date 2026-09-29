@Tags(['guard'])
library;

// The app's platform surface stays small and offline (#80, #96, CLAUDE.md
// invariant 1). The app reaches Android through its own two channels rather
// than plugins, so this guard reads both sides of each:
//  1. no Dart file under lib/ and no Kotlin file of the app names a network
//     API;
//  2. the platform channel's name is the same in Kotlin and Dart, Kotlin
//     handles exactly filesDir, openUrl and appVersion and refuses anything
//     else, and the Dart side invokes exactly those three; the sound channel
//     likewise, in SoundBridge.kt and sound_player.dart, with its six;
//  3. the main manifest leaves Android's own backup on: it is the player's
//     setting, and the app does not opt out.
//
// Every rule is a plain text match, comments included: it catches an honest
// mistake, not deliberate evasion (CLAUDE.md's stated scope). A network call
// made through a plugin is the manifest guard's and the bundle scan's to
// catch, through the permission it would need.

import 'package:flutter_test/flutter_test.dart';

import 'app_identity.dart';
import 'repo_files.dart';

/// Names that reach the network from Dart. A substring match, so `Socket`
/// also catches `WebSocket`, `RawSocket` and `SecureSocket`.
const dartNetworkApis = [
  'HttpClient',
  'Socket',
  'WebSocket',
  'RawSocket',
  'package:http',
  'InternetAddress',
];

/// Names that reach the network from Kotlin. `URL(` never matches
/// `openUrl(`, which is lower case.
const kotlinNetworkApis = ['java.net', 'URL(', 'HttpURLConnection', 'Socket'];

/// Every name in [apis] that [source] contains.
List<String> networkUses(String source, List<String> apis) => [
  for (final api in apis)
    if (source.contains(api)) api,
];

/// The methods the channel carries, in both languages.
const channelMethods = ['appVersion', 'filesDir', 'openUrl'];

const dartChannelFile = 'lib/platform/platform_channel.dart';

/// The methods the sound channel carries, in both languages.
const soundMethods = [
  'load',
  'musicPause',
  'musicStart',
  'musicStop',
  'play',
  'release',
];

const dartSoundFile = 'lib/feedback/sound_player.dart';

/// The value of every top-level `private const val <constant> = "…"`.
List<String> kotlinChannelNames(String kotlin, [String constant = 'CHANNEL']) =>
    [
      for (final m in RegExp(
        '^private const val $constant = "([^"]*)"',
        multiLine: true,
      ).allMatches(kotlin))
        m[1]!,
    ];

/// The value of every `const <constant> = '…'`.
List<String> dartChannelNames(
  String dart, [
  String constant = 'platformChannelName',
]) => [
  for (final m in RegExp(
    '^const $constant = [\'"]([^\'"]*)[\'"]',
    multiLine: true,
  ).allMatches(dart))
    m[1]!,
];

/// Every `"name" ->` branch label anywhere in [kotlin].
List<String> kotlinBranches(String kotlin) => [
  for (final m in RegExp(r'"([^"\n]*)"\s*->').allMatches(kotlin)) m[1]!,
];

/// What is wrong with [kotlin]'s branches: anything but exactly [methods],
/// or no `else -> result.notImplemented()`.
List<String> kotlinBranchProblems(
  String kotlin, [
  List<String> methods = channelMethods,
]) {
  final branches = kotlinBranches(kotlin)..sort();
  final elses = RegExp(r'else\s*->\s*result\.notImplemented\(\)')
      .allMatches(kotlin)
      .length;
  return [
    if (branches.join(',') != methods.join(','))
      'branches are $branches, not $methods',
    if (elses != 1)
      '$elses `else -> result.notImplemented()` branches, not exactly one',
  ];
}

/// The first argument of every `invokeMethod`, `invokeMapMethod` and
/// `invokeListMethod` call in [dart]; a non-literal shows as `<non-literal>`.
List<String> dartInvokedMethods(String dart) => [
  for (final m in RegExp(
    r"""invoke(?:Map|List)?Method\s*(?:<[^()]*?>)?\s*\(\s*(?:'([^']*)'|"([^"]*)"|([^,)]*))""",
  ).allMatches(dart))
    m[1] ?? m[2] ?? '<non-literal>',
];

/// Every backup attribute in [manifest] (comments removed) that could turn
/// Android's backup off: `allowBackup` set to anything but `true`, and
/// `fullBackupContent` or `dataExtractionRules` with any value.
List<String> backupOffenders(String manifest) {
  final xml = stripXmlComments(manifest);
  return [
    for (final m in RegExp(
      r'''android:allowBackup\s*=\s*(["'])(.*?)\1''',
    ).allMatches(xml))
      if (m[2]!.trim() != 'true') m[0]!,
    for (final m in RegExp(
      r'''android:(?:fullBackupContent|dataExtractionRules)\s*=\s*(["']).*?\1''',
    ).allMatches(xml))
      m[0]!,
  ];
}

const mainManifest = 'android/app/src/main/AndroidManifest.xml';

void main() {
  group('the real tree', () {
    late String activityPath;
    late String soundBridgePath;
    late List<String> kotlinFiles;

    setUpAll(() {
      final dir = readIdentity().kotlinDir;
      activityPath = '$dir/MainActivity.kt';
      soundBridgePath = '$dir/SoundBridge.kt';
      kotlinFiles = filesUnder(dir).where((p) => p.endsWith('.kt')).toList();
    });

    test('nothing in lib/ names a network API', () {
      final files = filesUnder('lib').where((p) => p.endsWith('.dart'));
      expect(files, contains(dartChannelFile));
      final offenders = [
        for (final path in files)
          for (final api in networkUses(readFile(path), dartNetworkApis))
            '$path: $api',
      ];
      expect(
        offenders,
        isEmpty,
        reason: describeOffenders(
          'platform-surface: network API in lib/',
          offenders,
        ),
      );
    });

    test('no Kotlin file of the app names a network API', () {
      expect(kotlinFiles, containsAll([activityPath, soundBridgePath]));
      final offenders = [
        for (final path in kotlinFiles)
          for (final api in networkUses(readFile(path), kotlinNetworkApis))
            '$path: $api',
      ];
      expect(
        offenders,
        isEmpty,
        reason: describeOffenders(
          'platform-surface: network API in the app\'s Kotlin',
          offenders,
        ),
      );
    });

    test('the channel has one name, the same on both sides', () {
      final kotlin = kotlinChannelNames(readFile(activityPath));
      final dart = dartChannelNames(readFile(dartChannelFile));
      expect(
        kotlin.length == 1 && dart.length == 1 && kotlin.single == dart.single,
        isTrue,
        reason:
            'platform-surface: channel name is $kotlin in MainActivity.kt and '
            '$dart in $dartChannelFile; each must declare exactly one, and '
            'the two must be equal',
      );
    });

    test('MainActivity.kt handles exactly the three methods', () {
      final problems = kotlinBranchProblems(readFile(activityPath));
      expect(
        problems,
        isEmpty,
        reason:
            'platform-surface: Kotlin channel branches: ${problems.join('; ')} '
            '— a new method is a new capability, which is a conversation with '
            'the owner, not an edit',
      );
    });

    test('the Dart side invokes exactly the three methods', () {
      final methods = dartInvokedMethods(readFile(dartChannelFile))..sort();
      expect(
        methods,
        channelMethods,
        reason:
            'platform-surface: Dart channel methods are $methods, not '
            '$channelMethods (each invoked once, by literal name)',
      );
    });

    test('the sound channel has one name, the same on both sides', () {
      final kotlin = kotlinChannelNames(
        readFile(soundBridgePath),
        'SOUND_CHANNEL',
      );
      final dart = dartChannelNames(
        readFile(dartSoundFile),
        'soundChannelName',
      );
      expect(
        kotlin.length == 1 && dart.length == 1 && kotlin.single == dart.single,
        isTrue,
        reason:
            'platform-surface: sound channel name is $kotlin in '
            'SoundBridge.kt and $dart in $dartSoundFile; each must declare '
            'exactly one, and the two must be equal',
      );
    });

    test('SoundBridge.kt handles exactly the six sound methods', () {
      final problems = kotlinBranchProblems(
        readFile(soundBridgePath),
        soundMethods,
      );
      expect(
        problems,
        isEmpty,
        reason:
            'platform-surface: sound channel Kotlin branches: '
            '${problems.join('; ')} — a new method is a new capability, '
            'which is a conversation with the owner, not an edit',
      );
    });

    test('the Dart sound player invokes exactly the six methods', () {
      final methods = dartInvokedMethods(readFile(dartSoundFile))..sort();
      expect(
        methods,
        soundMethods,
        reason:
            'platform-surface: sound channel Dart methods are $methods, not '
            '$soundMethods (each invoked once, by literal name)',
      );
    });

    test('the manifest leaves Android backup to the player', () {
      final offenders = backupOffenders(readFile(mainManifest));
      expect(
        offenders,
        isEmpty,
        reason: describeOffenders(
          'platform-surface: backup attribute',
          offenders,
        ),
      );
    });
  });

  group('the rules, proven both ways', () {
    test('network names are caught, comments included; openUrl( is not', () {
      expect(
        networkUses("import 'dart:io';\nFile('x');", dartNetworkApis),
        isEmpty,
      );
      expect(networkUses('final c = HttpClient();', dartNetworkApis), [
        'HttpClient',
      ]);
      expect(
        networkUses('WebSocket.connect(u)', dartNetworkApis),
        containsAll(['Socket', 'WebSocket']),
      );
      expect(networkUses('// Socket.connect(host, 80)', dartNetworkApis), [
        'Socket',
      ]);
      expect(networkUses('InternetAddress.lookup(h)', dartNetworkApis), [
        'InternetAddress',
      ]);
      expect(networkUses("import 'package:http/http.dart';", dartNetworkApis), [
        'package:http',
      ]);
      expect(networkUses('openUrl(url)', kotlinNetworkApis), isEmpty);
      expect(networkUses('// java.net.URL("https://x")', kotlinNetworkApis), [
        'java.net',
        'URL(',
      ]);
      expect(
        networkUses(
          'val c = u.openConnection() as HttpURLConnection',
          kotlinNetworkApis,
        ),
        ['HttpURLConnection'],
      );
    });

    const kotlin = '''
private const val CHANNEL = "a/b"

class MainActivity : FlutterActivity() {
    fun f() {
        when (call.method) {
            "filesDir" -> filesDir(result)
            "openUrl" -> result.success(openUrl(url))
            "appVersion" -> appVersion(result)
            else -> result.notImplemented()
        }
    }
}
''';

    test('the Kotlin branches: exactly three and a refusing else', () {
      expect(kotlinBranchProblems(kotlin), isEmpty);
      expect(
        kotlinBranchProblems(
          kotlin.replaceFirst(
            'else ->',
            '"vibrate" -> result.success(null)\n            else ->',
          ),
        ),
        hasLength(1),
        reason: 'a fourth branch',
      );
      expect(
        kotlinBranchProblems(
          kotlin.replaceFirst(
            'else -> result.notImplemented()',
            'else -> result.success(null)',
          ),
        ),
        hasLength(1),
        reason: 'an else that answers',
      );
      expect(
        kotlinBranchProblems(
          kotlin.replaceFirst('"appVersion" -> appVersion(result)\n', ''),
        ),
        hasLength(1),
        reason: 'a missing branch',
      );
    });

    test('the channel names are read on both sides', () {
      expect(kotlinChannelNames(kotlin), ['a/b']);
      expect(dartChannelNames("const platformChannelName = 'a/b';"), ['a/b']);
      expect(
        kotlinChannelNames(kotlin.replaceFirst('"a/b"', '"a/b2"')),
        isNot(dartChannelNames("const platformChannelName = 'a/b';")),
      );
      expect(kotlinChannelNames('val x = "a/b"'), isEmpty);
      const sound = 'private const val SOUND_CHANNEL = "a/s"';
      expect(kotlinChannelNames(sound, 'SOUND_CHANNEL'), ['a/s']);
      expect(kotlinChannelNames(sound), isEmpty);
      expect(kotlinChannelNames(kotlin, 'SOUND_CHANNEL'), isEmpty);
      expect(
        dartChannelNames("const soundChannelName = 'a/s';", 'soundChannelName'),
        ['a/s'],
      );
      expect(dartChannelNames("const soundChannelName = 'a/s';"), isEmpty);
    });

    test('the sound branches: exactly six and a refusing else', () {
      const bridge = '''
when (call.method) {
    "load" -> result.success(load(clips))
    "play" -> { play(); result.success(null) }
    "musicStart" -> result.success(musicStart())
    "musicPause" -> { pauseMusic(); result.success(null) }
    "musicStop" -> { stopMusic(); result.success(null) }
    "release" -> { release(); result.success(null) }
    else -> result.notImplemented()
}
''';
      expect(kotlinBranchProblems(bridge, soundMethods), isEmpty);
      expect(kotlinBranchProblems(bridge), hasLength(1));
      expect(
        kotlinBranchProblems(
          bridge.replaceFirst(
            'else ->',
            '"vibrate" -> result.success(null)\n    else ->',
          ),
          soundMethods,
        ),
        hasLength(1),
        reason: 'a seventh branch',
      );
      expect(
        kotlinBranchProblems(
          bridge.replaceFirst('    else -> result.notImplemented()\n', ''),
          soundMethods,
        ),
        hasLength(1),
        reason: 'no refusing else',
      );
    });

    test('the Dart invocations: literals only, generics allowed', () {
      const dart = '''
channel.invokeMethod<String>('filesDir');
channel.invokeMethod<bool>('openUrl', {'url': url});
channel.invokeMapMethod<String, Object?>('appVersion');
''';
      expect(dartInvokedMethods(dart), ['filesDir', 'openUrl', 'appVersion']);
      expect(dartInvokedMethods("channel.invokeListMethod('x')"), ['x']);
      expect(dartInvokedMethods('channel.invokeMethod(name)'), [
        '<non-literal>',
      ]);
    });

    test('backup: off in any form is caught, a comment or true is not', () {
      expect(backupOffenders('<application android:label="x">'), isEmpty);
      expect(
        backupOffenders('<application android:allowBackup="true">'),
        isEmpty,
      );
      expect(
        backupOffenders('<!-- android:allowBackup="false" -->\n<application>'),
        isEmpty,
      );
      for (final dirty in [
        '<application android:allowBackup="false">',
        "<application android:allowBackup='false'>",
        '<application android:allowBackup = "false">',
        '<application android:allowBackup="@bool/backup">',
        '<application android:fullBackupContent="@xml/rules">',
        '<application android:fullBackupContent="true">',
        "<application android:dataExtractionRules='@xml/rules'>",
      ]) {
        expect(backupOffenders(dirty), hasLength(1), reason: dirty);
      }
    });
  });
}
