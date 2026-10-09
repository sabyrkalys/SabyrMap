import 'package:uuid/uuid.dart';

/// Рабочее пространство: своё состояние карты, слоёв и оповещений.
class Workspace {
  const Workspace({required this.id, required this.name, required this.createdAt, required this.updatedAt});

  /// Новое пространство со случайным UUID.
  factory Workspace.create(String name, {required int now}) =>
      Workspace(id: const Uuid().v4(), name: name, createdAt: now, updatedAt: now);

  final String id;
  final String name;

  /// Unix ms.
  final int createdAt;
  final int updatedAt;

  Workspace copyWith({String? name, int? updatedAt}) =>
      Workspace(id: id, name: name ?? this.name, createdAt: createdAt, updatedAt: updatedAt ?? this.updatedAt);

  Map<String, Object?> toJson() => {'id': id, 'name': name, 'createdAt': createdAt, 'updatedAt': updatedAt};

  factory Workspace.fromJson(Map<String, dynamic> json) => Workspace(
    id: json['id'] as String,
    name: json['name'] as String,
    createdAt: json['createdAt'] as int,
    updatedAt: json['updatedAt'] as int,
  );

  @override
  bool operator ==(Object other) =>
      other is Workspace &&
      other.id == id &&
      other.name == name &&
      other.createdAt == createdAt &&
      other.updatedAt == updatedAt;

  @override
  int get hashCode => Object.hash(id, name, createdAt, updatedAt);
}
