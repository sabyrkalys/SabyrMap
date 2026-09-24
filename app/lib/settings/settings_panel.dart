import 'package:flutter/material.dart';

import '../app_icons.dart';
import '../theme/app_text_styles.dart';
import '../widgets/app_icon.dart';

/// Settings tab content: a floating panel over the map with the main items
/// and the options header. Tapping the header slides the option toggles out
/// below it (the panel grows upward). A downward arrow under the panel
/// points at the settings tab icon. All items are placeholders until each
/// function is implemented.
class SettingsPanel extends StatefulWidget {
  const SettingsPanel({super.key, required this.arrowCenterX});

  static const double arrowWidth = 16;
  static const double arrowHeight = 8;

  /// Horizontal center of the arrow, from the panel's left edge.
  final double arrowCenterX;

  @override
  State<SettingsPanel> createState() => _SettingsPanelState();
}

class _SettingsPanelState extends State<SettingsPanel> {
  static const double _headerHeight = 48;
  static const double _itemHeight = 52;
  static const double _iconSize = 24;
  static const double _horizontalPadding = 16;
  static const double _iconTextGap = 16;
  static const Duration _expandDuration = Duration(milliseconds: 200);

  static const _mainItems = [
    (icon: AppIcons.fullscreen, label: 'Скрыть кнопки меню'),
    (icon: AppIcons.lock, label: 'Блокировка экрана'),
    (icon: AppIcons.camera, label: 'Снимок экрана'),
    (icon: AppIcons.settings, label: 'Настройки'),
  ];

  static const _optionItems = [
    (icon: AppIcons.layers, label: 'Координатная сетка СК-42 (Гаусса-Крюгера)'),
    (icon: AppIcons.eye, label: 'Ночной режим'),
    (icon: AppIcons.geoTarget, label: 'Координаты центра экрана'),
  ];

  bool _optionsExpanded = false;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.surface;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Material(
          key: const Key('settings_panel_card'),
          color: color,
          borderRadius: BorderRadius.circular(12),
          clipBehavior: Clip.antiAlias,
          child: AnimatedSize(
            duration: _expandDuration,
            curve: Curves.easeOut,
            alignment: Alignment.bottomCenter,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final item in _mainItems) _buildItem(context, item.icon, item.label),
                _buildHeader(context),
                if (_optionsExpanded)
                  for (final item in _optionItems) _buildItem(context, item.icon, item.label, toggle: true),
              ],
            ),
          ),
        ),
        Padding(
          padding: EdgeInsets.only(left: widget.arrowCenterX - SettingsPanel.arrowWidth / 2),
          child: CustomPaint(
            key: const Key('settings_panel_arrow'),
            size: const Size(SettingsPanel.arrowWidth, SettingsPanel.arrowHeight),
            painter: _DownArrowPainter(color),
          ),
        ),
      ],
    );
  }

  Widget _buildHeader(BuildContext context) {
    final style = AppTextStyles.sectionHeader(context);
    return InkWell(
      key: const Key('settings_options_header'),
      onTap: () => setState(() => _optionsExpanded = !_optionsExpanded),
      child: _row(
        height: _headerHeight,
        icon: AppIcon(AppIcons.chevronUpdown, size: _iconSize, color: style.color),
        text: Text('ОПЦИИ', style: style),
      ),
    );
  }

  /// A [toggle] item gets a checkbox on the right (always off until the
  /// option is implemented).
  Widget _buildItem(BuildContext context, String icon, String label, {bool toggle = false}) {
    final style = AppTextStyles.menuItemDisabled(context);
    return _row(
      height: _itemHeight,
      icon: AppIcon(icon, size: _iconSize, color: style.color),
      text: Text(label, style: style),
      trailing: toggle
          ? AppIcon(
              AppIcons.checkboxOff,
              key: const Key('settings_option_checkbox'),
              size: _iconSize,
              color: style.color,
            )
          : null,
    );
  }

  Widget _row({required double height, required Widget icon, required Widget text, Widget? trailing}) {
    return SizedBox(
      height: height,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: _horizontalPadding),
        child: Row(
          children: [
            icon,
            const SizedBox(width: _iconTextGap),
            Expanded(child: text),
            if (trailing != null) ...[const SizedBox(width: _iconTextGap), trailing],
          ],
        ),
      ),
    );
  }
}

class _DownArrowPainter extends CustomPainter {
  const _DownArrowPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width / 2, size.height)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_DownArrowPainter oldDelegate) => oldDelegate.color != color;
}
