import 'export_adapter.dart';
import 'format_capability.dart';
import 'import_adapter.dart';

/// Формат файлов в реестре: имя, расширения, возможности, адаптеры.
class FormatDescriptor {
  FormatDescriptor({
    required this.id,
    required this.displayName,
    required List<String> extensions,
    required this.capabilities,
    this.importAdapter,
    this.exportAdapter,
  }) : extensions = List.unmodifiable(extensions.map(normalizeExtension));

  final String id;
  final String displayName;

  /// Без точки, в нижнем регистре; первое — основное.
  final List<String> extensions;
  final Set<FormatCapability> capabilities;
  final ImportAdapter? importAdapter;
  final ExportAdapter? exportAdapter;

  bool get canImport => importAdapter != null;
  bool get canExport => exportAdapter != null;

  /// null (тип без своей возможности) не поддерживается ни одним форматом.
  bool supports(FormatCapability? cap) => cap != null && capabilities.contains(cap);

  /// `.GPX` → `gpx`.
  static String normalizeExtension(String ext) => (ext.startsWith('.') ? ext.substring(1) : ext).toLowerCase();

  @override
  String toString() => 'FormatDescriptor($id)';
}
