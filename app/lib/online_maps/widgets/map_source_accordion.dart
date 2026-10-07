import 'package:flutter/material.dart';

import '../online_maps_models.dart';
import 'map_card.dart';

/// A source header (chevron, title, subtitle) whose map cards slide open
/// below it. Each accordion opens on its own; others are left as they are.
class MapSourceAccordion extends StatelessWidget {
  const MapSourceAccordion({
    super.key,
    required this.source,
    required this.maps,
    required this.isOpen,
    required this.onToggle,
    required this.onMapMore,
  });

  final OnlineMapSource source;

  /// [source]'s maps that pass the current filter.
  final List<OnlineMap> maps;
  final bool isOpen;
  final VoidCallback onToggle;
  final ValueChanged<OnlineMap> onMapMore;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final subtitle = source.subtitle;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          key: Key('source_header_${source.id}'),
          onTap: onToggle,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                AnimatedRotation(
                  turns: isOpen ? 0.5 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: const Icon(Icons.expand_more),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(source.title, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                      if (subtitle != null)
                        Text(
                          subtitle,
                          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        ClipRect(
          child: AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeInOut,
            alignment: Alignment.topCenter,
            child: isOpen
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
                    child: Column(
                      children: [for (final map in maps) MapCard(map: map, onMore: () => onMapMore(map))],
                    ),
                  )
                : const SizedBox(width: double.infinity),
          ),
        ),
      ],
    );
  }
}
