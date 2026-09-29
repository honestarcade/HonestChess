/// [n] with its digits grouped in threes by a plain comma ("1,234"). The
/// app's strings are English, so the grouping does not follow the phone's
/// locale.
String formatCount(int n) {
  if (n < 0) return '-${formatCount(-n)}';
  final digits = '$n';
  final out = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) out.write(',');
    out.write(digits[i]);
  }
  return out.toString();
}

/// [n] out of [d] as a whole percentage, a half rounded up. Integer
/// arithmetic, so an exact half is never lost to a double's rounding. [d]
/// must be above 0: a caller with no games shows "—" instead.
int percentHalfUp(int n, int d) {
  assert(d > 0, 'percentHalfUp: nothing to divide by');
  return (200 * n + d) ~/ (2 * d);
}
