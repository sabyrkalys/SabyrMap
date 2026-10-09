import 'icon_info.dart';
import 'icon_resolver.dart';

/// Иконки в памяти, собранные [IconResolver.scan]. Пусто до [refresh].
class IconRegistry {
  IconRegistry(this._resolver);

  final IconResolver _resolver;
  List<IconInfo> _icons = const [];
  Map<String, IconInfo> _byId = const {};

  /// Пересканировать папку иконок.
  Future<void> refresh() async {
    final icons = await _resolver.scan();
    _icons = List.unmodifiable(icons);
    _byId = {for (final icon in icons) icon.id: icon};
  }

  /// Все иконки, по категории и имени.
  List<IconInfo> get all => _icons;

  /// Подпапки первого уровня, по алфавиту.
  List<String> get categories => List.unmodifiable({for (final i in _icons) ?i.category}.toList()..sort());

  /// Иконки категории [category].
  List<IconInfo> byCategory(String category) => [for (final i in _icons) if (i.category == category) i];

  IconInfo? byId(String id) => _byId[id];
}
