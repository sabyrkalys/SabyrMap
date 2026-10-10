import 'package:app/app/landmark_services_provider.dart';
import 'package:app/landmarks/drafts/marker_draft.dart';
import 'package:app/landmarks/models/landmark_type.dart';
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
