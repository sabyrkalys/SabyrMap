import 'package:flutter/material.dart';

/// «Переименовать папку»: новое имя или null («ОТМЕНА»). Пустое имя и имя
/// с `/` или `\` не принимаются.
class RenameFolderDialog extends StatefulWidget {
  const RenameFolderDialog({super.key, required this.currentName});

  final String currentName;

  static const Color accent = Color(0xFF00A38E);

  static Future<String?> show(BuildContext context, String currentName) =>
      showDialog<String>(context: context, builder: (_) => RenameFolderDialog(currentName: currentName));

  /// Ошибка имени для подсказки; null — имя годится.
  static String? validate(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return '';
    if (trimmed.contains('/') || trimmed.contains(r'\')) return 'Недопустимые символы';
    if (trimmed == '.' || trimmed == '..') return 'Недопустимое имя';
    return null;
  }

  @override
  State<RenameFolderDialog> createState() => _RenameFolderDialogState();
}

class _RenameFolderDialogState extends State<RenameFolderDialog> {
  late final TextEditingController _name = TextEditingController(text: widget.currentName)
    ..selection = TextSelection(baseOffset: 0, extentOffset: widget.currentName.length);

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final error = RenameFolderDialog.validate(_name.text);
    const underline = UnderlineInputBorder(borderSide: BorderSide(color: RenameFolderDialog.accent));
    return AlertDialog(
      key: const Key('rename_folder_dialog'),
      insetPadding: EdgeInsets.symmetric(horizontal: width * 0.075, vertical: 24),
      title: const Text('Переименовать папку', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w500)),
      content: SizedBox(
        width: width * 0.85,
        child: TextField(
          key: const Key('rename_folder_field'),
          controller: _name,
          autofocus: true,
          maxLength: 200,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            enabledBorder: underline,
            focusedBorder: underline,
            errorText: error != null && error.isNotEmpty ? error : null,
          ),
        ),
      ),
      actions: [
        TextButton(
          key: const Key('rename_folder_cancel'),
          onPressed: () => Navigator.pop(context),
          style: TextButton.styleFrom(foregroundColor: RenameFolderDialog.accent),
          child: const Text('ОТМЕНА'),
        ),
        TextButton(
          key: const Key('rename_folder_ok'),
          onPressed: error == null ? () => Navigator.pop(context, _name.text.trim()) : null,
          style: TextButton.styleFrom(foregroundColor: RenameFolderDialog.accent),
          child: const Text('ОК', style: TextStyle(fontWeight: FontWeight.w600)),
        ),
      ],
    );
  }
}
