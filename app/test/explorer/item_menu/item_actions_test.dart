import 'dart:io';

import 'package:app/explorer/dialogs/landmark_properties_dialog.dart';
import 'package:app/explorer/item_menu/item_actions.dart';
import 'package:app/landmarks/composite/statistics/composite_calculator.dart';
import 'package:app/landmarks/explorer/clipboard/clipboard_entry.dart';
import 'package:app/landmarks/models/landmark_file.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../../landmarks/services/fixture.dart';
import '../landmark_test_helpers.dart';

void main() {
  late ServicesFixture f;

  setUp(() async => f = await ServicesFixture.create());
  tearDown(() => f.root.deleteSync(recursive: true));

  test('rename moves the file and keeps its content; display and clipboard follow', () async {
    final s = f.services;
    final path = await createLdk(s, 'Поход', comment: 'Весна');
    s.displayRegistry.display(path);
    s.explorerController.clipboard.copy([ClipboardEntry(sourcePath: path, type: LandmarkType.ldkFile, originalName: 'Поход')]);
    final result = await ItemActions.rename(s, path, 'Сборы 2027');
    expect(result!.message, 'Файл переименован');
    final renamed = result.path!;
    expect(File(path).existsSync(), isFalse);
    expect(p.basename(renamed), 'сборы_2027.ldk');
    final file = await s.repository.load(renamed);
    expect(file.content.userMetadata.name, 'Сборы 2027');
    expect(file.content.userMetadata.entries[LandmarkMetadata.commentKey], 'Весна');
    expect(s.displayRegistry.isDisplayed(renamed), isTrue);
    expect(s.explorerController.clipboard.isEmpty, isTrue);
    expect(await ItemActions.rename(s, renamed, 'Сборы 2027'), isNull);
  });

  test('properties update changes metadata and bumps the version', () async {
    final s = f.services;
    final path = await createLdk(s, 'Поход', comment: 'Весна');
    final before = (await s.repository.load(path)).content;
    expect(
      await ItemActions.updateProperties(s, path, const LandmarkProperties(name: 'Поход-2', description: 'Три дня')),
      'Свойства обновлены',
    );
    final after = (await s.repository.load(path)).content;
    expect(after.userMetadata.name, 'Поход-2');
    expect(after.userMetadata.entries.containsKey(LandmarkMetadata.commentKey), isFalse);
    expect(after.userMetadata.entries[LandmarkMetadata.descriptionKey], 'Три дня');
    expect(after.userMetadata.version, before.userMetadata.version + 1);
  });

  test('setColor writes the colour', () async {
    final paths = await createOneOfEach(f.services, f.paths.landmarks);
    for (final path in paths.values) {
      expect(await ItemActions.setColor(f.services, path, 0xFF1565C0), 'Цвет изменён');
      expect((await f.services.repository.load(path)).content.userMetadata.colorValue, 0xFF1565C0);
    }
  });

  test('delete removes the file; toggle display flips it', () async {
    final path = await createLdk(f.services, 'Поход');
    expect(ItemActions.toggleDisplay(f.services, path), isTrue);
    expect(ItemActions.toggleDisplay(f.services, path), isFalse);
    expect(await ItemActions.delete(f.services, path), 'Файл удалён');
    expect(File(path).existsSync(), isFalse);
  });

  test('reverseRoute reverses the waypoint order', () async {
    final paths = await createOneOfEach(f.services, f.paths.landmarks);
    final path = paths[LandmarkType.route]!;
    expect(await ItemActions.reverseRoute(f.services, path), 'Порядок точек изменён');
    final route = await f.services.routeService.load(path);
    expect(route.waypoints.map((w) => w.userMetadata.name), ['Финиш', 'Старт']);
  });

  test('toggleClosed opens and closes an area', () async {
    final paths = await createOneOfEach(f.services, f.paths.landmarks);
    final path = paths[LandmarkType.area]!;
    expect(CompositeCalculator.isClosed(await f.services.areaService.load(path)), isTrue);
    expect(await ItemActions.toggleClosed(f.services, path), isFalse);
    expect(CompositeCalculator.isClosed(await f.services.areaService.load(path)), isFalse);
    expect(await ItemActions.toggleClosed(f.services, path), isTrue);
  });

  test('setTarget returns the waypoint location', () async {
    final paths = await createOneOfEach(f.services, f.paths.landmarks);
    final at = await ItemActions.setTarget(f.services, paths[LandmarkType.waypoint]!);
    expect((at.latitude, at.longitude), (42.87, 74.6));
  });

  test('stubs answer «пока недоступна»', () {
    expect(ItemActions.stub('Движение по треку', '/x/a.trk'), ItemActions.notYet);
  });

  test('share without a platform layer explains itself', () async {
    final path = await createLdk(f.services, 'Поход');
    expect(await ItemActions.share(f.services, path), 'Отправка файлов на этом устройстве недоступна');
  });
}
