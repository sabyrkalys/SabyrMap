import 'dart:ui';

import 'package:flutter/material.dart';

import '../app_icons.dart';
import '../theme/app_text_styles.dart';
import '../widgets/app_icon.dart';

const double _itemHeight = 52;
const double _headerHeight = 48;
const double _iconSize = 24;
const double _horizontalPadding = 16;
const double _iconTextGap = 16;
const Color _dividerColor = Color(0xFFDADCE0);

/// Floating menu panel shown over the map: a title with a help button,
/// the main items, then collapsible sections, and a down-arrow pointing at
/// the nav icon that opened it. Scrolls when taller than the space it gets.
class MenuPanel extends StatelessWidget {
  const MenuPanel({
    super.key,
    required this.title,
    required this.items,
    this.sections = const [],
    required this.arrowCenterX,
  });

  static const double arrowWidth = 16;
  static const double arrowHeight = 8;
  static const double maxWidth = 400;
  static final Color background = Colors.white.withValues(alpha: 0.85);

  final String title;
  final List<Widget> items;
  final List<MenuSection> sections;

  /// Horizontal center of the arrow, from the panel's left edge.
  final double arrowCenterX;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: maxWidth),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Flexible(
            child: ClipRRect(
              key: const Key('menu_panel_card'),
              borderRadius: BorderRadius.circular(12),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                child: Material(
                  color: background,
                  child: SingleChildScrollView(
                    child: AnimatedSize(
                      duration: const Duration(milliseconds: 200),
                      curve: Curves.easeOut,
                      alignment: Alignment.bottomCenter,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _PanelHeader(title: title),
                          ...items,
                          for (final section in sections) ...[
                            const Divider(height: 1, thickness: 0.5, color: _dividerColor),
                            section,
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.only(left: arrowCenterX - arrowWidth / 2),
            child: CustomPaint(
              key: const Key('menu_panel_arrow'),
              size: const Size(arrowWidth, arrowHeight),
              painter: _DownArrowPainter(background),
            ),
          ),
        ],
      ),
    );
  }
}

class _PanelHeader extends StatelessWidget {
  const _PanelHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final style = AppTextStyles.sectionHeader(context);
    return SizedBox(
      height: _headerHeight,
      child: Padding(
        padding: const EdgeInsets.only(left: _horizontalPadding, right: 4),
        child: Row(
          children: [
            Expanded(child: Text(title, style: style)),
            // Help content is not designed yet.
            IconButton(
              key: const Key('menu_panel_help'),
              onPressed: null,
              icon: AppIcon(AppIcons.helpCircle, size: _iconSize, color: style.color),
            ),
          ],
        ),
      ),
    );
  }
}

/// Optional icon + label row. Without [onTap] it is a placeholder in the disabled style.
class MenuListItem extends StatelessWidget {
  const MenuListItem({super.key, this.icon, required this.label, this.onTap});

  final String? icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final style = onTap == null ? AppTextStyles.menuItemDisabled(context) : AppTextStyles.menuItem(context);
    final icon = this.icon;
    return InkWell(
      onTap: onTap,
      child: _MenuRow(
        leading: icon == null ? null : AppIcon(icon, size: _iconSize, color: style.color),
        label: Text(label, style: style),
      ),
    );
  }
}

class MenuSwitchItem extends StatelessWidget {
  const MenuSwitchItem({super.key, this.icon, required this.label, required this.value, required this.onChanged});

  final String? icon;
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final style = AppTextStyles.menuItem(context);
    final icon = this.icon;
    return InkWell(
      onTap: () => onChanged(!value),
      child: _MenuRow(
        leading: icon == null ? null : AppIcon(icon, size: _iconSize, color: style.color),
        label: Text(label, style: style),
        trailing: Switch(value: value, onChanged: onChanged),
      ),
    );
  }
}

class MenuCheckboxItem extends StatelessWidget {
  const MenuCheckboxItem({super.key, required this.label, required this.value, required this.onChanged});

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => onChanged(!value),
      child: _MenuRow(
        label: Text(label, style: AppTextStyles.menuItem(context)),
        trailing: Checkbox(value: value, onChanged: (v) => onChanged(v ?? false)),
      ),
    );
  }
}

/// Collapsible section: an upper-case title with a gear icon; tapping the
/// header shows or hides [children]. Starts collapsed.
class MenuSection extends StatefulWidget {
  const MenuSection({super.key, required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  State<MenuSection> createState() => _MenuSectionState();
}

class _MenuSectionState extends State<MenuSection> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final style = AppTextStyles.sectionHeader(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          key: Key('menu_section_${widget.title}'),
          onTap: () => setState(() => _expanded = !_expanded),
          child: SizedBox(
            height: _headerHeight,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: _horizontalPadding),
              child: Row(
                children: [
                  Expanded(child: Text(widget.title, style: style)),
                  AppIcon(AppIcons.gear, size: _iconSize, color: style.color),
                ],
              ),
            ),
          ),
        ),
        if (_expanded) ...widget.children,
      ],
    );
  }
}

class _MenuRow extends StatelessWidget {
  const _MenuRow({this.leading, required this.label, this.trailing});

  final Widget? leading;
  final Widget label;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final leading = this.leading;
    final trailing = this.trailing;
    return SizedBox(
      height: _itemHeight,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: _horizontalPadding),
        child: Row(
          children: [
            if (leading != null) ...[leading, const SizedBox(width: _iconTextGap)],
            Expanded(child: label),
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
