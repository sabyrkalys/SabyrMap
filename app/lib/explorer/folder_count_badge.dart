import 'dart:io';

import 'package:app/landmarks/models/landmark_type.dart';
import 'package:path/path.dart' as p;

/// Сколько в папке подпапок и файлов меток.
class FolderCounts {
  const FolderCounts({required this.folders, required this.files});

  final int folders;
  final int files;

  /// Подпись строки папки: «3 папки · 5 файл.».
  String get label => '${_folders(folders)} · $files файл.';

  static String _folders(int n) {
    final mod10 = n % 10;
    final mod100 = n % 100;
    final word = mod10 == 1 && mod100 != 11
        ? 'папка'
        : (mod10 >= 2 && mod10 <= 4 && (mod100 < 12 || mod100 > 14) ? 'папки' : 'папок');
    return '$n $word';
  }

  /// Считает без подпапок и симлинков; файлы — только метки. Нет доступа —
  /// нули.
  static Future<FolderCounts> of(String path) async {
    var folders = 0;
    var files = 0;
    try {
      await for (final e in Directory(path).list(followLinks: false)) {
        if (e is Directory) {
          folders++;
        } else if (e is File && LandmarkType.fromExtension(p.extension(e.path)) != null) {
          files++;
        }
      }
    } on FileSystemException {
      return const FolderCounts(folders: 0, files: 0);
    }
    return FolderCounts(folders: folders, files: files);
  }
}
