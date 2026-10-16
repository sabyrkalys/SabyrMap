import 'package:flutter/material.dart';

/// Нижнее меню приложения для шторок над картой («Карты на экране»,
/// «Метки на экране»): шторка — модальный маршрут поверх всего, и меню
/// [HomeShell] оказалось бы под ней. Шторка ставит копию меню над собой
/// ([aboveSheet]); нажатие на вкладку закрывает шторку и открывает эту
/// вкладку, как обычно.
/// Кнопки карты справа (ортофото, «+», «−») для шторок: их ставит
/// [MapScreen], пока он на экране; null — карты нет.
abstract final class MapSideButtons {
  static WidgetBuilder? builder;
}

class HomeNavScope extends InheritedWidget {
  const HomeNavScope({super.key, required this.buildNav, required this.select, required super.child});

  /// Меню; [onSelected] — что делать по нажатию на вкладку [index].
  final Widget Function(ValueChanged<int> onSelected) buildNav;

  /// Открывает вкладку [index] меню (как нажатие в самом меню).
  final ValueChanged<int> select;

  static HomeNavScope? maybeOf(BuildContext context) => context.getInheritedWidgetOfExactType<HomeNavScope>();

  /// builder шторки: [panel] (от контекста шторки) с меню над ней;
  /// [openerContext] — откуда шторку открыли. Шторка вызывается с
  /// прозрачным фоном; [background] — её фон под панелью, если панель не
  /// рисует свой. Открыта не с карты (из «Всех меток», над диалогом) — без
  /// меню, как раньше.
  static WidgetBuilder aboveSheet(BuildContext openerContext, WidgetBuilder panel, {Color? background}) {
    final scope = maybeOf(openerContext);
    Widget body(BuildContext sheetContext) => background == null
        ? panel(sheetContext)
        : Material(
            color: background,
            shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
            clipBehavior: Clip.antiAlias,
            child: panel(sheetContext),
          );
    if (scope == null) return body;
    // Шторка во всю высоту (вызывать с isScrollControlled): над панелью —
    // своё поле, и любое касание карты там — тап или начало сдвига —
    // закрывает шторку (барьер шторки ловит только тап).
    return (sheetContext) {
      void close() => Navigator.of(sheetContext).maybePop();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(
                  child: Listener(
                    key: const Key('sheet_map_area'),
                    behavior: HitTestBehavior.opaque,
                    onPointerDown: (_) => close(),
                  ),
                ),
                // Меню слева, кнопки карты справа — как над шторкой набора точек.
                Align(
                  alignment: Alignment.bottomCenter,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(
                          child: MediaQuery.removePadding(
                            context: sheetContext,
                            removeBottom: true,
                            child: scope.buildNav((index) {
                              Navigator.of(sheetContext).pop();
                              scope.select(index);
                            }),
                          ),
                        ),
                        if (MapSideButtons.builder case final buttons?)
                          Padding(padding: const EdgeInsets.only(right: 16), child: buttons(sheetContext)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.85),
            child: body(sheetContext),
          ),
        ],
      );
    };
  }

  @override
  bool updateShouldNotify(HomeNavScope oldWidget) => false;
}
