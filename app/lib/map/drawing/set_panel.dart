import 'package:flutter/material.dart';

/// «Управление метками»: нижняя панель нового набора точек:
/// серая полоса — флажок, название, поиск по точкам и
/// галочка «Готово»; под ней число точек и «+ ПУТЕВАЯ ТОЧКА», которая
/// ставит точку в прицел.
class SetPanel extends StatelessWidget {
  const SetPanel({
    super.key,
    required this.pointCount,
    required this.onAddPoint,
    required this.onSearch,
    required this.onFinish,
  });

  final int pointCount;
  final VoidCallback onAddPoint;

  /// Поиск по точкам набора; без точек — недоступен.
  final VoidCallback onSearch;

  /// Галочка: сохранить набор (без точек — закрыть).
  final VoidCallback onFinish;

  static const Color _bar = Color(0xFFD5D7D9);
  static const Color _button = Color(0xFFDCDEE0);
  static const Color _text = Color(0xFF212121);
  static const Color _icon = Color(0xFF424242);

  /// «0 точ.», «12 точ.».
  static String countLabel(int n) => '$n точ.';

  @override
  Widget build(BuildContext context) {
    return Material(
      key: const Key('set_panel'),
      color: Colors.white,
      elevation: 6,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Material(
            color: _bar,
            elevation: 2,
            child: SizedBox(
              height: 56,
              child: Row(
                children: [
                  const SizedBox(width: 16),
                  const Icon(Icons.flag_sharp, size: 28, color: _text),
                  const SizedBox(width: 16),
                  const Expanded(
                    child: Text(
                      'Управление метками',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 22, fontStyle: FontStyle.italic, color: _text),
                    ),
                  ),
                  IconButton(
                    key: const Key('set_panel_search'),
                    tooltip: 'Поиск по точкам',
                    onPressed: pointCount == 0 ? null : onSearch,
                    icon: const Icon(Icons.search_sharp, size: 28, color: _icon),
                  ),
                  const SizedBox(height: 28, child: VerticalDivider(width: 8, color: Color(0xFF9E9E9E))),
                  IconButton(
                    key: const Key('set_panel_done'),
                    tooltip: 'Готово',
                    onPressed: onFinish,
                    icon: const Icon(Icons.check_sharp, size: 28, color: _icon),
                  ),
                  const SizedBox(width: 4),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Text(
              countLabel(pointCount),
              key: const Key('set_panel_count'),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 18, color: _text),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
            child: Material(
              color: _button,
              elevation: 2,
              borderRadius: BorderRadius.circular(4),
              child: InkWell(
                key: const Key('set_panel_add'),
                onTap: onAddPoint,
                borderRadius: BorderRadius.circular(4),
                child: const SizedBox(
                  height: 56,
                  child: Row(
                    children: [
                      SizedBox(width: 16),
                      Icon(Icons.add_sharp, size: 30, color: _text),
                      Expanded(
                        child: Text(
                          'ПУТЕВАЯ ТОЧКА',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 18, letterSpacing: 0.5, color: _text),
                        ),
                      ),
                      SizedBox(width: 46),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
