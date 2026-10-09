import 'package:app/maps/color/erase_color_settings.dart';
import 'package:app/maps/color/layer_color_settings.dart';

import 'layer_blending.dart';

/// Слой в стеке карты.
class LayerEntry {
  const LayerEntry({
    required this.id,
    required this.sourceId,
    this.filePath,
    this.order = 0,
    this.opacity = 1.0,
    this.visible = true,
    this.color = const LayerColorSettings(),
    this.eraseColor,
    this.blending = LayerBlending.normal,
  });

  /// Уникален в стеке.
  final String id;

  /// id в [MapSourceRegistry].
  final String sourceId;

  /// Для файловых карт.
  final String? filePath;

  /// Место в стеке, 0 — нижний.
  final int order;

  /// 0..1.
  final double opacity;
  final bool visible;
  final LayerColorSettings color;
  final EraseColorSettings? eraseColor;
  final LayerBlending blending;

  static const Object _keep = Object();

  LayerEntry copyWith({
    String? id,
    String? sourceId,
    Object? filePath = _keep,
    int? order,
    double? opacity,
    bool? visible,
    LayerColorSettings? color,
    Object? eraseColor = _keep,
    LayerBlending? blending,
  }) => LayerEntry(
    id: id ?? this.id,
    sourceId: sourceId ?? this.sourceId,
    filePath: identical(filePath, _keep) ? this.filePath : filePath as String?,
    order: order ?? this.order,
    opacity: opacity ?? this.opacity,
    visible: visible ?? this.visible,
    color: color ?? this.color,
    eraseColor: identical(eraseColor, _keep) ? this.eraseColor : eraseColor as EraseColorSettings?,
    blending: blending ?? this.blending,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'sourceId': sourceId,
    'filePath': filePath,
    'order': order,
    'opacity': opacity,
    'visible': visible,
    'color': color.toJson(),
    'eraseColor': eraseColor?.toJson(),
    'blending': blending.name,
  };

  factory LayerEntry.fromJson(Map<String, dynamic> json) => LayerEntry(
    id: json['id'] as String,
    sourceId: json['sourceId'] as String,
    filePath: json['filePath'] as String?,
    order: json['order'] as int? ?? 0,
    opacity: (json['opacity'] as num?)?.toDouble() ?? 1.0,
    visible: json['visible'] as bool? ?? true,
    color: json['color'] is Map<String, dynamic>
        ? LayerColorSettings.fromJson(json['color'] as Map<String, dynamic>)
        : const LayerColorSettings(),
    eraseColor: json['eraseColor'] is Map<String, dynamic>
        ? EraseColorSettings.fromJson(json['eraseColor'] as Map<String, dynamic>)
        : null,
    blending: LayerBlending.values.where((b) => b.name == json['blending']).firstOrNull ?? LayerBlending.normal,
  );

  @override
  bool operator ==(Object other) =>
      other is LayerEntry &&
      other.id == id &&
      other.sourceId == sourceId &&
      other.filePath == filePath &&
      other.order == order &&
      other.opacity == opacity &&
      other.visible == visible &&
      other.color == color &&
      other.eraseColor == eraseColor &&
      other.blending == blending;

  @override
  int get hashCode => Object.hash(id, sourceId, filePath, order, opacity, visible, color, eraseColor, blending);
}
