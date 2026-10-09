import 'clipboard_entry.dart';

/// Буфер «Копировать / Вырезать / Вставить» проводника. Хранит пути, а не
/// содержимое файлов.
class LandmarksClipboard {
  List<ClipboardEntry> _entries = const [];
  bool _isCut = false;

  List<ClipboardEntry> get entries => _entries;
  bool get isEmpty => _entries.isEmpty;

  /// Записи вырезаны: после вставки исходные файлы исчезнут.
  bool get isCut => _isCut;

  void copy(List<ClipboardEntry> entries) => _fill(entries, cut: false);

  void cut(List<ClipboardEntry> entries) => _fill(entries, cut: true);

  void empty() => _fill(const [], cut: false);

  /// Удаляет одну запись после вставки.
  void removeOne(String sourcePath) {
    _entries = List.unmodifiable(_entries.where((e) => e.sourcePath != sourcePath));
    if (_entries.isEmpty) _isCut = false;
  }

  void _fill(List<ClipboardEntry> entries, {required bool cut}) {
    _entries = List.unmodifiable(entries);
    _isCut = cut && entries.isNotEmpty;
  }
}
