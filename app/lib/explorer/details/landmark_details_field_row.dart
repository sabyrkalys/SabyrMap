import 'package:flutter/material.dart';

import '../sheet_menu.dart';

/// Строка «подпись — значение».
class LandmarkDetailsFieldRow extends StatelessWidget {
  const LandmarkDetailsFieldRow({super.key, required this.label, required this.value, this.isMultiline = false});

  final String label;
  final String value;
  final bool isMultiline;

  @override
  Widget build(BuildContext context) => Padding(
    key: Key('details_field_$label'),
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 100,
          child: Text(
            label,
            style: const TextStyle(fontSize: 13, fontStyle: FontStyle.italic, color: SheetMenuColors.secondary),
          ),
        ),
        Expanded(
          child: Text(
            value,
            softWrap: isMultiline,
            maxLines: isMultiline ? null : 1,
            overflow: isMultiline ? TextOverflow.visible : TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: SheetMenuColors.text),
          ),
        ),
      ],
    ),
  );
}
