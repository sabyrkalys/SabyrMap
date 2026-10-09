/// Диапазон зумов.
class ZoomRange {
  const ZoomRange(this.min, this.max) : assert(min <= max);

  /// `1-17` или одно число; неверная строка — [FormatException].
  factory ZoomRange.parse(String text) {
    final m = RegExp(r'^\s*(\d{1,2})\s*(?:[-–:]\s*(\d{1,2}))?\s*$').firstMatch(text);
    if (m == null) throw FormatException('Invalid zoom range', text);
    final a = int.parse(m[1]!);
    final b = m[2] == null ? a : int.parse(m[2]!);
    if (a > b) throw FormatException('Zoom range min is above max', text);
    return ZoomRange(a, b);
  }

  final int min;
  final int max;

  bool includes(int z) => min <= z && z <= max;

  @override
  bool operator ==(Object other) => other is ZoomRange && other.min == min && other.max == max;

  @override
  int get hashCode => Object.hash(min, max);

  @override
  String toString() => '$min-$max';
}
