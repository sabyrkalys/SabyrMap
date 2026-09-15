import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../icons/waypoint_icon_assignments_controller.dart';
import 'waypoint_actions.dart';
import 'waypoint_color.dart';
import 'waypoint_types.dart';
import 'waypoints_controller.dart';

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

  @override
  Widget build(BuildContext context) {
    final waypoints = ref.watch(waypointsControllerProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Метки')),
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
