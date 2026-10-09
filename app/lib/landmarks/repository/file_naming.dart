import 'dart:io';

import 'package:app/landmarks/models/landmark_type.dart';
import 'package:path/path.dart' as p;

/// Имена файлов меток: читаемые, из имени объекта и времени создания.
/// Без хешей и UUID.
abstract final class FileNaming {
  /// Максимальная длина основы имени, в символах.
  static const int maxBaseLength = 64;

  /// Основа, если имя пустое или после очистки ничего не осталось.
  static const String untitled = 'untitled';

  static final RegExp _forbidden = RegExp(r'[\\/:*?"<>|]');
  static final RegExp _control = RegExp(r'[\x00-\x1F\x7F]');
  static final RegExp _whitespace = RegExp(r'\s+');

  /// Безопасная основа имени файла из имени объекта: нижний регистр,
  /// пробелы → `_`, без `\ / : * ? " < > |`, не длиннее 64 символов.
  ///
  /// Decision: подряд идущие пробелы дают один `_`, пробелы по краям
  /// отбрасываются; управляющие символы и ведущие точки (скрытые файлы)
  /// удаляются; обрезка идёт по символам Unicode, а не по байтам.
  static String baseFromName(String name) {
    var base = name
        .replaceAll(_forbidden, '')
        .replaceAll(_control, '')
        .trim()
        .replaceAll(_whitespace, '_')
        .toLowerCase()
        .replaceFirst(RegExp(r'^\.+'), '');
    final runes = base.runes.toList();
    if (runes.length > maxBaseLength) base = String.fromCharCodes(runes.take(maxBaseLength));
    return base.isEmpty ? untitled : base;
  }

  /// Полное имя файла: `<base>_<timestamp_ms>.<ext>`.
  static String filename(String name, LandmarkType type, {DateTime? at}) {
    final ms = (at ?? DateTime.now()).millisecondsSinceEpoch;
    return '${baseFromName(name)}_$ms.${type.extension}';
  }

  /// Свободный абсолютный путь для [filename] в [dir]: если имя занято,
  /// перед расширением добавляется `_1`, `_2`, ...
  ///
  /// Кандидат подбирается синхронной проверкой, затем перепроверяется
  /// асинхронно; если за это время файл появился, подбор повторяется.
  /// Decision: файл не резервируется, поэтому между возвратом пути и
  /// записью гонка остаётся возможной; при именах с временем в мс она
  /// практически исключена.
  static Future<String> resolveCollision(String dir, String filename) async {
    final ext = p.extension(filename);
    final stem = p.basenameWithoutExtension(filename);
    var index = 0;
    while (true) {
      String candidate;
      do {
        candidate = p.join(dir, index == 0 ? filename : '${stem}_$index$ext');
        index++;
      } while (FileSystemEntity.typeSync(candidate) != FileSystemEntityType.notFound);
      if (await FileSystemEntity.type(candidate) == FileSystemEntityType.notFound) return candidate;
    }
  }
}
