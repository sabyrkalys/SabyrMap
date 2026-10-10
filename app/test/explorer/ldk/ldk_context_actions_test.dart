import 'dart:io';

import 'package:app/explorer/ldk/ldk_context_actions.dart';
import 'package:app/explorer/ldk/ldk_properties_dialog.dart';
import 'package:app/landmarks/models/landmark_file.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../../landmarks/services/fixture.dart';
import 'ldk_test_helpers.dart';

void main() {
  late ServicesFixture f;

  setUp(() async => f = await ServicesFixture.create());
  tearDown(() => f.root.deleteSync(recursive: true));

  test('rename moves the file and keeps its content; display and clipboard follow', () async {
    final s = f.services;
    final path = await createLdk(s, 'Поход', comment: 'Весна');
    s.displayRegistry.display(path);
    LdkContextActions.copy(s, path, 'Поход');
    final result = await LdkContextActions.rename(s, path, 'Сборы 2027');

    expect(result!.message, 'Файл переименован');
    final renamed = result.path!;
    expect(File(path).existsSync(), isFalse);
    expect(p.basename(renamed), 'сборы_2027.ldk');
    final file = await s.repository.load(renamed);
    expect(file.type, LandmarkType.ldkFile);
    expect(file.content.userMetadata.name, 'Сборы 2027');
    expect(file.content.userMetadata.entries[LandmarkMetadata.commentKey], 'Весна');
    expect(s.displayRegistry.isDisplayed(renamed), isTrue);
    expect(s.displayRegistry.isDisplayed(path), isFalse);
    expect(s.explorerController.clipboard.isEmpty, isTrue);
  });

  test('rename to the same name changes nothing', () async {
    final path = await createLdk(f.services, 'Поход');
    expect(await LdkContextActions.rename(f.services, path, ' Поход '), isNull);
    expect(File(path).existsSync(), isTrue);
  });

  test('rename to a taken name gets a suffix', () async {
    final s = f.services;
    final first = await createLdk(s, 'А');
    final second = await createLdk(s, 'Б');
    final a = await LdkContextActions.rename(s, first, 'Один');
    final b = await LdkContextActions.rename(s, second, 'Один');
    expect(p.basename(a!.path!), 'один.ldk');
    expect(p.basename(b!.path!), 'один_1.ldk');
  });

  test('delete removes the file', () async {
    final path = await createLdk(f.services, 'Поход');
    expect(await LdkContextActions.delete(f.services, path), 'Файл удалён');
    expect(File(path).existsSync(), isFalse);
  });

  test('toggle display adds and removes the path', () async {
    final s = f.services;
    final path = await createLdk(s, 'Поход');
    expect(LdkContextActions.toggleDisplay(s, path), isTrue);
    expect(s.displayRegistry.isDisplayed(path), isTrue);
    expect(LdkContextActions.toggleDisplay(s, path), isFalse);
    expect(s.displayRegistry.isDisplayed(path), isFalse);
  });

  test('properties update changes metadata and bumps the version', () async {
    final s = f.services;
    final path = await createLdk(s, 'Поход', comment: 'Весна');
    final before = (await s.repository.load(path)).content;

    final text = await LdkContextActions.updateProperties(
      s,
      path,
      const LdkProperties(name: 'Поход-2', comment: '', description: 'Три дня'),
    );
    expect(text, 'Свойства обновлены');
    final after = (await s.repository.load(path)).content;
    final m = after.userMetadata;
    expect(m.name, 'Поход-2');
    expect(m.entries.containsKey(LandmarkMetadata.commentKey), isFalse);
    expect(m.entries[LandmarkMetadata.descriptionKey], 'Три дня');
    expect(m.version, before.userMetadata.version + 1);
    expect(after.technicalMetadata.version, before.technicalMetadata.version + 1);
  });

  test('copy and cut put the file into the clipboard as ldkFile', () async {
    final s = f.services;
    final path = await createLdk(s, 'Поход');
    expect(LdkContextActions.copy(s, path, 'Поход'), 'Скопировано: Поход');
    final entry = s.explorerController.clipboard.entries.single;
    expect((entry.sourcePath, entry.type, entry.isFolder), (path, LandmarkType.ldkFile, false));
    expect(LdkContextActions.cut(s, path, 'Поход'), 'Вырезано: Поход');
    expect(s.explorerController.clipboard.isCut, isTrue);
  });

  test('select activates selection with the file', () async {
    final s = f.services;
    final path = await createLdk(s, 'Поход');
    LdkContextActions.select(s, path);
    expect(s.explorerController.selection.state.isActive, isTrue);
    expect(s.explorerController.selection.contains(path), isTrue);
  });

  test('share without a platform layer explains itself', () async {
    final path = await createLdk(f.services, 'Поход');
    expect(await LdkContextActions.share(f.services, path), 'Отправка файлов на этом устройстве недоступна');
  });

  test('the folder service reports size and modification time', () async {
    final path = await createLdk(f.services, 'Поход');
    expect(await f.services.folders.fileSize(path), File(path).lengthSync());
    expect(await f.services.folders.fileModifiedMs(path), File(path).lastModifiedSync().millisecondsSinceEpoch);
    await f.services.folders.deleteFile(path);
    await f.services.folders.deleteFile(path);
    expect(File(path).existsSync(), isFalse);
  });
}
