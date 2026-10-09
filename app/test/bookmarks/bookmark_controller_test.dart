import 'package:app/bookmarks/bookmark.dart';
import 'package:app/bookmarks/bookmark_controller.dart';
import 'package:app/bookmarks/bookmark_store.dart';
import 'package:app/landmarks/settings/app_settings.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late BookmarkStore store;
  late BookmarkController c;
  late int notified;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    store = BookmarkStore(AppSettings(await SharedPreferences.getInstance()));
    c = BookmarkController(store, clock: () => DateTime.fromMillisecondsSinceEpoch(1000));
    await c.load();
    notified = 0;
    c.addListener(() => notified++);
  });

  test('add puts the bookmark in and saves it', () async {
    await c.add(const Bookmark(id: 'x', name: 'X', path: '/l/x', createdAt: 0, order: 0));
    expect(c.bookmarks.single.id, 'x');
    expect(c.isEmpty, isFalse);
    expect((await store.loadAll()).single.id, 'x');
  });

  test('addFromFolder: name from the folder, increasing order, no duplicates', () async {
    expect(await c.addFromFolder('/l/Поход'), isTrue);
    expect(await c.addFromFolder('/l/Озеро', customName: ' Моё озеро '), isTrue);
    expect(await c.addFromFolder('/l/Поход'), isFalse);
    expect(c.bookmarks.map((b) => (b.name, b.order, b.createdAt)), [('Поход', 0, 1000), ('Моё озеро', 1, 1000)]);
  });

  test('remove drops it; removing the last one notifies and empties the list', () async {
    await c.addFromFolder('/l/Поход');
    final before = notified;
    await c.remove(c.bookmarks.single.id);
    expect(c.isEmpty, isTrue);
    expect(notified, before + 1);
  });

  test('rename changes the name only', () async {
    await c.addFromFolder('/l/Поход');
    await c.rename(c.bookmarks.single.id, 'Летний поход');
    expect((c.bookmarks.single.name, c.bookmarks.single.path), ('Летний поход', '/l/Поход'));
    expect(() => c.rename(c.bookmarks.single.id, ' '), throwsArgumentError);
  });

  test('updatePath moves the folder and the ones inside, names kept', () async {
    await c.addFromFolder('/l/Поход');
    await c.addFromFolder('/l/Поход/День 1');
    await c.addFromFolder('/l/Поход 2');
    await c.updatePath('/l/Поход', '/l/Архив/Поход');
    expect(c.bookmarks.map((b) => (b.name, b.path)), [
      ('Поход', '/l/Архив/Поход'),
      ('День 1', '/l/Архив/Поход/День 1'),
      ('Поход 2', '/l/Поход 2'),
    ]);
  });

  test('removeByPathPrefix removes only the folder and what is inside it', () async {
    await c.addFromFolder('/l/Поход');
    await c.addFromFolder('/l/Поход/День 1');
    await c.addFromFolder('/l/Поход 2');
    expect(c.hasUnder('/l/Поход'), isTrue);
    await c.removeByPathPrefix('/l/Поход');
    expect(c.bookmarks.map((b) => b.path), ['/l/Поход 2']);
    expect(c.hasUnder('/l/Поход'), isFalse);
  });

  test('clear empties and notifies', () async {
    await c.addFromFolder('/l/a');
    await c.addFromFolder('/l/b');
    final before = notified;
    await c.clear();
    expect(c.isEmpty, isTrue);
    expect(notified, before + 1);
    expect(await store.loadAll(), isEmpty);
  });
}
