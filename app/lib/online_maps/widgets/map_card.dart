import 'package:flutter/material.dart';

import '../../app_icons.dart';
import '../../widgets/app_icon.dart';
import '../online_maps_models.dart';

/// A map as a 96 px preview strip: server preview image, dark gradient
/// towards the right, name and cached size on the right, menu top-right.
class MapCard extends StatelessWidget {
  const MapCard({super.key, required this.map, required this.onMore});

  final OnlineMap map;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 96,
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        boxShadow: const [BoxShadow(color: Color(0x22000000), blurRadius: 3, offset: Offset(0, 1))],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Stack(
          children: [
            Positioned.fill(
              child: Image.network(
                map.resolvedPreviewUrl,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => _PreviewPlaceholder(kind: map.kind),
              ),
            ),
            const Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(gradient: LinearGradient(colors: [Colors.transparent, Color(0x80000000)])),
              ),
            ),
            Positioned(
              right: 12,
              bottom: 10,
              left: 12,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    map.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                  Text(map.size, style: const TextStyle(color: Colors.white70, fontSize: 13)),
                ],
              ),
            ),
            Positioned(
              top: 0,
              right: 0,
              child: IconButton(
                key: Key('map_card_more_${map.id}'),
                icon: const AppIcon(AppIcons.dotsVertical, color: Colors.white),
                onPressed: onMore,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Shown until the server has a preview for the map.
class _PreviewPlaceholder extends StatelessWidget {
  const _PreviewPlaceholder({required this.kind});

  final MapKind kind;

  @override
  Widget build(BuildContext context) {
    final colors = switch (kind) {
      MapKind.scheme => const [Color(0xFFE8E4D8), Color(0xFFB9D3A8)],
      MapKind.terrain => const [Color(0xFFD9CFB0), Color(0xFF9DB58A)],
      MapKind.hybrid => const [Color(0xFF4E5D3A), Color(0xFF8A8F6A)],
      MapKind.satellite => const [Color(0xFF2F3D2A), Color(0xFF5F6B4B)],
    };
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: colors),
      ),
    );
  }
}
