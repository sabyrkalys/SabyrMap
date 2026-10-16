import 'package:app/landmarks/composite/edit_mode/edit_mode_controller.dart';
import 'package:app/landmarks/models/landmark_type.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../screens/layers_panel.dart' show onScreenPanelBackground;

/// Высота шторки на экране, dp (0 — шторки нет): над ней встаёт нижнее
/// меню приложения ([HomeShell]).
class SetPanelHeight extends Notifier<double> {
  @override
  double build() => 0;

  void set(double height) {
    if (state != height) state = height;
  }
}

final setPanelHeightProvider = NotifierProvider<SetPanelHeight, double>(SetPanelHeight.new);

/// Сообщает [onSize] размер ребёнка после каждой раскладки.
class MeasureSize extends SingleChildRenderObjectWidget {
  const MeasureSize({super.key, required this.onSize, super.child});

  final ValueChanged<Size> onSize;

  @override
  RenderObject createRenderObject(BuildContext context) => MeasureSizeBox(onSize);

  @override
  void updateRenderObject(BuildContext context, MeasureSizeBox renderObject) => renderObject.onSize = onSize;
}

class MeasureSizeBox extends RenderProxyBox {
  MeasureSizeBox(this.onSize);

  ValueChanged<Size> onSize;
  Size? _last;

  @override
  void performLayout() {
    super.performLayout();
    if (size == _last) return;
    _last = size;
    final reported = size;
    WidgetsBinding.instance.addPostFrameCallback((_) => onSize(reported));
  }
}

/// «Управление метками»: шторка нового набора точек или маршрута у нижнего
/// края экрана, в оформлении шторок приложения («Метки на экране»). Шапка —
/// значок, название, поиск по точкам и галочка «Готово»; под ней число
/// точек и «+ Путевая точка», которая ставит точку в прицел.
///
/// Decision: пока шторка открыта, нижнее меню и кнопки карты стоят над ней
/// ([setPanelHeightProvider]), сама шторка — у самого края экрана.
class SetPanel extends StatelessWidget {
  const SetPanel({
    super.key,
    required this.pointCount,
    required this.onAddPoint,
    required this.onSearch,
    required this.onFinish,
    this.lengthMeters,
    this.onDelete,
    this.drawing,
    this.onDrawingChanged,
  });

  /// Путь: «Начертить» включён — путь сам рисуется за прицелом; null — не
  /// путь (набор, маршрут), кнопки нет.
  final bool? drawing;
  final ValueChanged<bool>? onDrawingChanged;

  final int pointCount;
  final VoidCallback onAddPoint;

  /// Длина маршрута — рядом с числом точек; null — у набора её нет.
  final double? lengthMeters;

  /// «Удалить»: убирает последнюю точку; кнопка видна, пока точки есть.
  final VoidCallback? onDelete;

  /// Поиск по точкам набора; без точек — недоступен.
  final VoidCallback onSearch;

  /// Галочка: сохранить набор (без точек — закрыть).
  final VoidCallback onFinish;

  static const Color _ink = Color(0xFF333333);

  /// Рисуется новый набор точек, маршрут или путь — шторка на экране.
  static bool isActive(EditModeController editMode) {
    final target = editMode.state.target;
    return target != null &&
        target.isNew &&
        (target.type == LandmarkType.set || target.type == LandmarkType.route || target.type == LandmarkType.track);
  }

  /// «0 точ.», «12 точ.»; с длиной маршрута — «4 точ.   775 м».
  static String countLabel(int n, [double? meters]) =>
      meters == null || n < 2 ? '$n точ.' : '$n точ.   ${formatLength(meters)}';

  /// «775 м», «2,35 км».
  static String formatLength(double meters) =>
      meters < 1000 ? '${meters.round()} м' : '${(meters / 1000).toStringAsFixed(2).replaceAll('.', ',')} км';

  /// Высота системных кнопок внизу, dp — у самого окна: в карте нижний
  /// отступ MediaQuery занят нижним меню. Кнопки обычно спрятаны
  /// ([configureSystemUi]) — тогда отступа нет.
  static double bottomInset(BuildContext context) {
    final view = View.of(context);
    return view.padding.bottom / view.devicePixelRatio;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('set_panel'),
      decoration: const BoxDecoration(
        color: onScreenPanelBackground,
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        boxShadow: [BoxShadow(color: Color(0x26000000), blurRadius: 12)],
      ),
      child: Padding(
        // Отступ от системных кнопок Android берётся у окна: Scaffold со
        // спрятанным нижним меню убирает его из MediaQuery.
        padding: EdgeInsets.only(bottom: bottomInset(context)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(Icons.flag_sharp, size: 24, color: _ink),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Управление метками',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500, color: Color(0xFF212121)),
                    ),
                  ),
                  IconButton(
                    key: const Key('set_panel_search'),
                    tooltip: 'Поиск по точкам',
                    onPressed: pointCount == 0 ? null : onSearch,
                    icon: const Icon(Icons.search, size: 22),
                    color: _ink,
                  ),
                  IconButton(
                    key: const Key('set_panel_done'),
                    tooltip: 'Готово',
                    onPressed: onFinish,
                    icon: const Icon(Icons.check, size: 22),
                    color: _ink,
                  ),
                ],
              ),
              if (drawing != null)
                ..._pathBody()
              else ...[
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    countLabel(pointCount, lengthMeters),
                    key: const Key('set_panel_count'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 15, color: Color(0xFF616161)),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  // FilledButton в теме растянут во всю ширину — в Expanded так
                  // и нужно; подпись в половине ширины не переносится, а
                  // уменьшается.
                  child: Row(
                    children: [
                      Expanded(
                        child: FilledButton.tonalIcon(
                          key: const Key('set_panel_add'),
                          onPressed: onAddPoint,
                          icon: const Icon(Icons.add),
                          label: const FittedBox(fit: BoxFit.scaleDown, child: Text('Путевая точка', maxLines: 1)),
                        ),
                      ),
                      if (onDelete != null && pointCount > 0) ...[
                        const SizedBox(width: 8),
                        Expanded(
                          child: FilledButton.tonalIcon(
                            key: const Key('set_panel_delete'),
                            onPressed: onDelete,
                            icon: const Icon(Icons.delete_outline),
                            label: const FittedBox(fit: BoxFit.scaleDown, child: Text('Удалить', maxLines: 1)),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// Кнопка ряда пути: значок над подписью в две строки, как в образце.
  static Widget _pathButton(Key key, IconData icon, String label, VoidCallback? onPressed) => Expanded(
    child: FilledButton.tonal(
      key: key,
      onPressed: onPressed,
      style: ButtonStyle(
        minimumSize: WidgetStateProperty.all(const Size(0, 52)),
        padding: WidgetStateProperty.all(const EdgeInsets.symmetric(horizontal: 6, vertical: 4)),
        shape: WidgetStateProperty.all(RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 22),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              maxLines: 2,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, height: 1.15, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    ),
  );

  /// Путь: «Начертить», «Путевая точка», «Удалить», под ними статистика.
  List<Widget> _pathBody() => [
    const SizedBox(height: 4),
    Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Row(
        children: [
          _pathButton(
            const Key('set_panel_draw'),
            drawing! ? Icons.check_box : Icons.check_box_outline_blank,
            'Начертить',
            () => onDrawingChanged?.call(!drawing!),
          ),
          const SizedBox(width: 6),
          _pathButton(const Key('set_panel_add'), Icons.add, 'Путевая точка', onAddPoint),
          const SizedBox(width: 6),
          _pathButton(const Key('set_panel_delete'), Icons.delete, 'Удалить', pointCount > 0 ? onDelete : null),
        ],
      ),
    ),
    const SizedBox(height: 12),
    const Text(
      'СТАТИСТИКА',
      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF616161), letterSpacing: 0.5),
    ),
    const SizedBox(height: 6),
    _statRow('Длина', formatLength(lengthMeters ?? 0), const Key('set_panel_length')),
    // Высот у точек пути нет (не с чего взять) — подъём и спуск не считаются.
    _statRow('Подъём/Спуск', 'нет данных о высотах', const Key('set_panel_climb')),
  ];

  static Widget _statRow(String label, String value, Key key) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      children: [
        SizedBox(
          width: 120,
          child: Text(
            label,
            textAlign: TextAlign.right,
            style: const TextStyle(fontSize: 14, fontStyle: FontStyle.italic, color: Color(0xFF616161)),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            value,
            key: key,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Color(0xFF212121)),
          ),
        ),
      ],
    ),
  );
}
