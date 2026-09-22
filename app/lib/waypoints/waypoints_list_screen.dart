import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../icons/waypoint_icon_assignments_controller.dart';
import '../mediafile/mediafile_folder_screen.dart';
import '../mediafile/mediafile_subfolders.dart';
import '../tracks/tracks_list_screen.dart';
import '../tracks/tracks_visibility_controller.dart';
import 'waypoint_actions.dart';
import 'waypoint_color.dart';
import 'waypoint_types.dart';
import 'waypoints_controller.dart';
import '../widgets/app_icon.dart';
import '../app_icons.dart';

class WaypointsListScreen extends ConsumerStatefulWidget {
  const WaypointsListScreen({super.key});

  @override
  ConsumerState<WaypointsListScreen> createState() => _WaypointsListScreenState();
}

class _WaypointsListScreenState extends ConsumerState<WaypointsListScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(waypointsControllerProvider.notifier).loadWaypoints());
    Future.microtask(() => ref.read(waypointIconAssignmentsControllerProvider.notifier).load());
  }

  void _openFiles() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const MediaFileFolderScreen(
          title: 'Файлы меток',
          subfolder: kCustomTypesSubfolder,
          allowedExtensions: ['png', 'jpg', 'jpeg', 'svg'],
        ),
      ),
    );
  }

  void _openTracksList() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const TracksListScreen()),
    );
  }

  void _onLayersButtonPressed() {
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => Consumer(
        builder: (sheetContext, sheetRef, _) => Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Показывать треки'),
              Switch(
                key: const Key('tracks_visibility_switch'),
                value: sheetRef.watch(tracksVisibilityControllerProvider),
                onChanged: (value) => sheetRef.read(tracksVisibilityControllerProvider.notifier).setVisible(value),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final waypoints = ref.watch(waypointsControllerProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Метки'),
        actions: [
          IconButton(
            key: const Key('waypoint_files_button'),
            icon: const AppIcon(AppIcons.folder),
            onPressed: _openFiles,
          ),
          IconButton(
            key: const Key('layers_button'),
            icon: const AppIcon(AppIcons.layers),
            onPressed: _onLayersButtonPressed,
          ),
          IconButton(
            key: const Key('tracks_list_button'),
            icon: const AppIcon(AppIcons.list),
            onPressed: _openTracksList,
          ),
        ],
      ),
      body: waypoints.isEmpty
          ? const Center(child: Text('Пока нет меток'))
          : ListView.builder(
              itemCount: waypoints.length,
              itemBuilder: (context, index) {
                final waypoint = waypoints[index];
                final color = colorFromHex(
                  waypoint.color ?? waypointTypeColors[waypoint.type] ?? waypointTypeColors[defaultWaypointType]!,
                );
                return Card(
                  margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  child: ListTile(
                    key: Key('waypoint_card_${waypoint.id}'),
                    leading: CircleAvatar(backgroundColor: color, radius: 12),
                    title: Text(waypoint.name),
                    subtitle: Text(waypointTypeLabels[waypoint.type] ?? waypoint.type),
                    onTap: () => showWaypointDetails(context, ref, waypoint),
                  ),
                );
              },
            ),
    );
  }
}
