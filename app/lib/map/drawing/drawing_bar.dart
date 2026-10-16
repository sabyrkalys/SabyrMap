import 'package:app/landmarks/models/landmark_type.dart';
import 'package:flutter/material.dart';

/// Панель рисования нового маршрута или области поверх карты: точки
/// ставятся в прицел кнопкой «Точка» (или нажатием на прицел), шаги
/// отменяются и возвращаются, «Готово» сохраняет, крестик закрывает.
///
/// Decision: «Готово» — в строке заголовка, крестик — в ряду кнопок:
/// на узком телефоне все кнопки в одну строку не помещаются.
class DrawingBar extends StatelessWidget {
  const DrawingBar({
    super.key,
    required this.type,
    required this.pointCount,
    required this.canUndo,
    required this.canRedo,
    required this.canFinish,
    required this.onAddPoint,
    required this.onUndo,
    required this.onRedo,
    required this.onFinish,
    required this.onCancel,
  });

  final LandmarkType type;
  final int pointCount;
  final bool canUndo;
  final bool canRedo;
  final bool canFinish;
  final VoidCallback onAddPoint;
  final VoidCallback onUndo;
  final VoidCallback onRedo;
  final VoidCallback onFinish;
  final VoidCallback onCancel;

  /// «Новый маршрут», «Новая область»...
  static String titleOf(LandmarkType type) => switch (type) {
    LandmarkType.route => 'Новый маршрут',
    LandmarkType.area => 'Новая область',
    LandmarkType.track => 'Новый путь',
    LandmarkType.set => 'Новый набор точек',
    _ => 'Новая метка',
  };

  /// Подсказка, пока точек не хватает для сохранения.
  static String? hintOf(LandmarkType type, int pointCount) => switch (type) {
    LandmarkType.area when pointCount < 3 => 'Наведите прицел и добавьте не меньше 3 точек',
    LandmarkType.route || LandmarkType.track when pointCount < 2 => 'Наведите прицел и добавьте не меньше 2 точек',
    _ when pointCount == 0 => 'Наведите прицел и добавьте точку',
    _ => null,
  };

  /// Тема приложения растягивает кнопки во всю ширину (minimumSize с
  /// бесконечной шириной) — в ряду панели это ломает раскладку.
  static final ButtonStyle _compact = ButtonStyle(
    minimumSize: WidgetStateProperty.all(const Size(48, 40)),
    padding: WidgetStateProperty.all(const EdgeInsets.symmetric(horizontal: 12)),
    textStyle: WidgetStateProperty.all(const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
  );

  @override
  Widget build(BuildContext context) {
    final hint = hintOf(type, pointCount);
    return Material(
      key: const Key('drawing_bar'),
      color: Colors.white,
      elevation: 4,
      shadowColor: Colors.black54,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 4, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(titleOf(type), style: Theme.of(context).textTheme.titleMedium),
                      Text(
                        hint ?? 'Точек: $pointCount',
                        key: const Key('drawing_status'),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: FilledButton(
                    key: const Key('drawing_finish'),
                    style: _compact,
                    onPressed: canFinish ? onFinish : null,
                    child: const Text('Готово'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                FilledButton.tonalIcon(
                  key: const Key('drawing_add_point'),
                  style: _compact,
                  onPressed: onAddPoint,
                  icon: const Icon(Icons.add_location_alt_outlined),
                  label: const Text('Точка'),
                ),
                const SizedBox(width: 4),
                IconButton(
                  key: const Key('drawing_undo'),
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Отменить',
                  onPressed: canUndo ? onUndo : null,
                  icon: const Icon(Icons.undo),
                ),
                IconButton(
                  key: const Key('drawing_redo'),
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Вернуть',
                  onPressed: canRedo ? onRedo : null,
                  icon: const Icon(Icons.redo),
                ),
                const Spacer(),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  key: const Key('drawing_cancel'),
                  tooltip: 'Закрыть без сохранения',
                  onPressed: onCancel,
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
