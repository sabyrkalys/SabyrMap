import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:maplibre_gl/maplibre_gl.dart' show LatLng;

import '../app/landmark_services_provider.dart';
import '../icons/icon_library_scanner.dart';
import '../map/map_crosshair.dart';
import 'waypoint_dialog/marker_group.dart';
import 'waypoint_dialog/waypoint_data.dart';
import 'waypoint_dialog/waypoint_dialog.dart';
import 'waypoint_edits.dart';

/// [folder] — папка проводника, куда кладётся точка с группой по
/// умолчанию.
///
/// Opens the «Путевая точка» dialog and creates the waypoint at the map's
/// crosshair, or at [at] (the «Задать цель» target), or at the coordinates
/// typed in the dialog. Shared by the crosshair menu, the «Новая метка» sheet and the МЕТКИ panel.
///
/// The panel can be closed while the request is in flight, which unmounts
/// [context] and disposes [ref]; the container and messenger are captured
/// up front so the result is still applied and reported.
Future<void> createWaypointAtCrosshair(
  BuildContext context,
  WidgetRef ref, {
  IconLibraryScanner? iconScanner,
  LatLng? at,
  String? folder,
}) async {
  final container = ProviderScope.containerOf(context, listen: false);
  final messenger = ScaffoldMessenger.of(context);
  final coordinates = at ?? ref.read(mapCrosshairProvider);
  if (coordinates == null) {
    messenger.showSnackBar(const SnackBar(content: Text('Карта ещё не готова')));
    return;
  }
  final data = await showWaypointDialog(
    context,
    iconScanner: iconScanner,
    pointLabel: at == null ? 'Координаты центра экрана' : 'Координаты цели',
    fixedPoint: at,
  );
  if (data == null) return;
  // The crosshair as it is now: the map may have moved while the dialog was open.
  final point = data.point ?? at ?? container.read(mapCrosshairProvider) ?? coordinates;
  await saveWaypoint(container, messenger, data, point, folder: folder);
}

/// Creates [data] at [at]. An empty name becomes the next «Путевая точка N».
Future<void> saveWaypoint(
  ProviderContainer container,
  ScaffoldMessengerState messenger,
  WaypointData data,
  LatLng at, {
  String? folder,
}) async {
  final edits = container.read(waypointEditsProvider);
  final name = data.name.trim().isNotEmpty ? data.name.trim() : nextWaypointName(edits.names);
  try {
    await edits.create(
      name: name,
      type: data.type,
      note: data.note,
      color: data.colorHex,
      lat: at.latitude,
      lng: at.longitude,
      iconFileName: data.iconId,
      // Decision: из проводника точка ложится в открытую там папку, если
      // в диалоге осталась группа по умолчанию.
      folder: folder != null && data.groupId == WaypointData.unsortedGroupId
          ? folder
          : folderFor(container.read(markerGroupFoldersProvider), data.groupId),
      extra: {
        if (data.comment?.trim().isNotEmpty ?? false) 'comment': data.comment!.trim(),
        'icon': ?data.markerIconId,
      },
    );
  } on WaypointException catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(e.message)));
  }
}
