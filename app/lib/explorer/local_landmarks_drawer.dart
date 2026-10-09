import 'package:app/landmarks/explorer/places/place_root.dart';
import 'package:flutter/material.dart';

import '../map/screens/available_maps/available_maps_models.dart';
import '../map/screens/available_maps/side_drawer.dart';
import '../map/screens/available_maps/storage_bar.dart';
import 'online_marks_placeholder.dart';

/// Боковая панель «Локальных меток» в стиле «Доступных карт»: выезжает
/// слева над экраном, закрывается тапом по затемнению или свайпом влево.
class LocalLandmarksDrawer extends StatelessWidget {
  const LocalLandmarksDrawer({
    super.key,
    required this.isOpen,
    required this.places,
    required this.currentPlace,
    required this.deviceUsage,
    required this.onPlace,
    required this.onClose,
  });

  final bool isOpen;
  final List<PlaceRoot> places;
  final PlaceRoot? currentPlace;

  /// Память устройства; null — неизвестна.
  final StorageUsage? deviceUsage;
  final ValueChanged<PlaceRoot> onPlace;
  final VoidCallback onClose;

  static const _duration = Duration(milliseconds: 220);

  /// «Память устройства (454 ГБ)» для места устройства.
  static String titleOf(PlaceRoot place, StorageUsage? usage) {
    if (place.kind != PlaceRootKind.deviceFolder || usage == null) return place.title;
    return '${place.title} (${(usage.totalBytes / (1 << 30)).round()} ГБ)';
  }

  static IconData iconOf(PlaceRootKind kind) => switch (kind) {
    PlaceRootKind.landmarks => Icons.folder_special_outlined,
    PlaceRootKind.downloads => Icons.download_outlined,
    PlaceRootKind.deviceFolder => Icons.smartphone_outlined,
    PlaceRootKind.custom => Icons.folder_outlined,
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final width = (MediaQuery.sizeOf(context).width * 0.8).clamp(0.0, 320.0);
    return Stack(
      children: [
        IgnorePointer(
          ignoring: !isOpen,
          child: AnimatedOpacity(
            opacity: isOpen ? 1 : 0,
            duration: _duration,
            child: GestureDetector(
              key: const Key('explorer_drawer_scrim'),
              onTap: onClose,
              child: const ColoredBox(color: Color(0x66000000), child: SizedBox.expand()),
            ),
          ),
        ),
        AnimatedSlide(
          offset: isOpen ? Offset.zero : const Offset(-1, 0),
          duration: _duration,
          curve: Curves.easeOut,
          child: ExcludeSemantics(
            excluding: !isOpen,
            child: GestureDetector(
              onHorizontalDragEnd: (details) {
                if ((details.primaryVelocity ?? 0) < -200) onClose();
              },
              child: Material(
                key: const Key('local_landmarks_drawer'),
                elevation: 8,
                color: theme.colorScheme.surface,
                child: SizedBox(
                  width: width,
                  height: double.infinity,
                  child: ListView(
                    padding: EdgeInsets.zero,
                    children: [
                      const SideDrawerHeader('ЛОКАЛЬНЫЕ МЕТКИ'),
                      for (final place in places) ...[
                        ListTile(
                          key: Key('drawer_place_${place.id}'),
                          leading: Icon(iconOf(place.kind)),
                          title: Text(titleOf(place, deviceUsage)),
                          subtitle: Text(place.path, maxLines: 1, overflow: TextOverflow.ellipsis),
                          selected: place.id == currentPlace?.id,
                          onTap: () => onPlace(place),
                        ),
                        if (place.kind == PlaceRootKind.deviceFolder)
                          StorageBar(key: const Key('drawer_device_storage'), usage: deviceUsage),
                      ],
                      const Divider(),
                      SideDrawerHeader(
                        'ОНЛАЙН-МЕТКИ',
                        trailing: IconButton(
                          key: const Key('online_marks_settings'),
                          icon: const Icon(Icons.settings_outlined),
                          onPressed: () => OnlineMarksPlaceholder.show(context),
                        ),
                      ),
                      ListTile(
                        key: const Key('online_my_marks'),
                        leading: const Icon(Icons.cloud_outlined),
                        title: const Text('Мои метки'),
                        onTap: () => OnlineMarksPlaceholder.show(context),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
