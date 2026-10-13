import '../../maps/color/erase_color_settings.dart';
import '../../maps/color/layer_color_settings.dart';
import '../../maps/layer_stack/layer_blending.dart';

/// How one overlay is drawn beyond its opacity: colour correction, colour
/// erasing and blending. Lives for the session; kept between runs only in
/// a favourite set ([MapPreset.looks]).
class LayerLook {
  const LayerLook({
    this.color = const LayerColorSettings(),
    this.erase = const EraseColorSettings(),
    this.blending = LayerBlending.normal,
    this.forceRefresh = false,
  });

  final LayerColorSettings color;
  final EraseColorSettings erase;
  final LayerBlending blending;

  /// Re-download the layer's saved tiles; this session only, never saved.
  final bool forceRefresh;

  bool get isDefault => this == const LayerLook();

  LayerLook copyWith({LayerColorSettings? color, EraseColorSettings? erase, LayerBlending? blending, bool? forceRefresh}) =>
      LayerLook(
        color: color ?? this.color,
        erase: erase ?? this.erase,
        blending: blending ?? this.blending,
        forceRefresh: forceRefresh ?? this.forceRefresh,
      );

  factory LayerLook.fromJson(Map<String, dynamic> json) => LayerLook(
        color: LayerColorSettings.fromJson(json['color'] as Map<String, dynamic>? ?? const {}),
        erase: EraseColorSettings.fromJson(json['erase'] as Map<String, dynamic>? ?? const {}),
        blending: LayerBlending.values.asNameMap()[json['blending']] ?? LayerBlending.normal,
      );

  Map<String, dynamic> toJson() => {
        'color': color.toJson(),
        'erase': erase.toJson(),
        'blending': blending.name,
      };

  @override
  bool operator ==(Object other) =>
      other is LayerLook &&
      other.color == color &&
      other.erase == erase &&
      other.blending == blending &&
      other.forceRefresh == forceRefresh;

  @override
  int get hashCode => Object.hash(color, erase, blending, forceRefresh);
}
