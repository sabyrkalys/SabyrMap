import 'package:flutter/material.dart';

import '../on_screen/favorite_set_save_dialog.dart';
import 'compare_mode_controller.dart';

const Color _ink = Color(0xFF333333);
const Color _accent = Color(0xFF00A38E);

/// Панель режима сравнения: заголовок, имя слоя на карте, слайдер.
class CompareModeBottomPanel extends StatelessWidget {
  const CompareModeBottomPanel({super.key, required this.controller, required this.names, required this.onClose});

  final CompareModeController controller;

  /// Имена слоёв по id.
  final Map<String, String> names;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.white,
        child: Container(
          decoration: const BoxDecoration(border: Border(top: BorderSide(color: Color(0xFFE0E0E0)))),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: SafeArea(
            top: false,
            child: ListenableBuilder(
              listenable: controller,
              builder: (context, _) => Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.compare, size: 22, color: _ink),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text('Сравнить...', style: TextStyle(fontSize: 16, color: Color(0xFF212121))),
                      ),
                      IconButton(
                        key: const Key('compare_save'),
                        tooltip: 'Сохранить в избранное',
                        icon: const Icon(Icons.bookmark_add_outlined, size: 22, color: _ink),
                        onPressed: () => FavoriteSetSaveDialog.show(context),
                      ),
                      IconButton(
                        key: const Key('compare_close'),
                        icon: const Icon(Icons.close, size: 22, color: _ink),
                        onPressed: onClose,
                      ),
                    ],
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      names[controller.currentLayerId] ?? controller.currentLayerId,
                      key: const Key('compare_current'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: Color(0xFF212121)),
                    ),
                  ),
                  SliderTheme(
                    data: const SliderThemeData(
                      activeTrackColor: _accent,
                      inactiveTrackColor: Color(0xFFE0E0E0),
                      thumbColor: _accent,
                    ),
                    child: Slider(
                      key: const Key('compare_slider'),
                      value: controller.sliderValue,
                      divisions: controller.count - 1,
                      onChanged: (v) => controller.sliderValue = v,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
}
