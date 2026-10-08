import 'package:flutter/material.dart';

import 'marker_type.dart';

/// One row of the «Новая метка» sheet: icon, title and the optional
/// explanation under it. Every row looks equally available.
class MarkerTypeItem extends StatelessWidget {
  const MarkerTypeItem({super.key, required this.type, required this.onTap});

  static const Color iconColor = Color(0xFF333333);
  static const Color titleColor = Color(0xFF212121);
  static const Color subtitleColor = Color(0xFF757575);

  final MarkerType type;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final subtitle = type.subtitle;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        key: Key('marker_type_${type.id}'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Row(
            children: [
              SizedBox(width: 32, child: Icon(type.icon, size: 24, color: iconColor)),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      type.title,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w400, color: titleColor),
                    ),
                    if (subtitle != null)
                      Text(subtitle, style: const TextStyle(fontSize: 13, color: subtitleColor, height: 1.3)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
