import 'package:app/landmarks/explorer/places/place_root.dart';
import 'package:flutter/material.dart';

import '../map/screens/available_maps/available_maps_models.dart';
import 'explorer_style.dart';
import 'online_marks_placeholder.dart';
import 'storage_path_block.dart';

/// Боковое меню «Локальные метки»: место и его память, разделы,
/// «Онлайн-метки».
class LocalLandmarksDrawer extends StatelessWidget {
  const LocalLandmarksDrawer({
    super.key,
    required this.places,
    required this.currentPlace,
    required this.deviceUsage,
    required this.onPlace,
  });

  final List<PlaceRoot> places;
  final PlaceRoot? currentPlace;

  /// Память устройства; null — неизвестна.
  final StorageUsage? deviceUsage;
  final ValueChanged<PlaceRoot> onPlace;

  /// «Память устройства (454 ГБ)» для места устройства.
  static String titleOf(PlaceRoot place, StorageUsage? usage) {
    if (place.kind != PlaceRootKind.deviceFolder || usage == null) return place.title;
    return '${place.title} (${(usage.totalBytes / (1 << 30)).round()} ГБ)';
  }

  @override
  Widget build(BuildContext context) {
    final current = currentPlace;
    return Drawer(
      key: const Key('local_landmarks_drawer'),
      backgroundColor: ExplorerStyle.drawerBackground,
      elevation: 0,
      shape: const RoundedRectangleBorder(),
      child: SafeArea(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Text('ЛОКАЛЬНЫЕ МЕТКИ', style: ExplorerStyle.sectionHeader),
            ),
            if (current != null)
              StoragePathBlock(
                title: titleOf(current, deviceUsage),
                path: current.path,
                usage: current.kind == PlaceRootKind.deviceFolder ? deviceUsage : null,
              ),
            for (final place in places)
              ListTile(
                key: Key('drawer_place_${place.id}'),
                leading: SizedBox(
                  width: 12,
                  child: place.id == current?.id
                      ? const Icon(Icons.circle, size: 8, color: ExplorerStyle.accent)
                      : null,
                ),
                minLeadingWidth: 12,
                title: Text(
                  titleOf(place, deviceUsage),
                  style: ExplorerStyle.rowTitle.copyWith(
                    fontWeight: place.id == current?.id ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
                subtitle: Text(place.path, style: ExplorerStyle.subtitle),
                onTap: () => onPlace(place),
              ),
            ExplorerStyle.divider1,
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 4, 0),
              child: Row(
                children: [
                  const Expanded(child: Text('ОНЛАЙН-МЕТКИ', style: ExplorerStyle.sectionHeader)),
                  IconButton(
                    key: const Key('online_marks_settings'),
                    icon: const Icon(Icons.settings, color: ExplorerStyle.icon),
                    onPressed: () => OnlineMarksPlaceholder.show(context),
                  ),
                ],
              ),
            ),
            ListTile(
              key: const Key('online_my_marks'),
              leading: const SizedBox(width: 12),
              minLeadingWidth: 12,
              title: const Text('Мои метки', style: ExplorerStyle.rowTitle),
              onTap: () => OnlineMarksPlaceholder.show(context),
            ),
          ],
        ),
      ),
    );
  }
}
