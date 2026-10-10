import 'package:flutter/material.dart';

import '../sheet_menu.dart';

/// Имя, комментарий и описание файла меток.
class LandmarkProperties {
  const LandmarkProperties({
    this.name = '',
    this.comment = '',
    this.description = '',
  });

  final String name;
  final String comment;
  final String description;

  @override
  bool operator ==(Object other) =>
      other is LandmarkProperties &&
      other.name == name &&
      other.comment == comment &&
      other.description == description;

  @override
  int get hashCode => Object.hash(name, comment, description);
}

/// «Свойства»: имя, комментарий, описание; null — «ОТМЕНА».
class LandmarkPropertiesDialog extends StatefulWidget {
  const LandmarkPropertiesDialog({super.key, this.initial = const LandmarkProperties()});

  final LandmarkProperties initial;

  static Future<LandmarkProperties?> show(
    BuildContext context, {
    LandmarkProperties initial = const LandmarkProperties(),
  }) => showDialog<LandmarkProperties>(
    context: context,
    builder: (_) => LandmarkPropertiesDialog(initial: initial),
  );

  @override
  State<LandmarkPropertiesDialog> createState() => _LandmarkPropertiesDialogState();
}

class _LandmarkPropertiesDialogState extends State<LandmarkPropertiesDialog> {
  late final TextEditingController _name = TextEditingController(
    text: widget.initial.name,
  );
  late final TextEditingController _comment = TextEditingController(
    text: widget.initial.comment,
  );
  late final TextEditingController _description = TextEditingController(
    text: widget.initial.description,
  );

  @override
  void dispose() {
    _name.dispose();
    _comment.dispose();
    _description.dispose();
    super.dispose();
  }

  Widget _field(
    String key,
    String label,
    TextEditingController controller, {
    int maxLines = 1,
    int? maxLength,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextField(
      key: Key('ldk_props_$key'),
      controller: controller,
      maxLines: maxLines,
      minLines: 1,
      maxLength: maxLength,
      decoration: InputDecoration(
        labelText: label,
        floatingLabelStyle: const TextStyle(color: SheetMenuColors.accent),
        focusedBorder: const UnderlineInputBorder(
          borderSide: BorderSide(color: SheetMenuColors.accent, width: 1.5),
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    return AlertDialog(
      key: const Key('ldk_properties_dialog'),
      backgroundColor: Colors.white,
      insetPadding: EdgeInsets.symmetric(
        horizontal: width * 0.075,
        vertical: 24,
      ),
      title: const Text(
        'Свойства',
        style: TextStyle(fontSize: 20, fontWeight: FontWeight.w500),
      ),
      content: SizedBox(
        width: width * 0.85,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _field('name', 'Имя', _name, maxLength: 200),
              _field('comment', 'Комментарий', _comment, maxLines: 3),
              _field('description', 'Описание', _description, maxLines: 5),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          key: const Key('ldk_props_cancel'),
          onPressed: () => Navigator.pop(context),
          style: TextButton.styleFrom(foregroundColor: SheetMenuColors.accent),
          child: const Text(
            'ОТМЕНА',
            style: TextStyle(fontWeight: FontWeight.w600, letterSpacing: 0.5),
          ),
        ),
        TextButton(
          key: const Key('ldk_props_ok'),
          onPressed: () => Navigator.pop(
            context,
            LandmarkProperties(
              name: _name.text.trim(),
              comment: _comment.text,
              description: _description.text,
            ),
          ),
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
