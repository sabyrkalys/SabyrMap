import 'dart:ui';

import 'package:flutter/material.dart';

import '../app_icons.dart';
import '../menu/menu_widgets.dart';
import '../theme/app_text_styles.dart';
import '../widgets/app_icon.dart';

/// Context card opened by tapping the map crosshair. The pin / camera /
/// info icons are a separate function from the items, so they sit in their
/// own row above a divider. Tools are placeholders for now.
class CrosshairMenu extends StatefulWidget {
  const CrosshairMenu({
    super.key,
    required this.hasTarget,
    required this.onSetTarget,
    required this.onRemoveTarget,
    required this.onNewWaypoint,
    required this.onInfo,
  });

  static const double triangleWidth = 16;
  static const double triangleHeight = 8;
  static const double maxWidth = 320;

  static const tools = [
    'Поиск на карте (по имени)',
    'Спроектировать местоположение',
    'Автомаршрутизация',
    'Измерение',
    'Уклон',
    'Оповещение о сближении',
    'Поделиться',
  ];

  final bool hasTarget;
  final VoidCallback onSetTarget;
  final VoidCallback onRemoveTarget;
  final VoidCallback onNewWaypoint;
  final VoidCallback onInfo;

  @override
  State<CrosshairMenu> createState() => _CrosshairMenuState();
}

class _CrosshairMenuState extends State<CrosshairMenu> {
  bool _showTools = false;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: CrosshairMenu.maxWidth),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: ClipRRect(
              key: const Key('crosshair_menu'),
              borderRadius: BorderRadius.circular(12),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                child: Material(
                  color: MenuPanel.background,
                  child: SingleChildScrollView(
                    child: AnimatedSize(
                      duration: const Duration(milliseconds: 200),
                      curve: Curves.easeOut,
                      child: _showTools ? _buildTools(context) : _buildMain(context),
                    ),
                  ),
                ),
              ),
            ),
          ),
          CustomPaint(
            key: const Key('crosshair_menu_triangle'),
            size: const Size(CrosshairMenu.triangleWidth, CrosshairMenu.triangleHeight),
            painter: _TrianglePainter(MenuPanel.background),
          ),
        ],
      ),
    );
  }

  Widget _buildMain(BuildContext context) {
    final disabled = AppTextStyles.menuItemDisabled(context).color;
    Widget placeholderIcon(String key, String icon) => IconButton(
      key: Key(key),
      onPressed: null,
      icon: AppIcon(icon, size: 24, color: disabled),
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              placeholderIcon('crosshair_menu_pin', AppIcons.pinPlus),
              placeholderIcon('crosshair_menu_camera', AppIcons.camera),
              IconButton(
                key: const Key('crosshair_menu_info'),
                onPressed: widget.onInfo,
                icon: AppIcon(AppIcons.info, size: 24, color: AppTextStyles.menuItem(context).color),
              ),
            ],
          ),
        ),
        const Divider(height: 1, thickness: 0.5, color: Color(0xFFDADCE0)),
        if (widget.hasTarget)
          MenuListItem(icon: AppIcons.close, label: 'Убрать цель', onTap: widget.onRemoveTarget)
        else
          MenuListItem(icon: AppIcons.arrowRight, label: 'Задать цель', onTap: widget.onSetTarget),
        MenuListItem(icon: AppIcons.flagPlus, label: 'Новая метка...', onTap: widget.onNewWaypoint),
        MenuListItem(icon: AppIcons.wrench, label: 'Инструменты...', onTap: () => setState(() => _showTools = true)),
      ],
    );
  }

  Widget _buildTools(BuildContext context) {
    final style = AppTextStyles.sectionHeader(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          key: const Key('crosshair_menu_tools_back'),
          onTap: () => setState(() => _showTools = false),
          child: SizedBox(
            height: 48,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Transform.flip(flipX: true, child: AppIcon(AppIcons.arrowRight, size: 24, color: style.color)),
                  const SizedBox(width: 16),
                  Text('Инструменты', style: style),
                ],
              ),
            ),
          ),
        ),
        const Divider(height: 1, thickness: 0.5, color: Color(0xFFDADCE0)),
        for (final tool in CrosshairMenu.tools) MenuListItem(label: tool),
      ],
    );
  }
}

class _TrianglePainter extends CustomPainter {
  const _TrianglePainter(this.color);

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
  bool shouldRepaint(_TrianglePainter oldDelegate) => oldDelegate.color != color;
}
