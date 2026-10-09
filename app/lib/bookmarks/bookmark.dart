import 'package:uuid/uuid.dart';

/// Закладка — ссылка на папку.
class Bookmark {
  const Bookmark({
    required this.id,
    required this.name,
    required this.path,
    required this.createdAt,
    required this.order,
  });

  /// Новая закладка со случайным id.
  factory Bookmark.create({required String name, required String path, required int createdAt, required int order}) =>
      Bookmark(id: const Uuid().v4(), name: name, path: path, createdAt: createdAt, order: order);

  final String id;

  /// Отображаемое имя.
  final String name;

  /// Абсолютный путь к папке.
  final String path;

  /// Unix ms.
  final int createdAt;

  /// Порядок добавления.
  final int order;

  Bookmark copyWith({String? name, String? path, int? order}) => Bookmark(
    id: id,
    name: name ?? this.name,
    path: path ?? this.path,
    createdAt: createdAt,
    order: order ?? this.order,
  );

  Map<String, Object?> toJson() => {'id': id, 'name': name, 'path': path, 'createdAt': createdAt, 'order': order};

  factory Bookmark.fromJson(Map<String, dynamic> json) => Bookmark(
    id: json['id'] as String,
    name: json['name'] as String,
    path: json['path'] as String,
    createdAt: json['createdAt'] as int? ?? 0,
    order: json['order'] as int? ?? 0,
  );

  @override
  bool operator ==(Object other) =>
      other is Bookmark &&
      other.id == id &&
      other.name == name &&
      other.path == path &&
      other.createdAt == createdAt &&
      other.order == order;

  @override
  int get hashCode => Object.hash(id, name, path, createdAt, order);

  @override
  String toString() => 'Bookmark($name → $path)';
}
