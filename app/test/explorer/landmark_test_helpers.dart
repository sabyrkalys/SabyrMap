import 'package:app/app/landmark_services_provider.dart';
import 'package:app/landmarks/drafts/marker_draft.dart';
import 'package:app/landmarks/models/landmark_file.dart';
import 'package:app/landmarks/services/landmark_services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Создаёт файл меток через сервис создания и возвращает путь.
Future<String> createLdk(LandmarkServices s, String name, {String? folder, String? comment}) =>
    s.creation.create(
      MarkerDraft(
        type: LandmarkType.ldkFile,
        name: name,
        comment: comment,
        longitude: 0,
        latitude: 0,
        targetFolder: folder ?? s.paths.landmarks,
      ),
    );

/// Путевая точка в [folder] (для экспорта: у файла меток пока нет объектов).
Future<String> createWaypoint(LandmarkServices s, String name, String folder) => s.creation.create(
  MarkerDraft(type: LandmarkType.waypoint, name: name, longitude: 74.6, latitude: 42.87, targetFolder: folder),
);

/// Экран с одной кнопкой `host_button`, по которой вызывается [onPressed].
Widget hostApp(LandmarkServices s, void Function(BuildContext context) onPressed) => ProviderScope(
  overrides: [landmarkServicesProvider.overrideWithValue(s)],
  child: MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (context) => Center(
          child: TextButton(key: const Key('host_button'), onPressed: () => onPressed(context), child: const Text('go')),
        ),
      ),
    ),
  ),
);

/// Даёт операциям с диском идти в настоящем времени, пока не появится
/// [finder] и не пропадут индикаторы загрузки (не дольше ~3 с), затем
/// дорисовывает анимации.
Future<void> pumpUntil(WidgetTester tester, Finder finder) async {
  bool loading() => find.byType(CircularProgressIndicator).evaluate().isNotEmpty;
  for (var i = 0; i < 100 && (finder.evaluate().isEmpty || loading()); i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
    await tester.pump();
  }
  await tester.pumpAndSettle();
}

LandmarkLocation loc(double lat, double lon, {double? elevation}) => LandmarkLocation(
  latitude: lat,
  longitude: lon,
  values: [
    if (elevation != null) LocationValue(type: LocationValueType.elevation, value: (elevation * 1000).round()),
  ],
);

WaypointObject wpt(String name, double lat, double lon) =>
    WaypointObject(location: loc(lat, lon), userMetadata: LandmarkMetadata(entries: {LandmarkMetadata.nameKey: name}));

LandmarkMetadata named(String name) => LandmarkMetadata(entries: {LandmarkMetadata.nameKey: name});

/// Сохраняет [object] в [folder]; у составных объектов пишется статистика.
Future<String> saveObject(LandmarkServices s, LandmarkObject object, String folder) async {
  final path = await s.repository.save(LandmarkFile.of(object), directory: folder);
  switch (object) {
    case final SetObject o:
      await s.setService.save(path, o);
    case final RouteObject o:
      await s.routeService.save(path, o);
    case final TrackObject o:
      await s.trackService.save(path, o);
    case final AreaObject o:
      await s.areaService.save(path, o);
  }
  return path;
}

/// По одному объекту каждого типа в [folder]; пути по типам.
Future<Map<LandmarkType, String>> createOneOfEach(LandmarkServices s, String folder) async => {
  LandmarkType.waypoint: await saveObject(s, wpt('Перевал', 42.87, 74.6), folder),
  LandmarkType.set: await saveObject(
    s,
    SetObject(userMetadata: named('Родники'), waypoints: [wpt('Родник 1', 42.8, 74.5), wpt('Родник 2', 42.81, 74.52)]),
    folder,
  ),
  LandmarkType.route: await saveObject(
    s,
    RouteObject(userMetadata: named('Маршрут'), waypoints: [wpt('Старт', 42.8, 74.5), wpt('Финиш', 42.82, 74.53)]),
    folder,
  ),
  LandmarkType.track: await saveObject(
    s,
    TrackObject(
      userMetadata: named('Подъём'),
      waypoints: [wpt('Привал', 42.805, 74.505)],
      segments: [
        TrackSegment(locations: [loc(42.8, 74.5, elevation: 1500), loc(42.81, 74.51, elevation: 1700)]),
        TrackSegment(locations: [loc(42.81, 74.51, elevation: 1700), loc(42.82, 74.52, elevation: 1650)]),
      ],
    ),
    folder,
  ),
  LandmarkType.area: await saveObject(
    s,
    AreaObject(
      userMetadata: named('Луг'),
      polygons: [
        AreaPolygon(outline: [loc(42.8, 74.5), loc(42.8, 74.51), loc(42.81, 74.51), loc(42.81, 74.5)]),
      ],
    ),
    folder,
  ),
  LandmarkType.ldkFile: await createLdk(s, 'Поход', folder: folder),
};
