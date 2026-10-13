import 'package:flutter/material.dart';

import '../available_maps_screen.dart';
import 'favorite_set_save_dialog.dart';

/// Заголовок «Карты на экране»: к доступным картам, сохранить в избранное,
/// закрыть.
class OnScreenLayersHeader extends StatelessWidget {
  const OnScreenLayersHeader({super.key});

  static const Color _ink = Color(0xFF333333);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(
          children: [
            const Icon(Icons.layers, size: 24, color: _ink),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Карты на экране',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500, color: Color(0xFF212121)),
              ),
            ),
            IconButton(
              key: const Key('layers_header_maps'),
              tooltip: 'К доступным картам',
              icon: const Icon(Icons.map_outlined, size: 22, color: _ink),
              onPressed: () {
                final navigator = Navigator.of(context);
                navigator.pop();
                navigator.push(MaterialPageRoute<void>(builder: (_) => const AvailableMapsScreen()));
              },
            ),
            IconButton(
              key: const Key('layers_header_save'),
              tooltip: 'Сохранить в избранное',
              icon: const Icon(Icons.bookmark_add_outlined, size: 22, color: _ink),
              onPressed: () => FavoriteSetSaveDialog.show(context),
            ),
            IconButton(
              key: const Key('layers_header_close'),
              icon: const Icon(Icons.close, size: 22, color: _ink),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        ),
      );
}
