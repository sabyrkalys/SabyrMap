import 'package:app/landmarks/models/landmark_metadata.dart';
import 'package:app/landmarks/services/metadata_editor.dart';

/// Правка [LandmarkMetadata]: какие ключи поставить и какие удалить.
class MetadataPatch {
  const MetadataPatch({this.set = const {}, this.remove = const {}});

  /// Ключи и новые значения. Decision: значение null равнозначно удалению
  /// ключа.
  final Map<String, Object?> set;

  /// Ключи для удаления.
  final Set<String> remove;

  bool get isEmpty => set.isEmpty && remove.isEmpty;

  /// Применяет правку к [source]: сначала [remove], затем [set];
  /// version + 1, `updated_at` = [now] (по умолчанию — сейчас), `created_at`
  /// ставится, если его не было. См. [MetadataEditor.apply].
  LandmarkMetadata apply(LandmarkMetadata source, {DateTime? now}) =>
      MetadataEditor(clock: now == null ? null : () => now).apply(source, this);
}
