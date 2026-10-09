import 'package:app/exceptions/storage_exception.dart';
import 'package:app/landmarks/composite/statistics/composite_calculator.dart';
import 'package:app/landmarks/composite/validation/composite_validator.dart';
import 'package:app/landmarks/drafts/metadata_patch.dart';
import 'package:app/landmarks/models/landmark_file.dart';
import 'package:app/landmarks/repository/landmark_repository.dart';
import 'package:app/landmarks/services/metadata_editor.dart';
import 'package:app/landmarks/validation/validation_result.dart';

/// Общее для сервисов набора, маршрута, трека и области: чтение файла
/// своего типа и запись правки.
///
/// Каждая запись: проверка объекта ([CompositeValidator.validateObject]),
/// пользовательские метаданные version + 1 и `updated_at`, ключи
/// статистики пересчитываются, файл переписывается через
/// [LandmarkRepository.update]. Методы возвращают объект, как он записан.
abstract class CompositeService<T extends LandmarkObject> {
  CompositeService(this.repository, {this.editor = const MetadataEditor(), this.calculator = const CompositeCalculator()});

  final LandmarkRepository repository;
  final MetadataEditor editor;
  final CompositeCalculator calculator;

  /// Тип файлов этого сервиса.
  LandmarkType get type;

  /// Читает объект. Файл другого типа — [StorageException].
  Future<T> load(String path) async {
    final file = await repository.load(path);
    final content = file.content;
    if (content is! T) {
      throw StorageException('Expected a ${type.extension} file, got ${file.type.extension}', path: path);
    }
    return content;
  }

  /// Правит пользовательские метаданные объекта.
  Future<T> updateMetadata(String path, MetadataPatch patch) async => save(path, await load(path), patch: patch);

  /// Удаляет файл; отсутствующий — не ошибка.
  Future<void> delete(String path) => repository.delete(path);

  /// Записывает [object] в [path] с правкой [patch] пользовательских
  /// метаданных. Неверный объект — [ValidationException], файл не меняется.
  Future<T> save(String path, T object, {MetadataPatch patch = const MetadataPatch()}) async {
    final result = CompositeValidator.validateObject(object);
    if (!result.isValid) throw ValidationException(result.errors);
    final stats = calculator.metadataFor(object);
    final merged = MetadataPatch(
      set: {...patch.set, ...stats.set},
      remove: {...patch.remove, ...stats.remove}.difference(stats.set.keys.toSet()),
    );
    final metadata = editor.apply(object.userMetadata, merged);
    await repository.update(path, LandmarkFile.of(object.withUserMetadata(metadata)));
    return load(path);
  }

  /// Читает, меняет через [change] и записывает.
  Future<T> mutate(String path, T Function(T object) change) async => save(path, change(await load(path)));
}
