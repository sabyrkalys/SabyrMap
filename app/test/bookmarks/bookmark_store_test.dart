import 'package:app/bookmarks/bookmark.dart';
import 'package:app/bookmarks/bookmark_store.dart';
import 'package:app/landmarks/settings/app_settings.dart';
import 'package:app/landmarks/settings/settings_keys.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late AppSettings settings;
  late BookmarkStore store;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    settings = AppSettings(await SharedPreferences.getInstance());
    store = BookmarkStore(settings);
  });

  test('an empty store gives an empty list', () async {
    expect(await store.loadAll(), isEmpty);
  });

  test('saveAll / loadAll round-trip, sorted by order', () async {
    const a = Bookmark(id: 'a', name: 'Поход', path: '/l/Поход', createdAt: 1, order: 1);
    const b = Bookmark(id: 'b', name: 'Озеро', path: '/l/Озеро', createdAt: 2, order: 0);
    await store.saveAll([a, b]);
    expect(await store.loadAll(), [b, a]);
  });

  test('the first version stored plain paths: they still load', () async {
    await settings.setString(SettingsKeys.explorerBookmarks, '["/l/Поход","/l/Озеро"]');
    final loaded = await store.loadAll();
    expect(loaded.map((b) => (b.name, b.path, b.order)), [('Поход', '/l/Поход', 0), ('Озеро', '/l/Озеро', 1)]);
  });

  test('a broken record reads as empty', () async {
    await settings.setString(SettingsKeys.explorerBookmarks, '{nope');
    expect(await store.loadAll(), isEmpty);
  });
}
