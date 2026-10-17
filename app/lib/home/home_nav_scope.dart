import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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

/// Главный экран для шторок над картой: открыть немодальную шторку у
/// нижнего края ([showSheet]) с главным меню и кнопками карты над ней.
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

  /// Шторки сейчас открываются немодально над картой ([showSheet]).
  static bool sheetsOverMap(BuildContext context) {
    final scope = maybeOf(context) ?? current;
    return scope != null && scope.isMapOnTop();
  }

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

  @override
  bool updateShouldNotify(HomeNavScope oldWidget) => false;
}
