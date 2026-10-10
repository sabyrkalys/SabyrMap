import 'package:flutter/material.dart';

import '../sheet_menu.dart';

/// «Переименовать» файл меток: новое имя или null («ОТМЕНА»). Пустое имя
/// не принимается.
class LdkRenameDialog extends StatefulWidget {
  const LdkRenameDialog({super.key, required this.currentName});

  final String currentName;

  static Future<String?> show(BuildContext context, String currentName) =>
      showDialog<String>(
        context: context,
        builder: (_) => LdkRenameDialog(currentName: currentName),
      );

  @override
  State<LdkRenameDialog> createState() => _LdkRenameDialogState();
}

class _LdkRenameDialogState extends State<LdkRenameDialog> {
  late final TextEditingController _name =
      TextEditingController(text: widget.currentName)
        ..selection = TextSelection(
          baseOffset: 0,
          extentOffset: widget.currentName.length,
        );

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    const underline = UnderlineInputBorder(
      borderSide: BorderSide(color: SheetMenuColors.accent),
    );
    final valid = _name.text.trim().isNotEmpty;
    return AlertDialog(
      key: const Key('ldk_rename_dialog'),
      backgroundColor: Colors.white,
      insetPadding: EdgeInsets.symmetric(
        horizontal: width * 0.075,
        vertical: 24,
      ),
      title: const Text(
        'Переименовать',
        style: TextStyle(fontSize: 20, fontWeight: FontWeight.w500),
      ),
      content: SizedBox(
        width: width * 0.85,
        child: TextField(
          key: const Key('ldk_rename_field'),
          controller: _name,
          autofocus: true,
          maxLength: 200,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(
            enabledBorder: underline,
            focusedBorder: underline,
          ),
        ),
      ),
      actions: [
        TextButton(
          key: const Key('ldk_rename_cancel'),
          onPressed: () => Navigator.pop(context),
          style: TextButton.styleFrom(foregroundColor: SheetMenuColors.accent),
          child: const Text(
            'ОТМЕНА',
            style: TextStyle(fontWeight: FontWeight.w600, letterSpacing: 0.5),
          ),
        ),
        TextButton(
          key: const Key('ldk_rename_ok'),
          onPressed: valid
              ? () => Navigator.pop(context, _name.text.trim())
              : null,
          style: TextButton.styleFrom(foregroundColor: SheetMenuColors.accent),
          child: const Text(
            'ОК',
            style: TextStyle(fontWeight: FontWeight.w600, letterSpacing: 0.5),
          ),
        ),
      ],
    );
  }
}
