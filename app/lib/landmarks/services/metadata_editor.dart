import 'dart:typed_data';

import 'package:app/exceptions/serialization_exception.dart';
import 'package:app/landmarks/drafts/metadata_patch.dart';
import 'package:app/landmarks/models/landmark_metadata.dart';

/// Правка и проверка [LandmarkMetadata].
class MetadataEditor {
  const MetadataEditor({DateTime Function()? clock}) : _clock = clock;

  final DateTime Function()? _clock;

  DateTime _now() => (_clock ?? DateTime.now)();

  /// Применяет [patch]: сначала удаления, затем установки; version + 1,
  /// `updated_at` = сейчас, `created_at` = сейчас, если его не было.
  /// Несериализуемое значение в патче — [SerializationException].
  LandmarkMetadata apply(LandmarkMetadata source, MetadataPatch patch) {
    final now = _now().millisecondsSinceEpoch;
    final entries = Map<String, dynamic>.of(source.entries)..removeWhere((key, _) => patch.remove.contains(key));
    for (final MapEntry(:key, :value) in patch.set.entries) {
      if (value == null) {
        entries.remove(key);
      } else {
        _checkValue(key, value);
        entries[key] = value;
      }
    }
    entries[LandmarkMetadata.updatedAtKey] = now;
    entries.putIfAbsent(LandmarkMetadata.createdAtKey, () => now);
    return LandmarkMetadata(entries: entries, version: source.version + 1);
  }

  /// Применяет [patch] как есть: удаления, затем установки, без версии и
  /// отметок времени — для метаданных сегментов, многоугольников и для
  /// правок, которые записываются позже одним сохранением.
  LandmarkMetadata merge(LandmarkMetadata source, MetadataPatch patch) {
    final entries = Map<String, dynamic>.of(source.entries)..removeWhere((key, _) => patch.remove.contains(key));
    for (final MapEntry(:key, :value) in patch.set.entries) {
      if (value == null) {
        entries.remove(key);
      } else {
        _checkValue(key, value);
        entries[key] = value;
      }
    }
    return source.copyWith(entries: entries);
  }

  /// Новые метаданные версии 0 из [entries] с проверкой типов значений.
  LandmarkMetadata validateAndBuild(Map<String, Object> entries) {
    final metadata = LandmarkMetadata(entries: Map<String, dynamic>.of(entries));
    validateEntries(metadata);
    return metadata;
  }

  /// Проверяет, что все значения можно записать в файл: bool, int,
  /// double, String, Uint8List. Иначе — [SerializationException].
  void validateEntries(LandmarkMetadata metadata) {
    for (final MapEntry(:key, :value) in metadata.entries.entries) {
      _checkValue(key, value);
    }
  }

  static void _checkValue(String key, Object? value) {
    if (value is bool || value is int || value is double || value is String || value is Uint8List) return;
    throw SerializationException('Unsupported metadata value type ${value.runtimeType} for key "$key"');
  }
}
