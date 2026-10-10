import 'package:app/landmarks/drafts/metadata_patch.dart';
import 'package:app/landmarks/explorer/explorer_node.dart';
import 'package:app/landmarks/explorer/listing/landmark_item.dart';
import 'package:app/landmarks/explorer/listing/sort_options.dart';
import 'package:app/landmarks/models/landmark_file.dart';
import 'package:app/landmarks/services/landmark_services.dart';

import '../descriptors/landmark_type_descriptor.dart';

/// Операции над секцией списка (все элементы одного типа в открытой
/// папке) и её настройки: режим показа и сортировка.
abstract final class SectionActions {
  static String viewModeKey(LandmarkType type) => 'explorer.view_mode.${type.extension}';
  static String sortKey(LandmarkType type) => 'explorer.sort.${type.extension}';

  /// Элементы секции [type] в открытой папке, в порядке списка.
  static List<LandmarkItem> itemsOf(LandmarkServices s, LandmarkType type) => [
    for (final n in s.explorerController.state.nodes.whereType<ExplorerItemNode>())
      if (n.item.type == type) n.item,
  ];

  static Set<String> pathsOf(LandmarkServices s, LandmarkType type) => {
    for (final item in itemsOf(s, type)) item.path,
  };

  /// Режим показа секции; не задан — по умолчанию дескриптора.
  static SectionViewMode viewModeOf(LandmarkServices s, LandmarkTypeDescriptor d) {
    final saved = s.settings.getString(viewModeKey(d.type));
    return SectionViewMode.values.where((m) => m.name == saved).firstOrNull ?? d.defaultViewMode;
  }

  static Future<void> setViewMode(LandmarkServices s, LandmarkType type, SectionViewMode mode) =>
      s.settings.setString(viewModeKey(type), mode.name);

  /// Сортировка секции; null — общая сортировка списка.
  static SortOptions? sortOf(LandmarkServices s, LandmarkType type) => SortOptions.decode(s.settings.getString(sortKey(type)));

  static Future<void> setSort(LandmarkServices s, LandmarkType type, SortOptions sort) =>
      s.settings.setString(sortKey(type), sort.encode());

  /// Сортировка, которая сейчас действует для секции.
  static SortOptions effectiveSort(LandmarkServices s, LandmarkType type) =>
      sortOf(s, type) ?? s.explorerController.state.sort;

  static String showAll(LandmarkServices s, LandmarkType type) {
    final paths = pathsOf(s, type);
    s.displayRegistry.displayAll(paths);
    return 'Показано на карте: ${paths.length}';
  }

  static String hideAll(LandmarkServices s, LandmarkType type) {
    final paths = pathsOf(s, type);
    s.displayRegistry.undisplayAll(paths);
    return 'Убрано с карты: ${paths.length}';
  }

  static Future<String> copyAll(LandmarkServices s, LandmarkType type) async {
    final result = await s.explorerOperations.copySelected(pathsOf(s, type));
    return 'Скопировано: ${result.affectedCount}';
  }

  static Future<String> cutAll(LandmarkServices s, LandmarkType type) async {
    final result = await s.explorerOperations.cutSelected(pathsOf(s, type));
    return 'Вырезано: ${result.affectedCount}';
  }

  /// Один цвет всем элементам секции.
  static Future<String> setColorAll(LandmarkServices s, LandmarkType type, int color) async {
    final result = await s.explorerOperations.editDetailsSelected(
      pathsOf(s, type),
      MetadataPatch(set: {LandmarkMetadata.colorKey: color}),
    );
    return result.success ? 'Цвет изменён: ${result.affectedCount}' : (result.errorMessage ?? 'Не всё изменено');
  }

  static Future<String> deleteAll(LandmarkServices s, LandmarkType type) async {
    final result = await s.explorerOperations.deleteSelected(pathsOf(s, type));
    return result.success ? 'Удалено: ${result.affectedCount}' : (result.errorMessage ?? 'Не всё удалено');
  }

  static void selectAll(LandmarkServices s, LandmarkType type) {
    s.explorerController.selection
      ..activate()
      ..selectAll(pathsOf(s, type));
  }

  static void clearSelection(LandmarkServices s) => s.explorerController.selection.clear();
}
