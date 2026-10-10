import 'context_menu_action.dart';

/// Группа пунктов меню под общим заголовком.
class ContextMenuSection {
  const ContextMenuSection({this.title, required this.actions, this.isRadio = false, this.keepsOpen = false});

  /// «Буфер обмена», «Изменить»...; null — без заголовка.
  final String? title;
  final List<ContextMenuAction> actions;

  /// Пункты — переключатели с одним выбором.
  final bool isRadio;

  /// Нажатие не закрывает шторку (сортировка).
  final bool keepsOpen;
}
