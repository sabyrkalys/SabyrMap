import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'marker_icon.dart';

const Color _iconColor = Color(0xFF333333);

/// How [icon] looks: its glyph, its picture file, or a filled circle.
class MarkerIconGlyph extends StatelessWidget {
  const MarkerIconGlyph({super.key, required this.icon, this.size = 22});

  final MarkerIcon icon;
  final double size;

  @override
  Widget build(BuildContext context) {
    final path = icon.assetPath;
    if (path != null) {
      return path.toLowerCase().endsWith('.svg')
          ? SvgPicture.file(
              File(path),
              width: size,
              height: size,
              placeholderBuilder: (_) => Icon(Icons.image, size: size, color: _iconColor),
            )
          : Image.file(
              File(path),
              width: size,
              height: size,
              errorBuilder: (_, _, _) => Icon(Icons.broken_image, size: size, color: _iconColor),
            );
    }
    final glyph = icon.icon;
    if (glyph != null) return Icon(glyph, size: size, color: _iconColor);
    return Container(
      width: size * 12 / 22,
      height: size * 12 / 22,
      decoration: const BoxDecoration(shape: BoxShape.circle, color: _iconColor),
    );
  }
}

/// One icon in a category: the icon in a 28×28 box, then its name.
class IconItem extends StatelessWidget {
  const IconItem({super.key, required this.icon, required this.onTap, this.selected = false});

  final MarkerIcon icon;
  final VoidCallback onTap;

  /// The waypoint's current icon: its name is in bold.
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      key: Key('marker_icon_${icon.id}'),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
        child: Row(
          children: [
            SizedBox(
              width: 28,
              height: 28,
              child: Center(child: MarkerIconGlyph(icon: icon)),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                icon.label,
                style: TextStyle(
                  fontSize: 15,
                  color: const Color(0xFF212121),
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
