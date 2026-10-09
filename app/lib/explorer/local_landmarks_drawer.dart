import 'package:app/landmarks/explorer/places/place_root.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

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
    this.bookmarks = const [],
    this.onBookmark,
    this.onRemoveBookmark,
  });

  /// Папки из закладок (существующие).
  final List<String> bookmarks;
  final ValueChanged<String>? onBookmark;
  final ValueChanged<String>? onRemoveBookmark;

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

  /// Долгое нажатие на закладку: шторка с предложением удалить её.
  Future<void> _askRemove(BuildContext context, String path) async {
    final remove = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        key: const Key('bookmark_menu'),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Text(
                    p.basename(path),
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w500, color: Color(0xFF212121)),
                  ),
                ),
                InkWell(
                  key: const Key('bookmark_menu_remove'),
                  onTap: () => Navigator.pop(context, true),
                  borderRadius: BorderRadius.circular(8),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 32,
                          child: Icon(Icons.bookmark_remove_outlined, size: 24, color: Color(0xFFD32F2F)),
                        ),
                        SizedBox(width: 16),
                        Text('Удалить закладку', style: TextStyle(fontSize: 16, color: Color(0xFF212121))),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      key: const Key('bookmark_menu_cancel'),
                      onPressed: () => Navigator.pop(context, false),
                      style: TextButton.styleFrom(foregroundColor: const Color(0xFF00A38E)),
                      child: const Text('ОТМЕНА', style: TextStyle(fontWeight: FontWeight.w600, letterSpacing: 0.5)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (remove ?? false) onRemoveBookmark?.call(path);
  }

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
                      if (bookmarks.isNotEmpty) ...[
                        const SideDrawerHeader('ЗАКЛАДКИ'),
                        for (final path in bookmarks)
                          ListTile(
                            key: Key('drawer_bookmark_${p.basename(path)}'),
                            leading: const Icon(Icons.bookmark_outline),
                            title: Text(p.basename(path)),
                            subtitle: Text(path, maxLines: 1, overflow: TextOverflow.ellipsis),
                            onTap: () => onBookmark?.call(path),
                            onLongPress: () => _askRemove(context, path),
                          ),
                        const Divider(),
                      ],
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
