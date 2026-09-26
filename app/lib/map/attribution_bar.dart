import 'package:flutter/material.dart';

import 'models/map_models.dart';

/// Attributions of every visible layer (base + overlays), without repeats:
/// «© OpenFreeMap · © OpenStreetMap contributors». Providers require it on
/// screen, so it is never hidden.
String attributionText(MapSource? base, List<MapSource> visibleOverlays) {
  final parts = <String>[];
  for (final source in [if (base != null) base, ...visibleOverlays]) {
    for (final part in (source.attribution ?? '').split('·')) {
      final text = part.trim();
      if (text.isNotEmpty && !parts.contains(text)) parts.add(text);
    }
  }
  return parts.join(' · ');
}

class AttributionBar extends StatelessWidget {
  const AttributionBar({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    if (text.isEmpty) return const SizedBox.shrink();
    return DecoratedBox(
      key: const Key('attribution_bar'),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        child: Text(text, style: const TextStyle(fontSize: 10, color: Color(0xFF16181A))),
      ),
    );
  }
}
