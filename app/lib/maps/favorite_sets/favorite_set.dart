import 'package:app/maps/layer_stack/layer_entry.dart';
import 'package:collection/collection.dart';

/// Сохранённый стек слоёв.
class FavoriteSet {
  const FavoriteSet({
    required this.id,
    required this.name,
    required this.layers,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String name;

  /// Слои целиком: источник, прозрачность, цвет, наложение.
  final List<LayerEntry> layers;

  /// Unix ms.
  final int createdAt;
  final int updatedAt;

  FavoriteSet copyWith({String? name, List<LayerEntry>? layers, int? updatedAt}) => FavoriteSet(
    id: id,
    name: name ?? this.name,
    layers: layers ?? this.layers,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'layers': [for (final l in layers) l.toJson()],
    'createdAt': createdAt,
    'updatedAt': updatedAt,
  };

  factory FavoriteSet.fromJson(Map<String, dynamic> json) => FavoriteSet(
    id: json['id'] as String,
    name: json['name'] as String,
    layers: [for (final l in json['layers'] as List<dynamic>) LayerEntry.fromJson(l as Map<String, dynamic>)],
    createdAt: json['createdAt'] as int,
    updatedAt: json['updatedAt'] as int,
  );

  static const _list = ListEquality<LayerEntry>();

  @override
  bool operator ==(Object other) =>
      other is FavoriteSet &&
      other.id == id &&
      other.name == name &&
      other.createdAt == createdAt &&
      other.updatedAt == updatedAt &&
      _list.equals(other.layers, layers);

  @override
  int get hashCode => Object.hash(id, name, createdAt, updatedAt, _list.hash(layers));
}
