import 'layer_color_settings.dart';

/// Цветокоррекция пикселя (без состояния).
class LayerColorController {
  const LayerColorController();

  /// Применяет [s] к пикселю ARGB по порядку: контраст, яркость,
  /// насыщенность, оттенок (умножение, сила — альфа оттенка), инверсия.
  /// Каналы ограничиваются [0, 255]; альфа пикселя не меняется.
  static int applyToPixel(int argb, LayerColorSettings s) {
    final alpha = (argb >> 24) & 0xFF;
    var r = ((argb >> 16) & 0xFF).toDouble();
    var g = ((argb >> 8) & 0xFF).toDouble();
    var b = (argb & 0xFF).toDouble();

    double contrast(double c) => _clip((c - 128) * s.contrast + 128);
    r = contrast(r);
    g = contrast(g);
    b = contrast(b);

    final shift = s.brightness * 255;
    r = _clip(r + shift);
    g = _clip(g + shift);
    b = _clip(b + shift);

    final gray = 0.299 * r + 0.587 * g + 0.114 * b;
    r = _clip(gray + (r - gray) * s.saturation);
    g = _clip(gray + (g - gray) * s.saturation);
    b = _clip(gray + (b - gray) * s.saturation);

    final tint = s.tint;
    if (tint != null) {
      final strength = ((tint >> 24) & 0xFF) / 255;
      double multiply(double c, int t) => _clip(c * (1 - strength) + (c * t / 255) * strength);
      r = multiply(r, (tint >> 16) & 0xFF);
      g = multiply(g, (tint >> 8) & 0xFF);
      b = multiply(b, tint & 0xFF);
    }

    if (s.inverted) {
      r = 255 - r;
      g = 255 - g;
      b = 255 - b;
    }
    return alpha << 24 | r.round() << 16 | g.round() << 8 | b.round();
  }

  static double _clip(double v) => v < 0 ? 0 : (v > 255 ? 255 : v);
}
