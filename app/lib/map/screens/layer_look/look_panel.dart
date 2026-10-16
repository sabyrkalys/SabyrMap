import 'package:flutter/material.dart';
import '../../../home/home_nav_scope.dart';

const Color _ink = Color(0xFF333333);
const Color _accent = Color(0xFF00A38E);
const Color _secondary = Color(0xFF757575);

/// Открывает экран вида слоя (цвет, удаление цвета) внизу поверх карты:
/// карта над ним видна и меняется сразу.
Future<void> showLookPanel(BuildContext context, Widget panel) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.transparent,
      builder: HomeNavScope.aboveSheet(context, (_) => panel),
    );

/// Серая плашка экрана: иконка, «Название · слой», ?, 🔧, разделитель, ✓.
class LookAppBar extends StatelessWidget {
  const LookAppBar({
    super.key,
    required this.icon,
    required this.title,
    required this.onHelp,
    required this.onTools,
    required this.onDone,
  });

  final IconData icon;
  final String title;
  final VoidCallback onHelp;
  final VoidCallback onTools;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: const BoxDecoration(
          color: Color(0xF0E0E0E0),
          border: Border.symmetric(horizontal: BorderSide(color: Color(0xFFBDBDBD))),
        ),
        child: Row(
          children: [
            Icon(icon, size: 22, color: _ink),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                key: const Key('look_title'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 15, fontStyle: FontStyle.italic, color: Color(0xFF212121)),
              ),
            ),
            IconButton(
              key: const Key('look_help'),
              icon: const Icon(Icons.help, size: 22, color: _ink),
              onPressed: onHelp,
            ),
            IconButton(
              key: const Key('look_tools'),
              icon: const Icon(Icons.build, size: 22, color: _ink),
              onPressed: onTools,
            ),
            Container(width: 1, height: 24, color: const Color(0xFF9E9E9E)),
            IconButton(
              key: const Key('look_done'),
              icon: const Icon(Icons.check, size: 22, color: _accent),
              onPressed: onDone,
            ),
          ],
        ),
      );
}

/// Белая панель слайдеров под плашкой.
class LookSliders extends StatelessWidget {
  const LookSliders({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.white,
        child: Container(
          decoration: const BoxDecoration(border: Border(top: BorderSide(color: Color(0xFFE0E0E0)))),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: SafeArea(
            top: false,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
          ),
        ),
      );
}

/// Строка слайдера: минимум слева, «Название: значение» по центру,
/// максимум справа, под ними слайдер.
class LookSliderRow extends StatelessWidget {
  const LookSliderRow({
    super.key,
    required this.minLabel,
    required this.label,
    required this.maxLabel,
    required this.value,
    required this.min,
    required this.max,
    this.divisions,
    required this.onChanged,
  });

  final String minLabel;

  /// Центральная подпись: «Яркость: 93 %» или «r: 53 58 63».
  final Widget label;
  final String maxLabel;
  final double value;
  final double min;
  final double max;
  final int? divisions;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(child: Text(minLabel, style: const TextStyle(fontSize: 12, color: _secondary))),
              // На узком экране подпись ужимается, а не вылезает за край.
              Flexible(flex: 4, child: FittedBox(fit: BoxFit.scaleDown, child: label)),
              Expanded(
                child: Text(maxLabel, textAlign: TextAlign.right, style: const TextStyle(fontSize: 12, color: _secondary)),
              ),
            ],
          ),
          SliderTheme(
            data: const SliderThemeData(
              activeTrackColor: _accent,
              inactiveTrackColor: Color(0xFFE0E0E0),
              thumbColor: _accent,
            ),
            child: Slider(value: value.clamp(min, max), min: min, max: max, divisions: divisions, onChanged: onChanged),
          ),
        ],
      );
}

/// Кнопка диалогов экранов вида: бирюзовая, полужирная, капсом.
class LookDialogButton extends StatelessWidget {
  const LookDialogButton({super.key, required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => TextButton(
        style: TextButton.styleFrom(foregroundColor: _accent),
        onPressed: onPressed,
        child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600, letterSpacing: 0.5)),
      );
}
