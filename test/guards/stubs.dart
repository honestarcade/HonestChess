// Runs a repository script, or a workflow step's `run:` body, in a scratch
// directory with chosen commands replaced by stub scripts on PATH. Lets a
// guard drive a script's failure branches — a refusing API, a failing `gh` —
// with no network and no credentials.
import 'dart:io';

import 'repo_files.dart';

class ScriptRun {
  ScriptRun(this.exitCode, this.stdout, this.stderr, this.dir);
  final int exitCode;
  final String stdout;
  final String stderr;

  /// The scratch directory, deleted once the run returns. Only paths are
  /// meaningful here, for messages.
  final String dir;

  String get output => '$stdout$stderr';
}

/// Runs `bash` with [args] in a fresh scratch directory. [stubs] maps a
/// command name to the text of an executable that replaces it; PATH is the
/// stub directory then `/usr/bin:/bin`. [files] are written into the scratch
/// directory first. `{dir}` in [args], an [env] value or a [files] body becomes
/// the scratch
/// directory's path, for scripts that change directory. [inspect] sees
/// the directory before it is deleted.
ScriptRun runWithStubs(
  List<String> args, {
  Map<String, String> stubs = const {},
  Map<String, String> env = const {},
  Map<String, String> files = const {},
  void Function(Directory dir)? inspect,
}) {
  final dir = Directory.systemTemp.createTempSync('guard-stubs');
  String at(String s) => s.replaceAll('{dir}', dir.path);
  try {
    final bin = Directory('${dir.path}/bin')..createSync();
    for (final MapEntry(key: name, value: body) in stubs.entries) {
      File('${bin.path}/$name').writeAsStringSync(body);
      Process.runSync('chmod', ['+x', '${bin.path}/$name']);
    }
    for (final MapEntry(key: path, value: body) in files.entries) {
      File('${dir.path}/$path')
        ..createSync(recursive: true)
        ..writeAsStringSync(at(body));
    }
    final r = Process.runSync(
      'bash',
      args.map(at).toList(),
      workingDirectory: dir.path,
      includeParentEnvironment: false,
      environment: {
        'PATH': '${bin.path}:/usr/bin:/bin',
        'HOME': dir.path,
        'RUNNER_TEMP': dir.path,
        'LC_ALL': 'C',
        for (final MapEntry(:key, :value) in env.entries) key: at(value),
      },
    );
    inspect?.call(dir);
    return ScriptRun(
      r.exitCode,
      r.stdout as String,
      r.stderr as String,
      dir.path,
    );
  } finally {
    dir.deleteSync(recursive: true);
  }
}

/// The absolute path of a repository script, for [runWithStubs].
String tool(String name) => '${repoRoot.path}/tools/$name';

/// The JDK tool [name] (keytool, jarsigner), found the way the release
/// scripts find keytool: HS_KEYTOOL's directory, Homebrew's openjdk@21,
/// JAVA_HOME, then PATH. The macOS /usr/bin stubs are skipped.
String jdkTool(String name) {
  final env = Platform.environment;
  final candidates = [
    if (env['HS_KEYTOOL'] != null)
      '${File(env['HS_KEYTOOL']!).parent.path}/$name',
    '/opt/homebrew/opt/openjdk@21/bin/$name',
    if (env['JAVA_HOME'] != null) '${env['JAVA_HOME']}/bin/$name',
  ];
  for (final c in candidates) {
    if (File(c).existsSync()) return c;
  }
  final which = Process.runSync('which', [name]);
  final found = (which.stdout as String).trim();
  if (which.exitCode == 0 && found != '/usr/bin/$name') return found;
  throw StateError('guard: no $name found; set HS_KEYTOOL or JAVA_HOME');
}
