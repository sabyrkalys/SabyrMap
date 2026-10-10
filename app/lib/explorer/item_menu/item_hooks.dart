import 'package:flutter/widgets.dart';

/// Что экран делает после действий меню элемента. Экран кладёт хуки над
/// собой; действия ищут их в своём [BuildContext].
class ItemHooks extends InheritedWidget {
  const ItemHooks({
    super.key,
    required super.child,
    this.onOpen,
    this.onRenamed,
    this.onDeleted,
    this.inDetails = false,
  });

  /// «Детали» / «Открыть»; null — детализация поверх текущего экрана.
  final Future<void> Function(String path)? onOpen;

  /// Файл переименован — новый путь.
  final void Function(String path)? onRenamed;
  final VoidCallback? onDeleted;

  /// Меню открыто из детализации (без «Детали» и «Открыть»).
  final bool inDetails;

  static ItemHooks? maybeOf(BuildContext context) => context.getInheritedWidgetOfExactType<ItemHooks>();

  @override
  bool updateShouldNotify(ItemHooks oldWidget) =>
      onOpen != oldWidget.onOpen ||
      onRenamed != oldWidget.onRenamed ||
      onDeleted != oldWidget.onDeleted ||
      inDetails != oldWidget.inDetails;
}
