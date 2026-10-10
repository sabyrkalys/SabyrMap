import 'package:flutter/material.dart';

import '../descriptors/detail_data.dart';
import '../descriptors/detail_section.dart';
import '../sheet_menu.dart';
import 'landmark_details_field_row.dart';

/// Секция детализации: [▴ ЗАГОЛОВОК ... ⋮] и строки или своё тело.
class LandmarkDetailsSection extends StatefulWidget {
  const LandmarkDetailsSection({super.key, required this.section, required this.data, required this.onMore});

  final DetailSection section;
  final LandmarkDetailsData data;
  final VoidCallback onMore;

  @override
  State<LandmarkDetailsSection> createState() => _LandmarkDetailsSectionState();
}

class _LandmarkDetailsSectionState extends State<LandmarkDetailsSection> {
  late bool _expanded = widget.section.initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    final section = widget.section;
    final custom = section.customBody;
    return Column(
      key: Key('details_section_${section.title}'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            IconButton(
              key: Key('details_toggle_${section.title}'),
              icon: Icon(_expanded ? Icons.expand_less : Icons.expand_more),
              onPressed: () => setState(() => _expanded = !_expanded),
            ),
            Text(
              section.title,
              style: const TextStyle(
                fontSize: 13,
                color: SheetMenuColors.secondary,
                letterSpacing: 0.5,
                fontWeight: FontWeight.w500,
              ),
            ),
            const Spacer(),
            IconButton(
              key: Key('details_more_${section.title}'),
              icon: const Icon(Icons.more_vert),
              onPressed: widget.onMore,
            ),
          ],
        ),
        if (_expanded) ...[
          for (final field in section.fields)
            LandmarkDetailsFieldRow(
              label: field.label,
              value: field.valueResolver(widget.data),
              isMultiline: field.isMultiline,
            ),
          if (custom != null) custom(context, widget.data),
        ],
        const Divider(height: 1, color: Color(0xFFE0E0E0)),
      ],
    );
  }
}
