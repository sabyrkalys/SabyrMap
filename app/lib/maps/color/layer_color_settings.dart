/// Цветокоррекция слоя.
class LayerColorSettings {
  const LayerColorSettings({
    this.contrast = 1.0,
    this.brightness = 0.0,
    this.saturation = 1.0,
    this.tint,
    this.inverted = false,
  });

  /// Без изменений.
  static LayerColorSettings identity() => const LayerColorSettings();

  /// 0..2, 1 — без изменений.
  final double contrast;

  /// −1..1, 0 — без изменений.
  final double brightness;

  /// 0..2, 1 — без изменений, 0 — серый.
  final double saturation;

  /// Оттенок ARGB (альфа — сила), наложение умножением.
  final int? tint;
  final bool inverted;

  bool get isIdentity => this == const LayerColorSettings();

  static const Object _keep = Object();

  LayerColorSettings copyWith({
    double? contrast,
    double? brightness,
    double? saturation,
    Object? tint = _keep,
    bool? inverted,
  }) => LayerColorSettings(
    contrast: contrast ?? this.contrast,
    brightness: brightness ?? this.brightness,
    saturation: saturation ?? this.saturation,
    tint: identical(tint, _keep) ? this.tint : tint as int?,
    inverted: inverted ?? this.inverted,
  );

  Map<String, Object?> toJson() => {
    'contrast': contrast,
    'brightness': brightness,
    'saturation': saturation,
    'tint': tint,
    'inverted': inverted,
  };

  factory LayerColorSettings.fromJson(Map<String, dynamic> json) => LayerColorSettings(
    contrast: (json['contrast'] as num?)?.toDouble() ?? 1.0,
    brightness: (json['brightness'] as num?)?.toDouble() ?? 0.0,
    saturation: (json['saturation'] as num?)?.toDouble() ?? 1.0,
    tint: json['tint'] as int?,
    inverted: json['inverted'] as bool? ?? false,
  );

  @override
  bool operator ==(Object other) =>
      other is LayerColorSettings &&
      other.contrast == contrast &&
      other.brightness == brightness &&
      other.saturation == saturation &&
      other.tint == tint &&
      other.inverted == inverted;

  @override
  int get hashCode => Object.hash(contrast, brightness, saturation, tint, inverted);
}
