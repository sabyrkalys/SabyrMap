import 'package:flutter/material.dart';

import 'waypoint_property.dart';

/// One row of the «Ещё...» sheet: the property's icon and title.
class PropertyItem extends StatelessWidget {
  const PropertyItem({super.key, required this.property, required this.onTap});

  final WaypointProperty property;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      key: Key('waypoint_property_${property.type.name}'),
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Row(
          children: [
            SizedBox(width: 32, child: Icon(property.icon, size: 24, color: const Color(0xFF333333))),
            const SizedBox(width: 16),
            Expanded(
              child: Text(property.title, style: const TextStyle(fontSize: 16, color: Color(0xFF212121))),
            ),
          ],
        ),
      ),
    );
  }
}
