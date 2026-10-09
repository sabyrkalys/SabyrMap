/// Цвет отрезка измерения по азимуту: на север (0° ± 45°) — красный, на юг
/// (180° ± 45°) — синий, между ними — плавный переход.
abstract final class MeasureColorScheme {
  static const int red = 0xFFFF0000;
  static const int blue = 0xFF0000FF;

  /// Цвет ARGB для азимута в градусах (любой, приводится к [0, 360)).
  static int colorFor(double azimuthDeg) {
    final a = azimuthDeg % 360;
    // Отклонение от севера, 0..180.
    final fromNorth = a > 180 ? 360 - a : a;
    if (fromNorth <= 45) return red;
    if (fromNorth >= 135) return blue;
    return _mix(red, blue, (fromNorth - 45) / 90);
  }

  static int _mix(int from, int to, double t) {
    int channel(int shift) {
      final a = (from >> shift) & 0xFF;
      final b = (to >> shift) & 0xFF;
      return (a + (b - a) * t).round() & 0xFF;
    }

    return 0xFF000000 | channel(16) << 16 | channel(8) << 8 | channel(0);
  }
}
