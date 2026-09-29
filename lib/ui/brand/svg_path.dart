import 'dart:ui';

/// Parses SVG path data [d] written with absolute `M`, `L`, `H`, `V`, `A`
/// and `Z` commands only — what the brand marks are drawn with — into a
/// [Path]. A command's parameters may repeat (after `M`, extra pairs are
/// lines, as in SVG). Any other command letter, relative ones included, a
/// malformed number or a command left short of parameters throws a
/// [FormatException].
Path parseSvgPath(String d) {
  final path = Path();
  final tokens = RegExp(r'[A-Za-z]|[^A-Za-z\s,]+').allMatches(d);
  String? command;
  final args = <double>[];
  var x = 0.0, y = 0.0;

  void run() {
    switch (command) {
      case 'M' || 'L' when args.length == 2:
        x = args[0];
        y = args[1];
        command == 'M' ? path.moveTo(x, y) : path.lineTo(x, y);
        // Further pairs after a move are lines.
        if (command == 'M') command = 'L';
      case 'H' when args.length == 1:
        x = args[0];
        path.lineTo(x, y);
      case 'V' when args.length == 1:
        y = args[0];
        path.lineTo(x, y);
      case 'A' when args.length == 7:
        x = args[5];
        y = args[6];
        path.arcToPoint(
          Offset(x, y),
          radius: Radius.elliptical(args[0], args[1]),
          rotation: args[2],
          largeArc: args[3] != 0,
          clockwise: args[4] != 0,
        );
      default:
        return;
    }
    args.clear();
  }

  for (final match in tokens) {
    final token = match[0]!;
    if (RegExp(r'^[A-Za-z]$').hasMatch(token)) {
      if (args.isNotEmpty) {
        throw FormatException('svg-path: $command is short of parameters', d);
      }
      if (!const {'M', 'L', 'H', 'V', 'A', 'Z'}.contains(token)) {
        throw FormatException('svg-path: unsupported command $token', d);
      }
      command = token;
      if (token == 'Z') path.close();
      continue;
    }
    final value = double.tryParse(token);
    if (value == null) {
      throw FormatException('svg-path: malformed number $token', d);
    }
    if (command == null || command == 'Z') {
      throw FormatException('svg-path: number $token outside a command', d);
    }
    args.add(value);
    run();
  }
  if (args.isNotEmpty) {
    throw FormatException('svg-path: $command is short of parameters', d);
  }
  return path;
}
