@Tags(['guard'])
library;

// The app's platform surface stays small and offline (#80, CLAUDE.md
// invariant 1). The app reaches Android through its own channel rather than
// a plugin, so this guard reads both sides of it:
//  1. no Dart file under lib/ and nothing in MainActivity.kt names a network
//     API;
//  2. the channel's name is the same in Kotlin and Dart, Kotlin handles
//     exactly filesDir, openUrl and appVersion and refuses anything else, and
//     the Dart side invokes exactly those three;
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

/// The value of every top-level `private const val CHANNEL = "…"`.
List<String> kotlinChannelNames(String kotlin) => [
  for (final m in RegExp(
    r'^private const val CHANNEL = "([^"]*)"',
    multiLine: true,
  ).allMatches(kotlin))
    m[1]!,
];

/// The value of every `const platformChannelName = '…'`.
List<String> dartChannelNames(String dart) => [
  for (final m in RegExp(
    r"""^const platformChannelName = ['"]([^'"]*)['"]""",
    multiLine: true,
  ).allMatches(dart))
    m[1]!,
];

/// Every `"name" ->` branch label anywhere in [kotlin].
List<String> kotlinBranches(String kotlin) => [
  for (final m in RegExp(r'"([^"\n]*)"\s*->').allMatches(kotlin)) m[1]!,
];

/// What is wrong with [kotlin]'s branches: anything but exactly
/// [channelMethods], or no `else -> result.notImplemented()`.
List<String> kotlinBranchProblems(String kotlin) {
  final branches = kotlinBranches(kotlin)..sort();
  final elses = RegExp(r'else\s*->\s*result\.notImplemented\(\)')
      .allMatches(kotlin)
      .length;
  return [
    if (branches.join(',') != channelMethods.join(','))
      'branches are $branches, not $channelMethods',
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

    setUpAll(
      () => activityPath = '${readIdentity().kotlinDir}/MainActivity.kt',
    );

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

    test('nothing in MainActivity.kt names a network API', () {
      final offenders = [
        for (final api in networkUses(
          readFile(activityPath),
          kotlinNetworkApis,
        ))
          '$activityPath: $api',
      ];
      expect(
        offenders,
        isEmpty,
        reason: describeOffenders(
          'platform-surface: network API in MainActivity.kt',
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
