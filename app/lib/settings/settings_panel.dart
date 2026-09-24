import 'package:flutter/material.dart';

import '../app_icons.dart';
import '../theme/app_text_styles.dart';
import '../widgets/app_icon.dart';

/// Settings tab content: a floating panel over the map. Collapsed it shows
/// only the options header; tapping the header slides the items out above
/// it. The items are placeholders until each function is implemented.
class SettingsPanel extends StatefulWidget {
  const SettingsPanel({super.key});

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

  static const _items = [
    (icon: AppIcons.fullscreen, label: 'Скрыть кнопки меню'),
    (icon: AppIcons.lock, label: 'Блокировка экрана'),
    (icon: AppIcons.camera, label: 'Снимок экрана'),
    (icon: AppIcons.settings, label: 'Настройки'),
  ];

  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: AnimatedSize(
        duration: _expandDuration,
        curve: Curves.easeOut,
        alignment: Alignment.bottomCenter,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_expanded)
              for (final item in _items) _buildItem(context, item.icon, item.label),
            _buildHeader(context),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final style = AppTextStyles.sectionHeader(context);
    return InkWell(
      key: const Key('settings_options_header'),
      onTap: () => setState(() => _expanded = !_expanded),
      child: _row(
        height: _headerHeight,
        icon: AppIcon(AppIcons.chevronUpdown, size: _iconSize, color: style.color),
        text: Text('ОПЦИИ', style: style),
      ),
    );
  }

  Widget _buildItem(BuildContext context, String icon, String label) {
    final style = AppTextStyles.menuItemDisabled(context);
    return _row(
      height: _itemHeight,
      icon: AppIcon(icon, size: _iconSize, color: style.color),
      text: Text(label, style: style),
    );
  }

  Widget _row({required double height, required Widget icon, required Widget text}) {
    return SizedBox(
      height: height,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: _horizontalPadding),
        child: Row(
          children: [
            icon,
            const SizedBox(width: _iconTextGap),
            Expanded(child: text),
          ],
        ),
      ),
    );
  }
}
