import 'package:flutter/material.dart';

import '../home/home_nav_scope.dart';
import 'descriptors/context_menu_action.dart';
import 'descriptors/context_menu_section.dart';
import 'sheet_menu.dart';

/// Шторка меню из [ContextMenuSection]: заголовок, секции (пустые не
/// показываются), «ОТМЕНА». Пункт закрывает шторку и выполняется на
/// экране [origin]; пункты секций [ContextMenuSection.keepsOpen]
/// выполняются сразу, шторка перерисовывается.
class ContextMenuSheet extends StatefulWidget {
  const ContextMenuSheet({
    super.key,
    required this.title,
    required this.sections,
    required this.env,
    required this.origin,
    required this.keyPrefix,
  });

  final String title;
  final List<ContextMenuSection> sections;

  /// Окружение для резолверов пунктов.
  final Object env;

  /// Экран, с которого открыта шторка.
  final BuildContext origin;

  /// Префикс ключей пунктов: `<prefix>_<id>`.
  final String keyPrefix;

  static Future<void> show(
    BuildContext context, {
    required String title,
    required List<ContextMenuSection> sections,
    required Object env,
    required String keyPrefix,
    Key? key,
  }) => HomeNavScope.showSheet(
    context,
    (_) => ContextMenuSheet(key: key, title: title, sections: sections, env: env, origin: context, keyPrefix: keyPrefix),
  );

  @override
  State<ContextMenuSheet> createState() => _ContextMenuSheetState();
}

class _ContextMenuSheetState extends State<ContextMenuSheet> {
  Future<void> _run(ContextMenuSection section, ContextMenuAction action) async {
    if (section.keepsOpen) {
      await action.onTap(widget.origin);
      if (mounted) setState(() {});
      return;
    }
    Navigator.of(context).pop();
    if (widget.origin.mounted) await action.onTap(widget.origin);
  }

  Widget _item(ContextMenuSection section, ContextMenuAction action) {
    final env = widget.env;
    final key = Key('${widget.keyPrefix}_${action.id}');
    final enabled = action.enabledFor(env);
    final label = action.labelFor(env);
    if (section.isRadio) {
      final selected = action.isSelected?.call(env) ?? false;
      return InkWell(
        key: key,
        onTap: enabled ? () => _run(section, action) : null,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            children: [
              SizedBox(
                width: 32,
                child: Icon(
                  selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                  size: 22,
                  color: selected ? SheetMenuColors.text : SheetMenuColors.secondary,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 16,
                    color: selected ? SheetMenuColors.text : SheetMenuColors.secondary,
                    fontWeight: selected ? FontWeight.w500 : FontWeight.w400,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }
    final item = SheetMenuItem(
      key: key,
      icon: action.icon,
      color: Color(action.iconColor),
      label: label,
      onTap: () => _run(section, action),
    );
    return enabled ? item : Opacity(opacity: 0.4, child: IgnorePointer(child: item));
  }

  @override
  Widget build(BuildContext context) => SheetMenu(
    title: widget.title,
    children: [
      for (final section in widget.sections)
        if (section.actions.isNotEmpty) ...[
          if (section.title case final title?) SheetMenuSection(title),
          for (final action in section.actions) _item(section, action),
        ],
      SheetMenuCancel(buttonKey: Key('${widget.keyPrefix}_cancel'), onPressed: () => Navigator.of(context).pop()),
    ],
  );
}
