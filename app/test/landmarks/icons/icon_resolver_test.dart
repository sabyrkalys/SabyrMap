import 'dart:io';

import 'package:app/landmarks/icons/icon_info.dart';
import 'package:app/landmarks/icons/icon_registry.dart';
import 'package:app/landmarks/icons/icon_resolver.dart';
import 'package:app/storage/storage_paths.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory root;
  late StoragePaths paths;
  late IconResolver resolver;

  setUp(() {
    root = Directory.systemTemp.createTempSync('icons_');
    paths = StoragePaths.forRoot(root.path);
    resolver = IconResolver(paths);
  });
  tearDown(() => root.deleteSync(recursive: true));

  File put(String relative, {int bytes = 10}) =>
      File(p.join(paths.icons, relative))
        ..createSync(recursive: true)
        ..writeAsBytesSync(List.filled(bytes, 0));

  test('a missing icons folder gives an empty list', () async {
    expect(await resolver.scan(), isEmpty);
  });

  test('an empty icons folder gives an empty list', () async {
    Directory(paths.icons).createSync(recursive: true);
    expect(await resolver.scan(), isEmpty);
  });

  test('png and svg are found, other files, big files and links are not', () async {
    put('tourism/tent.png');
    put('flag.svg');
    put('readme.txt');
    put('tourism/huge.png', bytes: IconResolver.maxFileBytes + 1);
    put('tourism/limit.png', bytes: IconResolver.maxFileBytes);
    Link(p.join(paths.icons, 'linked.png')).createSync(p.join(paths.icons, 'flag.svg'));
    Link(p.join(paths.icons, 'linked_dir')).createSync(p.join(paths.icons, 'tourism'));

    final icons = await resolver.scan();
    expect(icons.map((i) => i.id), ['flag', 'tourism/limit', 'tourism/tent']);
    expect(
      icons.last,
      IconInfo(
        id: 'tourism/tent',
        name: 'tent',
        category: 'tourism',
        path: p.join(paths.icons, 'tourism', 'tent.png'),
        extension: 'png',
      ),
    );
    expect(icons.first.category, isNull);
  });

  test('folders deeper than three levels are skipped', () async {
    put('a/b/c/ok.png');
    put('a/b/c/d/deep.png');
    expect((await resolver.scan()).map((i) => i.id), ['a/b/c/ok']);
  });

  test('svg wins over png for the same id', () async {
    put('x/pin.png');
    put('x/pin.svg');
    final icons = await resolver.scan();
    expect(icons.single.extension, 'svg');
    expect(await resolver.resolve('x/pin'), p.join(paths.icons, 'x', 'pin.svg'));
  });

  test('exists and resolve', () async {
    put('tourism/tent.png');
    put('big.png', bytes: IconResolver.maxFileBytes + 1);
    expect(await resolver.exists('tourism/tent'), isTrue);
    expect(await resolver.resolve('tourism/tent'), p.join(paths.icons, 'tourism', 'tent.png'));
    expect(await resolver.exists('tourism/none'), isFalse);
    expect(await resolver.exists('big'), isFalse);
    expect(await resolver.exists('../icons/tourism/tent'), isFalse);
    expect(await resolver.exists(''), isFalse);
  });

  test('registry: all, categories, byCategory, byId', () async {
    put('tourism/tent.png');
    put('tourism/cabin.svg');
    put('military/post.png');
    put('flag.svg');
    final registry = IconRegistry(resolver);
    expect(registry.all, isEmpty);
    await registry.refresh();

    expect(registry.all.map((i) => i.id), ['flag', 'military/post', 'tourism/cabin', 'tourism/tent']);
    expect(registry.categories, ['military', 'tourism']);
    expect(registry.byCategory('tourism').map((i) => i.name), ['cabin', 'tent']);
    expect(registry.byId('tourism/tent')?.path, p.join(paths.icons, 'tourism', 'tent.png'));
    expect(registry.byId('nope'), isNull);
  });
}
