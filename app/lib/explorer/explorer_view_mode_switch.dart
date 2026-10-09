import 'package:app/landmarks/explorer/explorer_view_mode.dart';

/// Подпись пункта меню, переключающего вид списка.
abstract final class ExplorerViewModeSwitch {
  static String labelFor(ExplorerViewMode current) =>
      current == ExplorerViewMode.list ? 'Подробный список' : 'Компактный список';

  static ExplorerViewMode next(ExplorerViewMode current) =>
      current == ExplorerViewMode.list ? ExplorerViewMode.preview : ExplorerViewMode.list;
}
