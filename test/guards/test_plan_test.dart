@Tags(['guard'])
library;

// The test plan keeps up with the app (#106): every screen route, every
// Settings row, every strength step, clock, colour and board look in the
// code has a place in qa/test-plan.md, so a screen or option added later
// cannot go untested on the phone by omission; and nothing in the plan's
// route lines or sampling table names something the code no longer has.
// The run-record template keeps its header fields, and every committed run
// record keeps the naming the M6 stories agreed on.
//
// What this does not check: whether an Expected line is right about the app
// (the runs are how that is found out), the steps themselves, or the
// contents of a run record beyond its name.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:honest_chess/engine/engine.dart';
import 'package:honest_chess/ui/board/board_options.dart';
import 'package:honest_chess/ui/game/defaults.dart';

import 'repo_files.dart';

const planPath = 'qa/test-plan.md';
const templatePath = 'qa/runs/TEMPLATE.md';
const navigationPath = 'lib/ui/navigation.dart';
const settingsPath = 'lib/ui/screens/settings_screen.dart';

/// The states with no route of their own that must each have a section.
const requiredHeadings = [
  'Install',
  'Splash',
  'Menu',
  'Promotion card',
  'Pause card',
  'Declined-draw card',
  'Result card',
  'View board',
  'Gestures',
  'Persistence',
  'Feedback',
];

/// The sampling table's option columns, besides one per Settings row.
const modeColumn = 'Mode';
const stepColumn = 'Step';
const colourColumn = 'Play as';
const clockColumn = 'Clock';
const themeColumn = 'Board colour';
const styleColumn = 'Pieces';
const surfaceColumn = 'Surface';
const fixedColumns = ['Run', 'Notes'];

/// The Settings row that applies to two-player games only, so both its
/// states must be sampled in a two-player run.
const twoPlayerOnlyRow = 'rotate';

const notApplicable = 'n/a';

/// `YYYY-MM-DD-<device>-<who>[-n].md`.
final runRecordName = RegExp(
  r'^\d{4}-\d{2}-\d{2}-(s26ultra|emu-api24|emu-api34)-(owner|agent)(-\d+)?\.md$',
);

/// The template's header fields (shared M6 conventions).
const templateFields = [
  'Build',
  'Device',
  'Android / One UI',
  'Hardware or emulator',
  'AVD and image',
  'Runs',
  'Run by',
];

final checkHeading = RegExp(r'^### (T\d{3}) — (.+)$');
final routeLine = RegExp(r'^route: (\S+)\s*$');
final customClock = RegExp(r'^custom (\d+)\+(\d+)$');
final citedPath = RegExp(r'(?:^|; )((?:test|integration_test)/[\w/]+\.dart)');

class Check {
  Check(this.id, this.title, this.lines);

  final String id;
  final String title;
  final List<String> lines;

  bool get retired => title.contains('(retired');
}

/// The plan's `##` sections, heading → lines.
Map<String, List<String>> sections(String text) {
  final out = <String, List<String>>{};
  List<String>? current;
  for (final line in text.split('\n')) {
    if (line.startsWith('## ')) {
      current = out[line.substring(3).trim()] = [];
    } else {
      current?.add(line);
    }
  }
  return out;
}

/// The `###` checks in [lines], each with the lines up to the next heading.
List<Check> checksIn(List<String> lines) {
  final out = <Check>[];
  Check? current;
  for (final line in lines) {
    final m = checkHeading.firstMatch(line);
    if (m != null) {
      current = Check(m[1]!, m[2]!, []);
      out.add(current);
    } else if (line.startsWith('#')) {
      current = null;
    } else {
      current?.lines.add(line);
    }
  }
  return out;
}

List<String> cells(String row) {
  final parts = row.trim().split('|');
  return parts.sublist(1, parts.length - 1).map((c) => c.trim()).toList();
}

/// The sampling table's header and its rows as column → cell.
({List<String> columns, List<Map<String, String>> rows}) samplingTable(
  List<String> section,
) {
  final header = section.firstWhere(
    (l) => RegExp(r'^\|\s*Run\s*\|').hasMatch(l),
    orElse: () => '',
  );
  if (header.isEmpty) return (columns: const [], rows: const []);
  final columns = cells(header);
  return (
    columns: columns,
    rows: [
      for (final line in section)
        if (RegExp(r'^\|\s*R\d+\s*\|').hasMatch(line))
          {
            for (final (i, cell) in cells(line).indexed)
              if (i < columns.length) columns[i]: cell,
          },
    ],
  );
}

/// The screen route names: every `const <x>RouteName = '<name>';`.
Map<String, String> routeNames() => {
  for (final m in RegExp(
    r"^const (\w+RouteName) = '([^']+)';",
    multiLine: true,
  ).allMatches(readFile(navigationPath)))
    m[1]!: m[2]!,
};

/// The Settings switches, id → label, read from the `_toggles` table.
Map<String, String> settingRows() {
  final source = readFile(settingsPath);
  final start = source.indexOf('final List<_Toggle> _toggles = [');
  if (start < 0) return const {};
  final end = source.indexOf('\n];', start);
  final table = source.substring(start, end < 0 ? source.length : end);
  return {
    for (final m in RegExp(
      r"id: '([^']+)',\s*group: '[^']*',\s*label: '([^']+)'",
    ).allMatches(table))
      m[1]!: m[2]!,
  };
}

/// The Settings rows that are not switches (#181's slider), read from
/// every `const <x>RowLabel = '<label>';` in the Settings screen.
List<String> otherSettingRows() => [
  for (final m in RegExp(
    r'''^const \w+RowLabel = (?:'([^']+)'|"([^"]+)");''',
    multiLine: true,
  ).allMatches(readFile(settingsPath)))
    m[1] ?? m[2]!,
];

/// [name] compared the way the table writes an enum value: any case, any
/// spacing ("vs computer" for `vsComputer`).
String squash(String name) => name.replaceAll(' ', '').toLowerCase();

/// A clock cell's [TimeChoice], or null when it names none.
TimeChoice? clockChoice(String cell) {
  if (customClock.hasMatch(cell)) return TimeChoice.custom;
  for (final c in TimeChoice.values) {
    if (c != TimeChoice.custom && squash(cell) == c.name) return c;
  }
  return null;
}

/// The colour choice a Play as cell names: `white`, `black`, or `random`
/// with the colour it drew in brackets.
ColourChoice? colourChoice(String cell) {
  final lower = cell.toLowerCase();
  if (RegExp(r'^random \((white|black)\)$').hasMatch(lower) ||
      lower == 'random') {
    return ColourChoice.random;
  }
  for (final c in ColourChoice.values) {
    if (lower == c.name) return c;
  }
  return null;
}

void main() {
  final plan = readFile(planPath);
  final bySection = sections(plan);
  final checks = checksIn(plan.split('\n'));
  final table = samplingTable(bySection['Sampling'] ?? const []);
  final rows = table.rows;
  final toggles = settingRows();

  test('the sources the guard reads still parse', () {
    expect(
      routeNames(),
      isNotEmpty,
      reason: 'test-plan: no *RouteName constants parsed from $navigationPath',
    );
    expect(
      toggles,
      isNotEmpty,
      reason: 'test-plan: no Settings rows parsed from $settingsPath',
    );
    expect(rows, isNotEmpty, reason: 'test-plan: no sampling table rows');
  });

  test('every screen route has a route line, and every route line a '
      'route', () {
    final routes = routeNames();
    final named = <String>[
      for (final line in plan.split('\n'))
        if (routeLine.firstMatch(line) case final m?) m[1]!,
    ];
    final wrong = [
      for (final MapEntry(key: constant, value: name) in routes.entries)
        if (!named.contains(name))
          'test-plan: route $name ($constant) has no "route: $name" line',
      for (final name in named)
        if (!routes.containsValue(name))
          'test-plan: "route: $name" names no route in $navigationPath',
    ];
    expect(wrong, isEmpty, reason: wrong.join('\n'));
  });

  test('every state without a route has its section, holding a check', () {
    final wrong = <String>[];
    for (final h in requiredHeadings) {
      final lines = bySection[h];
      if (lines == null) {
        wrong.add('test-plan: no "## $h" heading');
      } else if (!lines.any(checkHeading.hasMatch)) {
        wrong.add('test-plan: "## $h" holds no T-check');
      }
    }
    expect(wrong, isEmpty, reason: wrong.join('\n'));
  });

  test('every Settings row is named in the Settings section', () {
    final text = (bySection['Settings'] ?? const []).join('\n');
    final missing = [
      for (final MapEntry(key: id, value: label) in toggles.entries)
        if (!text.contains(label))
          'test-plan: Settings row "$label" ($id) is not in the Settings '
              'section',
      for (final label in otherSettingRows())
        if (!text.contains(label))
          'test-plan: Settings row "$label" is not in the Settings section',
    ];
    expect(missing, isEmpty, reason: missing.join('\n'));
  });

  test('every step description is quoted in the plan as the app shows '
      'it', () {
    final missing = [
      for (final s in Strength.values)
        if (!plan.contains(s.description))
          "test-plan: Strength.${s.name}'s description is not quoted in the "
              'plan word for word',
    ];
    expect(missing, isEmpty, reason: missing.join('\n'));
  });

  test('every option value in the code appears in the sampling table', () {
    final missing = <String>[];
    final computer = rows.where(
      (r) =>
          squash(r[modeColumn] ?? '') == GameKind.vsComputer.name.toLowerCase(),
    );
    final two = rows.where(
      (r) =>
          squash(r[modeColumn] ?? '') == GameKind.twoPlayers.name.toLowerCase(),
    );

    void need(
      String what,
      String column,
      Iterable<Map<String, String>> among,
      Iterable<String> values,
      bool Function(String cell, String value) matches,
    ) {
      if (!table.columns.contains(column)) {
        missing.add('test-plan: sampling table has no "$column" column');
        return;
      }
      for (final v in values) {
        if (!among.any((r) => matches(r[column] ?? '', v))) {
          missing.add('test-plan: sampling table lacks $what=$v');
        }
      }
    }

    bool same(String cell, String value) => squash(cell) == squash(value);

    need('mode', modeColumn, rows, [
      for (final k in GameKind.values) k.name,
    ], same);
    need('step', stepColumn, computer, [
      for (final s in Strength.values) s.name,
    ], same);
    need('play as', colourColumn, computer, [
      for (final c in ColourChoice.values) c.name,
    ], (cell, v) => colourChoice(cell)?.name == v);
    need('clock', clockColumn, rows, [
      for (final c in TimeChoice.values) c.name,
    ], (cell, v) => clockChoice(cell)?.name == v);
    need('clock', clockColumn, rows, [
      'custom $customMinutesMin+$customIncrementMin',
      'custom $customMinutesMax+$customIncrementMax',
    ], same);
    need('board colour', themeColumn, rows, [
      for (final t in BoardTheme.values) t.name,
    ], same);
    need('pieces', styleColumn, rows, [
      for (final s in PieceStyle.values) s.name,
    ], same);
    need('surface', surfaceColumn, rows, [
      for (final s in BoardSurface.values) s.name,
    ], same);
    for (final id in toggles.keys) {
      need(id, id, id == twoPlayerOnlyRow ? two : rows, ['on', 'off'], same);
    }
    expect(missing, isEmpty, reason: missing.join('\n'));
  });

  test('every sampling column and value exists in the code', () {
    final wrong = <String>[];
    final known = {
      ...fixedColumns,
      modeColumn,
      stepColumn,
      colourColumn,
      clockColumn,
      themeColumn,
      styleColumn,
      surfaceColumn,
      ...toggles.keys,
    };
    for (final c in table.columns) {
      if (!known.contains(c)) {
        wrong.add('test-plan: sampling column "$c" is no option in the code');
      }
    }
    bool isName(String cell, Iterable<Enum> values) =>
        values.any((v) => squash(cell) == v.name.toLowerCase());

    for (final r in rows) {
      final run = r['Run'];
      final computer =
          squash(r[modeColumn] ?? '') == GameKind.vsComputer.name.toLowerCase();
      void check(String column, bool ok, String what) {
        final cell = r[column];
        if (cell == null || !ok) {
          wrong.add('test-plan: $run\'s $column "$cell" is not $what');
        }
      }

      String cell(String c) => r[c] ?? '';
      check(
        modeColumn,
        isName(cell(modeColumn), GameKind.values),
        'a GameKind',
      );
      if (computer) {
        check(
          stepColumn,
          isName(cell(stepColumn), Strength.values),
          'a Strength',
        );
        check(
          colourColumn,
          colourChoice(cell(colourColumn)) != null,
          'a ColourChoice',
        );
      } else {
        check(stepColumn, cell(stepColumn) == notApplicable, notApplicable);
        check(colourColumn, cell(colourColumn) == notApplicable, notApplicable);
      }
      final clock = cell(clockColumn);
      check(clockColumn, clockChoice(clock) != null, 'a TimeChoice');
      if (customClock.firstMatch(clock) case final m?) {
        final minutes = int.parse(m[1]!);
        final increment = int.parse(m[2]!);
        check(
          clockColumn,
          minutes >= customMinutesMin &&
              minutes <= customMinutesMax &&
              increment >= customIncrementMin &&
              increment <= customIncrementMax,
          'a custom time the steppers allow',
        );
      }
      check(
        themeColumn,
        isName(cell(themeColumn), BoardTheme.values),
        'a BoardTheme',
      );
      check(
        styleColumn,
        isName(cell(styleColumn), PieceStyle.values),
        'a PieceStyle',
      );
      check(
        surfaceColumn,
        isName(cell(surfaceColumn), BoardSurface.values),
        'a BoardSurface',
      );
      for (final id in toggles.keys) {
        check(id, const ['on', 'off'].contains(cell(id)), 'on or off');
      }
    }
    expect(wrong, isEmpty, reason: wrong.join('\n'));
  });

  test('check headings are well-formed and their IDs unique', () {
    final malformed = [
      for (final line in plan.split('\n'))
        if (line.startsWith('### ') && !checkHeading.hasMatch(line))
          'test-plan: malformed check heading "$line"',
    ];
    final seen = <String>{};
    final duplicates = [
      for (final c in checks)
        if (!seen.add(c.id)) 'test-plan: ${c.id} is used twice',
    ];
    expect(checks, isNotEmpty, reason: 'test-plan: no T-checks parsed');
    expect(
      [...malformed, ...duplicates],
      isEmpty,
      reason: [...malformed, ...duplicates].join('\n'),
    );
  });

  test('every live check has Steps, Expected, Core and Where lines', () {
    final wrong = <String>[];
    for (final c in checks) {
      if (c.retired) continue;
      String? field(String name) => c.lines
          .where((l) => l.startsWith('$name:'))
          .map((l) => l.substring(name.length + 1).trim())
          .firstOrNull;
      if (field('Steps') == null) {
        wrong.add('test-plan: ${c.id} has no Steps:');
      }
      if (field('Expected') == null) {
        wrong.add('test-plan: ${c.id} has no Expected:');
      }
      if (!const ['yes', 'no'].contains(field('Core'))) {
        wrong.add('test-plan: ${c.id} has no Core: yes|no');
      }
      if (!const ['phone', 'emulator', 'both'].contains(field('Where'))) {
        wrong.add('test-plan: ${c.id} has no Where: phone|emulator|both');
      }
    }
    expect(wrong, isEmpty, reason: wrong.join('\n'));
  });

  test('every Automated citation names a file that exists', () {
    final missing = <String>[];
    for (final c in checks) {
      for (final line in c.lines) {
        if (!line.startsWith('Automated:')) continue;
        final value = line.substring('Automated:'.length).trim();
        if (value == 'none') continue;
        // Each citation is a path, optionally followed by ` — <test name>`,
        // and citations are separated by `; `; a test name may itself hold
        // `; `, so the paths are found by their shape.
        final paths = [for (final m in citedPath.allMatches(value)) m[1]!];
        if (paths.isEmpty) {
          missing.add(
            'test-plan: ${c.id} has an Automated line naming no test',
          );
        }
        for (final path in paths) {
          if (!pathExists(path)) {
            missing.add('test-plan: ${c.id} cites $path, which does not exist');
          }
        }
      }
    }
    expect(missing, isEmpty, reason: missing.join('\n'));
  });

  test('the run-record template has its header fields and table', () {
    final template = readFile(templatePath);
    final missing = [
      for (final f in templateFields)
        if (!RegExp(
          '^- ${RegExp.escape(f)}:',
          multiLine: true,
        ).hasMatch(template))
          'test-plan: TEMPLATE.md lacks the header field "$f:"',
      if (!RegExp(
        r'^\|\s*check\s*\|\s*result\s*\|\s*bug\s*\|',
        multiLine: true,
      ).hasMatch(template))
        'test-plan: TEMPLATE.md lacks the check | result | bug table',
    ];
    expect(missing, isEmpty, reason: missing.join('\n'));
  });

  test('the run-record name pattern', () {
    for (final good in [
      '2026-09-30-s26ultra-owner.md',
      '2026-10-01-emu-api24-agent.md',
      '2026-10-01-emu-api34-agent-2.md',
    ]) {
      expect(runRecordName.hasMatch(good), isTrue, reason: good);
    }
    for (final bad in [
      '2026-09-30-s26-owner.md',
      '2026-9-30-s26ultra-owner.md',
      '2026-09-30-s26ultra-claude.md',
      '2026-09-30-emu-dev-agent.md',
      '2026-09-30-s26ultra-owner.txt',
    ]) {
      expect(runRecordName.hasMatch(bad), isFalse, reason: bad);
    }
  });

  test('every committed run record is named by the pattern', () {
    final dir = Directory('${repoRoot.path}/qa/runs');
    expect(dir.existsSync(), isTrue, reason: 'test-plan: qa/runs is missing');
    final misnamed = [
      for (final entry in dir.listSync())
        if (entry is File)
          if (entry.uri.pathSegments.last case final name
              when name != 'TEMPLATE.md' && !runRecordName.hasMatch(name))
            'test-plan: misnamed run record qa/runs/$name',
    ];
    expect(misnamed, isEmpty, reason: misnamed.join('\n'));
  });
}
