import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:app/explorer/export/landmark_export_flow.dart';
import 'package:app/landmarks/import_export/export/export_options.dart';
import 'package:app/landmarks/import_export/export/export_options_schema.dart';
import 'package:app/landmarks/import_export/export/export_result.dart';
import 'package:app/landmarks/import_export/registry/export_adapter.dart';
import 'package:app/landmarks/import_export/registry/format_capability.dart';
import 'package:app/landmarks/import_export/registry/format_descriptor.dart';
import 'package:app/landmarks/import_export/registry/import_adapter.dart';
import 'package:app/landmarks/models/landmark_object.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../../landmarks/services/fixture.dart';
import '../landmark_test_helpers.dart';

/// Простой текстовый формат без параметров: имена объектов по строкам.
class _NamesAdapter extends ExportAdapter {
  const _NamesAdapter();

  @override
  String get formatId => 'names';

  @override
  ExportOptionsSchema get optionsSchema => const ExportOptionsSchema();

  @override
  Future<Uint8List> serialize(List<LandmarkObject> objects, ExportOptions options, {WarningSink? onWarning}) async =>
      utf8.encode(objects.map((o) => o.userMetadata.name).join('\n'));

  @override
  String extensionFor(ExportOptions options) => 'txt';
}

void main() {
  late ServicesFixture f;
  late String path;
  ExportResult? result;
  var finished = false;

  /// Запускает поток для файла, созданного [make].
  Future<void> start(WidgetTester tester, Future<String> Function() make) async {
    result = null;
    finished = false;
    await tester.runAsync(() async {
      f = await ServicesFixture.create();
      path = await make();
    });
    await tester.pumpWidget(
      hostApp(f.services, (context) async {
        result = await LandmarkExportFlow.start(context, path);
        finished = true;
      }),
    );
    await tester.tap(find.byKey(const Key('host_button')));
    await pumpUntil(tester, find.byKey(const Key('ldk_export_formats')));
  }

  Future<void> dispose(WidgetTester tester) => tester.runAsync(() async => f.root.deleteSync(recursive: true));

  testWidgets('step 1 lists the exporters of the format registry', (tester) async {
    await start(tester, () => createLdk(f.services, 'Поход'));
    expect(find.text('Экспортировать как...'), findsOneWidget);
    final exporters = f.services.formatRegistry.exporters;
    expect(exporters, isNotEmpty);
    for (final format in exporters) {
      expect(find.byKey(Key('ldk_export_format_${format.id}')), findsOneWidget, reason: format.id);
      expect(find.text(format.extensions.join(', ')), findsOneWidget);
    }
    await tester.tap(find.byKey(const Key('ldk_export_cancel')));
    await tester.pumpAndSettle();
    expect(finished, isTrue);
    expect(result, isNull);
    await dispose(tester);
  });

  testWidgets('an empty .ldk → «Формат не поддерживает содержимое файла»', (tester) async {
    await start(tester, () => createLdk(f.services, 'Поход'));
    await tester.tap(find.byKey(const Key('ldk_export_format_gpx')));
    await pumpUntil(tester, find.text(LandmarkExportFlow.unsupported));
    expect(find.text(LandmarkExportFlow.unsupported), findsOneWidget);
    expect(find.byKey(const Key('ldk_export_options')), findsNothing);
    expect(result, isNull);
    await dispose(tester);
  });

  testWidgets('steps 2–4: options, folder picker, export, result', (tester) async {
    await start(tester, () => createWaypoint(f.services, 'Перевал', f.paths.importDefault));

    await tester.tap(find.byKey(const Key('ldk_export_format_gpx')));
    await pumpUntil(tester, find.byKey(const Key('ldk_export_options')));
    expect(find.byKey(const Key('ldk_export_option_includeWaypoints')), findsOneWidget);
    expect(find.byKey(const Key('ldk_export_option_includeSegments')), findsOneWidget);
    await tester.tap(find.byKey(const Key('ldk_export_option_includeSegments')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('ldk_export_options_next')));
    await pumpUntil(tester, find.byKey(const Key('folder_picker_dialog')));

    // Открыта папка файла; поднимаемся в «Мои метки» и создаём папку.
    expect(find.text('Мои метки / Несортированные метки'), findsOneWidget);
    await tester.tap(find.byKey(const Key('folder_picker_up')));
    await pumpUntil(tester, find.byKey(const Key('folder_picker_Несортированные метки')));
    await tester.tap(find.byKey(const Key('folder_picker_create')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('folder_picker_new_name')), 'Экспорт');
    await tester.runAsync(() => tester.tap(find.byKey(const Key('folder_picker_new_ok'))));
    await pumpUntil(tester, find.text('Мои метки / Экспорт'));
    await tester.tap(find.byKey(const Key('folder_picker_choose')));
    await pumpUntil(tester, find.byKey(const Key('ldk_export_result')));

    final target = p.join(f.paths.landmarks, 'Экспорт');
    for (final key in ['ldk_export_share', 'ldk_export_open', 'ldk_export_ok']) {
      expect(find.byKey(Key(key)), findsOneWidget);
    }
    final shown = tester.widget<SelectableText>(
      find.descendant(of: find.byKey(const Key('ldk_export_result')), matching: find.byType(SelectableText)),
    );
    await tester.tap(find.byKey(const Key('ldk_export_ok')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('ldk_export_result')), findsNothing);
    expect(result!.success, isTrue);
    expect(shown.data, result!.filePath);
    expect(p.dirname(result!.filePath!), target);
    expect(p.extension(result!.filePath!), '.gpx');
    final gpx = await tester.runAsync(() => File(result!.filePath!).readAsString());
    expect(gpx, contains('Перевал'));
    await dispose(tester);
  });

  testWidgets('a format without options skips step 2', (tester) async {
    await start(tester, () async {
      f.services.formatRegistry.register(
        FormatDescriptor(
          id: 'names',
          displayName: 'Имена',
          extensions: const ['txt'],
          capabilities: const {FormatCapability.exportWaypoint},
          exportAdapter: const _NamesAdapter(),
        ),
      );
      return createWaypoint(f.services, 'Перевал', f.paths.landmarks);
    });
    await tester.ensureVisible(find.byKey(const Key('ldk_export_format_names')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('ldk_export_format_names')));
    await pumpUntil(tester, find.byKey(const Key('folder_picker_dialog')));
    expect(find.byKey(const Key('ldk_export_options')), findsNothing);
    await tester.tap(find.byKey(const Key('folder_picker_cancel')));
    await tester.pumpAndSettle();
    expect(finished, isTrue);
    expect(result, isNull);
    await dispose(tester);
  });
}
