import 'package:flutter/material.dart';

import '../../../explorer/sheet_menu.dart';

/// Ответ на [ReplaceScreenDialog]: сохранить ли экран избранным набором и
/// запомнить ли ответ («Не задавать этот вопрос»).
typedef ReplaceScreenAnswer = ({bool save, bool remember});

/// «Карты на экране»: перед «Показать» — конфигурация будет заменена,
/// сохранить её в избранном наборе? ОТМЕНА / НЕТ / ДА; null — отмена.
class ReplaceScreenDialog extends StatefulWidget {
  const ReplaceScreenDialog({super.key});

  static Future<ReplaceScreenAnswer?> show(BuildContext context) =>
      showDialog<ReplaceScreenAnswer>(context: context, builder: (_) => const ReplaceScreenDialog());

  @override
  State<ReplaceScreenDialog> createState() => _ReplaceScreenDialogState();
}

class _ReplaceScreenDialogState extends State<ReplaceScreenDialog> {
  static const Color _info = Color(0xFF29A8E0);

  bool _remember = false;

  @override
  Widget build(BuildContext context) {
    final button = TextButton.styleFrom(foregroundColor: SheetMenuColors.accent);
    void answer(bool save) => Navigator.of(context).pop((save: save, remember: _remember));
    return AlertDialog(
      key: const Key('replace_screen_dialog'),
      title: const Row(
        children: [
          Icon(Icons.info, color: _info, size: 32),
          SizedBox(width: 12),
          Expanded(child: Text('Карты на экране', style: TextStyle(color: _info))),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Конфигурация отображаемых в данный момент карт будет заменена и утеряна.'),
          const SizedBox(height: 16),
          const Text('Сохранить её в избранном наборе карт?'),
          const SizedBox(height: 8),
          CheckboxListTile(
            key: const Key('replace_screen_remember'),
            value: _remember,
            onChanged: (v) => setState(() => _remember = v ?? false),
            title: const Text('Не задавать этот вопрос'),
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
            activeColor: SheetMenuColors.accent,
          ),
        ],
      ),
      actionsAlignment: MainAxisAlignment.spaceBetween,
      actions: [
        TextButton(
          key: const Key('replace_screen_cancel'),
          style: button,
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('ОТМЕНА'),
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextButton(
              key: const Key('replace_screen_no'),
              style: button,
              onPressed: () => answer(false),
              child: const Text('НЕТ'),
            ),
            TextButton(
              key: const Key('replace_screen_yes'),
              style: button,
              onPressed: () => answer(true),
              child: const Text('ДА'),
            ),
          ],
        ),
      ],
    );
  }
}
