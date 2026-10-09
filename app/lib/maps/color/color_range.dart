/// Диапазон значений одного канала цвета.
class ColorRange {
  const ColorRange({required this.channel, required this.center, this.width = defaultWidth})
    : assert(channel >= 0 && channel <= 2),
      assert(center >= 0 && center <= 255),
      assert(width >= 1 && width <= 255);

  static const int defaultWidth = 5;

  /// 0 — R, 1 — G, 2 — B.
  final int channel;
  final int center;

  /// Допуск в обе стороны.
  final int width;

  /// |value − center| ≤ width.
  bool contains(int value) => (value - center).abs() <= width;

  /// Значение своего канала из ARGB.
  int channelOf(int argb) => (argb >> (16 - 8 * channel)) & 0xFF;

  Map<String, Object?> toJson() => {'channel': channel, 'center': center, 'width': width};

  factory ColorRange.fromJson(Map<String, dynamic> json) => ColorRange(
    channel: json['channel'] as int,
    center: json['center'] as int,
    width: json['width'] as int? ?? defaultWidth,
  );

  @override
  bool operator ==(Object other) =>
      other is ColorRange && other.channel == channel && other.center == center && other.width == width;

  @override
  int get hashCode => Object.hash(channel, center, width);
}
