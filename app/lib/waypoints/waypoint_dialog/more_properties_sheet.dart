import 'package:flutter/material.dart';

import 'property_item.dart';
import 'waypoint_property.dart';

/// Opens «Ещё...» over the waypoint dialog. Completes with the chosen
/// property's type, or null on «ОТМЕНА».
Future<WaypointPropertyType?> showMorePropertiesSheet(BuildContext context) {
  return showModalBottomSheet<WaypointPropertyType>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: MorePropertiesSheet.background,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
    builder: (_) => const MorePropertiesSheet(),
  );
}

/// «Ещё...»: the waypoint's other properties, at most 85% of the screen tall.
class MorePropertiesSheet extends StatelessWidget {
  const MorePropertiesSheet({super.key, this.properties = waypointProperties});

  static const Color background = Color(0xFFEEF1F5);

  final List<WaypointProperty> properties;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.85),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Padding(
                padding: EdgeInsets.only(bottom: 20),
                child: Text(
                  'Ещё...',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w500, color: Color(0xFF212121)),
                ),
              ),
              Flexible(
                child: SingleChildScrollView(
                  key: const Key('more_properties_sheet'),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final (i, property) in properties.indexed) ...[
                        if (i > 0) const SizedBox(height: 4),
                        PropertyItem(property: property, onTap: () => Navigator.of(context).pop(property.type)),
                      ],
                    ],
                  ),
                ),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  key: const Key('more_properties_cancel'),
                  onPressed: () => Navigator.of(context).pop(),
                  style: TextButton.styleFrom(foregroundColor: const Color(0xFF00A38E)),
                  child: const Text('ОТМЕНА', style: TextStyle(fontWeight: FontWeight.w600, letterSpacing: 0.5)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
