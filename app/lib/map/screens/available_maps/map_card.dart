import 'package:flutter/material.dart';

import '../../../app_icons.dart';
import '../../../widgets/app_icon.dart';
import 'available_maps_models.dart';

/// A map as a 96 px preview strip: preview image (or a placeholder tinted by
/// [kind]), dark gradient towards the right, name and caption on the right,
/// [menu] top-right. [selected] outlines the map on screen; a card that is
/// not [enabled] is dimmed and ignores taps.
class MapCard extends StatelessWidget {
  const MapCard({
    super.key,
    required this.name,
    required this.caption,
    required this.kind,
    this.thumbnailAsset,
    this.favorite = false,
    this.selected = false,
    this.enabled = true,
    this.onTap,
    this.menu,
  });

  final String name;
  final String caption;
  final MapKind kind;
  final String? thumbnailAsset;
  final bool favorite;
  final bool selected;
  final bool enabled;
  final VoidCallback? onTap;
  final Widget? menu;

  @override
  Widget build(BuildContext context) {
    final thumbnail = thumbnailAsset;
    final radius = BorderRadius.circular(8);
    return Opacity(
      opacity: enabled ? 1 : 0.4,
      child: Container(
        height: 96,
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          borderRadius: radius,
          border: selected ? Border.all(color: Theme.of(context).colorScheme.primary, width: 3) : null,
          boxShadow: const [BoxShadow(color: Color(0x22000000), blurRadius: 3, offset: Offset(0, 1))],
        ),
        child: ClipRRect(
          borderRadius: selected ? BorderRadius.circular(5) : radius,
          child: Stack(
            children: [
              Positioned.fill(
                child: thumbnail != null
                    ? Image.asset(
                        thumbnail,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => _PreviewPlaceholder(kind: kind),
                      )
                    : _PreviewPlaceholder(kind: kind),
              ),
              const Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(gradient: LinearGradient(colors: [Colors.transparent, Color(0x80000000)])),
                ),
              ),
              Positioned.fill(
                child: Material(
                  type: MaterialType.transparency,
                  child: InkWell(onTap: enabled ? onTap : null),
                ),
              ),
              Positioned(
                right: 12,
                bottom: 10,
                left: 12,
                child: IgnorePointer(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          if (favorite) ...[
                            const AppIcon(AppIcons.star, size: 16, color: Colors.white),
                            const SizedBox(width: 6),
                          ],
                          Flexible(
                            child: Text(
                              name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700),
                            ),
                          ),
                        ],
                      ),
                      Text(caption, style: const TextStyle(color: Colors.white70, fontSize: 13)),
                    ],
                  ),
                ),
              ),
              if (menu case final menu?) Positioned(top: 0, right: 0, child: menu),
            ],
          ),
        ),
      ),
    );
  }
}

/// Shown when the map has no bundled preview.
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
