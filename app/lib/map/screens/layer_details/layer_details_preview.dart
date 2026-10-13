import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/map_models.dart';
import '../../services/map_previews.dart';

/// Картинка карты (та же, что в «Доступных картах»), без действий по тапу;
/// пока её нет — серый плейсхолдер с иконкой карты.
class LayerDetailsPreview extends ConsumerWidget {
  const LayerDetailsPreview({super.key, required this.source});

  static const double height = 180;

  final MapSource? source;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final source = this.source;
    final file = source == null ? null : ref.watch(mapPreviewProvider(source)).value;
    final asset = source?.thumbnailAsset;
    final ImageProvider? image = file != null ? FileImage(file) : (asset != null ? AssetImage(asset) : null);
    const placeholder = ColoredBox(
      key: Key('details_preview_placeholder'),
      color: Color(0xFFE0E0E0),
      child: Center(child: Icon(Icons.map_outlined, size: 48, color: Color(0xFF9E9E9E))),
    );
    return Container(
      key: const Key('details_preview'),
      height: height,
      width: double.infinity,
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFE0E0E0)))),
      child: image == null
          ? placeholder
          : Image(image: image, fit: BoxFit.cover, errorBuilder: (_, _, _) => placeholder),
    );
  }
}
