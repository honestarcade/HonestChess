// Reads app_identity.yaml, the single source of the app's identity.
//
// tools/rename_app.py writes it; android_identity_test.dart asserts every
// file that repeats one of its values agrees with it.
import 'package:yaml/yaml.dart';

import 'repo_files.dart';

const identityPath = 'app_identity.yaml';

const orientations = ['portrait', 'landscape', 'any'];
const knownPlatforms = ['android', 'ios', 'macos', 'linux', 'windows', 'web'];

class AppIdentity {
  AppIdentity({
    required this.packageId,
    required this.label,
    required this.dartPackage,
    required this.slug,
    required this.minSdk,
    required this.orientation,
    required this.platforms,
  });

  final String packageId;
  final String label;
  final String dartPackage;
  final String slug;
  final int minSdk;
  final String orientation;
  final List<String> platforms;

  /// The Kotlin source directory MainActivity lives in.
  String get kotlinDir =>
      'android/app/src/main/kotlin/${packageId.replaceAll('.', '/')}';
}

/// Every way [yamlText] fails to be a usable identity. Empty means valid.
List<String> identityProblems(String yamlText) {
  final Object? parsed;
  try {
    parsed = loadYaml(yamlText);
  } on YamlException catch (e) {
    return ['does not parse: ${e.message}'];
  }
  if (parsed is! YamlMap) return ['is not a mapping'];
  final doc = parsed;
  final problems = <String>[];
  String? str(String key, RegExp shape) {
    final v = doc[key];
    if (v is! String || !shape.hasMatch(v)) {
      problems.add('$key is ${v == null ? 'missing' : '"$v"'}');
      return null;
    }
    return v;
  }

  str('package_id', RegExp(r'^[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)+$'));
  str('label', RegExp(r'''^[^"'\\$`}<>&]*\S[^"'\\$`}<>&]*$'''));
  str('dart_package', RegExp(r'^[a-z][a-z0-9_]*$'));
  str('slug', RegExp(r'^[a-z][a-z0-9-]{3,26}$'));
  final minSdk = doc['min_sdk'];
  if (minSdk is! int || minSdk < 21 || minSdk > 40) {
    problems.add('min_sdk is ${minSdk ?? 'missing'}');
  }
  if (!orientations.contains(doc['orientation'])) {
    problems.add('orientation is ${doc['orientation'] ?? 'missing'}');
  }
  final platforms = doc['platforms'];
  if (platforms is! YamlList ||
      !platforms.contains('android') ||
      platforms.any((p) => !knownPlatforms.contains(p))) {
    problems.add('platforms is ${platforms ?? 'missing'}');
  }
  return problems;
}

/// The repository's identity. Throws, naming the problems, if it is invalid.
AppIdentity readIdentity() {
  final text = readFile(identityPath);
  final problems = identityProblems(text);
  if (problems.isNotEmpty) {
    throw StateError('app-identity: $identityPath ${problems.join('; ')}');
  }
  final doc = loadYaml(text) as YamlMap;
  return AppIdentity(
    packageId: doc['package_id'] as String,
    label: doc['label'] as String,
    dartPackage: doc['dart_package'] as String,
    slug: doc['slug'] as String,
    minSdk: doc['min_sdk'] as int,
    orientation: doc['orientation'] as String,
    platforms: (doc['platforms'] as YamlList).cast<String>().toList(),
  );
}
