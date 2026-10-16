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
  });

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

  /// Рисуется новый набор точек или маршрут — шторка на экране.
  static bool isActive(EditModeController editMode) {
    final target = editMode.state.target;
    return target != null && target.isNew && (target.type == LandmarkType.set || target.type == LandmarkType.route);
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
                // и нужно.
                child: Row(
                  children: [
                    Expanded(
                      child: FilledButton.tonalIcon(
                        key: const Key('set_panel_add'),
                        onPressed: onAddPoint,
                        icon: const Icon(Icons.add),
                        label: const Text('Путевая точка'),
                      ),
                    ),
                    if (onDelete != null && pointCount > 0) ...[
                      const SizedBox(width: 8),
                      Expanded(
                        child: FilledButton.tonalIcon(
                          key: const Key('set_panel_delete'),
                          onPressed: onDelete,
                          icon: const Icon(Icons.delete_outline),
                          label: const Text('Удалить'),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
