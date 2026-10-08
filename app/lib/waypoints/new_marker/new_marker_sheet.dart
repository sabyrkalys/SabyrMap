import 'package:flutter/material.dart';

import 'marker_type.dart';
import 'marker_type_item.dart';
import 'section_header.dart';

/// Opens the «Новая метка» sheet. Completes with the chosen type, or null
/// when it was closed with «ОТМЕНА», a swipe down or a tap outside.
Future<MarkerType?> showNewMarkerSheet(BuildContext context) {
  return showModalBottomSheet<MarkerType>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: NewMarkerSheet.background,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
    builder: (context) => NewMarkerSheet(onMarkerTypeSelected: (type) => Navigator.of(context).pop(type)),
  );
}

/// «Новая метка»: what can be made at the crosshair, built from
/// [markerTypes] in two sections, ЛОКАЛЬНЫЕ МЕТКИ and ИНСТРУМЕНТЫ.
class NewMarkerSheet extends StatelessWidget {
  const NewMarkerSheet({super.key, required this.onMarkerTypeSelected, this.types = markerTypes});

  static const Color background = Color(0xFFF5F6F8);
  static const Color cancelColor = Color(0xFF00A38E);

  final ValueChanged<MarkerType> onMarkerTypeSelected;
  final List<MarkerType> types;

  static const _sections = [(MarkerCategory.local, 'Локальные метки'), (MarkerCategory.tool, 'Инструменты')];

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        key: const Key('new_marker_sheet'),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.only(bottom: 20),
              child: Text('Новая метка', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w500)),
            ),
            for (final (category, label) in _sections) ...[
              SectionHeader(label: label),
              for (final type in types.where((t) => t.category == category))
                MarkerTypeItem(type: type, onTap: () => onMarkerTypeSelected(type)),
            ],
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                key: const Key('new_marker_cancel'),
                onPressed: () => Navigator.of(context).pop(),
                style: TextButton.styleFrom(foregroundColor: cancelColor),
                child: const Text('ОТМЕНА', style: TextStyle(fontWeight: FontWeight.w600, letterSpacing: 0.5)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
