// Structural access to GitHub Actions workflows, for the workflow guards.
//
// Workflows are read with package:yaml rather than scanned as text: a flow
// mapping, a quoted scalar or a value on the next line reads differently as
// text but means the same to the runner.
import 'package:yaml/yaml.dart';

import 'repo_files.dart';

/// Parses [text] as a workflow document. Throws, naming [path], when it is not
/// a mapping with a `jobs:` mapping, so a guard never passes by reading
/// nothing.
YamlMap parseWorkflow(String text, {String path = '<fixture>'}) {
  final doc = loadYaml(text);
  if (doc is! YamlMap || doc['jobs'] is! YamlMap) {
    throw StateError('workflow: $path has no jobs: mapping');
  }
  return doc;
}

YamlMap readWorkflow(String path) => parseWorkflow(readFile(path), path: path);

/// Every tracked workflow file.
List<String> workflowFiles() =>
    trackedFilesUnder('.github/workflows')
        .where((p) => p.endsWith('.yml') || p.endsWith('.yaml'))
        .toList();

/// The `on:` block. YAML 1.1 readers turn a bare `on` key into `true`.
Object? triggers(YamlMap workflow) => workflow['on'] ?? workflow[true];

YamlMap jobsOf(YamlMap workflow) => workflow['jobs'] as YamlMap;

/// The steps of [job], or none for a job that `uses:` another workflow.
List<YamlMap> stepsOf(Object? job) {
  if (job is! YamlMap) return const [];
  final steps = job['steps'];
  return steps is YamlList ? steps.whereType<YamlMap>().toList() : const [];
}

/// A step's label for a failure message: its `id:`, else its `name:`.
String stepLabel(YamlMap step) => '${step['id'] ?? step['name'] ?? '?'}';
