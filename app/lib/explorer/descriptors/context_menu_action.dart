import 'package:flutter/widgets.dart';

/// Пункт контекстного меню.
///
/// [labelResolver], [isEnabled] и [isSelected] получают окружение меню
/// (`MenuEnv`): сервисы и, для меню элемента, прочитанный объект.
class ContextMenuAction {
  const ContextMenuAction({
    required this.id,
    required this.label,
    required this.icon,
    required this.iconColor,
    required this.onTap,
    this.labelResolver,
    this.isEnabled,
    this.isSelected,
  });

  final String id;
  final String label;
  final IconData icon;

  /// Цвет иконки, ARGB.
  final int iconColor;

  /// Действие; [BuildContext] — экран, с которого открыто меню (шторка к
  /// этому моменту уже закрыта, кроме пунктов сортировки).
  final Future<void> Function(BuildContext context) onTap;

  /// Подпись, зависящая от состояния («Показать» / «Скрыть»).
  final String Function(Object context)? labelResolver;
  final bool Function(Object context)? isEnabled;

  /// Для пунктов-переключателей: выбран ли пункт.
  final bool Function(Object context)? isSelected;

  String labelFor(Object context) => labelResolver?.call(context) ?? label;
  bool enabledFor(Object context) => isEnabled?.call(context) ?? true;
}
