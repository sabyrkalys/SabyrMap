import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Нижнее меню приложения для шторок над картой («Карты на экране»,
/// «Метки на экране»): шторка — модальный маршрут поверх всего, и меню
/// [HomeShell] оказалось бы под ней. Шторка ставит копию меню над собой
/// ([aboveSheet]); нажатие на вкладку закрывает шторку и открывает эту
/// вкладку, как обычно.
/// Касание карты, которое закрыло меню или карточку: оно доходит до карты
/// (та сразу двигается), но ничего на ней не открывает — ни карточку
/// прицела, ни метку под пальцем.
abstract final class MapTouchGuard {
  static int? _pointer;
  static DateTime _at = DateTime.fromMillisecondsSinceEpoch(0);

  /// Касание [pointer] закрыло меню.
  static void consume(int pointer) {
    _pointer = pointer;
    _at = DateTime.now();
  }

  /// Касание [pointer] — то самое.
  static bool isConsumed(int pointer) => pointer == _pointer;

  /// Тап по карте сразу после закрытия меню — от того же касания.
  static bool get justConsumed => DateTime.now().difference(_at) < const Duration(milliseconds: 600);
}

/// Кнопки карты справа (ортофото, «+», «−») для шторок: их ставит
/// [MapScreen], пока он на экране; null — карты нет.
abstract final class MapSideButtons {
  static WidgetBuilder? builder;
}

/// Открыта ли немодальная шторка над картой ([HomeNavScope.showSheet]):
/// пока открыта, нижнее меню и кнопки карты — над ней, а не внизу.
class MapSheetOpen extends Notifier<bool> {
  @override
  bool build() => false;

  void set(bool open) => state = open;
}

final mapSheetOpenProvider = NotifierProvider<MapSheetOpen, bool>(MapSheetOpen.new);

class HomeNavScope extends InheritedWidget {
  const HomeNavScope({
    super.key,
    required this.buildNav,
    required this.select,
    required this.openSheet,
    required this.isMapOnTop,
    required super.child,
  });

  /// Открывает немодальную шторку у нижнего края (во всю ширину, над ней —
  /// меню и кнопки карты); карта под ней живая. Завершается, когда шторку
  /// закрыли.
  final Future<void> Function(WidgetBuilder builder) openSheet;

  /// Карта сейчас на экране (поверх неё нет другого экрана).
  final bool Function() isMapOnTop;

  /// Текущее меню [HomeShell] — для шторок, открытых не изнутри него
  /// (например, от контекста навигатора).
  static HomeNavScope? current;

  /// Шторка над картой: немодальная, если карта на экране ([openSheet]):
  /// касание карты закрывает её и тут же двигает карту. Иначе (из «Всех
  /// меток», в тестах без [HomeShell]) — обычная модальная шторка [panel].
  static Future<void> showSheet(BuildContext context, WidgetBuilder panel, {Color? background}) {
    final scope = maybeOf(context) ?? current;
    if (scope != null && scope.isMapOnTop()) {
      return scope.openSheet((sheetContext) => _body(sheetContext, panel, background));
    }
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black12,
      builder: (sheetContext) => _body(sheetContext, panel, background),
    );
  }

  static Widget _body(BuildContext sheetContext, WidgetBuilder panel, Color? background) => background == null
      ? panel(sheetContext)
      : Material(
          color: background,
          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
          clipBehavior: Clip.antiAlias,
          child: panel(sheetContext),
        );

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
      // Сразу, без анимации ухода: пока шторка уезжала (~0,3 с), карта под
      // ней не принимала касаний и «замирала».
      void close() {
        final route = ModalRoute.of(sheetContext);
        if (route != null && route.isActive) Navigator.of(sheetContext).removeRoute(route);
      }

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
                              close();
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
