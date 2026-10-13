import 'package:app/map/catalog/catalog_repository.dart';
import 'package:app/map/screens/layer_details/layer_details_preview.dart';
import 'package:app/map/screens/layer_details/layer_details_screen.dart';
import 'package:app/map/screens/on_screen/layer_context_menu.dart';
import 'package:app/map/services/tile_cache_stats.dart';
import 'package:app/map/state/map_layers_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../on_screen/harness.dart';

void main() {
  final h = LayersHarness();

  Future<void> open(WidgetTester tester, String sourceId, {String? layerMenuId}) async {
    await h.pump(
      tester,
      saved: stateWith(const [hybridLayer]),
      overrides: [
        localMapInfoProvider.overrideWith((ref) async => const {
              'ortho-Доброполье.mbtiles':
                  LocalMapInfo(sizeBytes: 3 * 1024 * 1024, path: '/o/Доброполье.mbtiles', files: ['Доброполье.mbtiles']),
            }),
        tileCacheStatsProvider.overrideWith((ref) async => const TileCacheStats(
              templatesBySource: {
                'yandex-hybrid': {'y'},
              },
              bytesByTemplate: {'y': 1024 * 1024},
            )),
      ],
      child: Builder(
        builder: (context) => TextButton(
          key: const Key('open_details'),
          onPressed: () => LayerDetailsScreen.show(context, sourceId, layerMenuId: layerMenuId),
          child: const Text('open'),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('open_details')));
    await tester.pumpAndSettle();
  }

  String? valueOf(WidgetTester tester, String label, {int index = 0}) {
    final rows = find.ancestor(of: find.text(label), matching: find.byType(Row));
    if (rows.evaluate().length <= index) return null;
    final texts = find.descendant(of: rows.at(index), matching: find.byType(SelectableText));
    return tester.widget<SelectableText>(texts.first).data;
  }

  testWidgets('app bar: the map group and the map name; ✕ closes', (tester) async {
    await open(tester, 'yandex-hybrid');
    expect(find.text('Яндекс'), findsOneWidget);
    expect(tester.widget<Text>(find.byKey(const Key('details_subtitle'))).data, 'Яндекс Гибрид');
    await tester.tap(find.byKey(const Key('details_close')));
    await tester.pumpAndSettle();
    expect(find.byType(LayerDetailsScreen), findsNothing);
  });

  testWidgets('preview is 180 high, a placeholder without a picture', (tester) async {
    await open(tester, 'yandex-hybrid');
    expect(tester.getSize(find.byType(LayerDetailsPreview)).height, LayerDetailsPreview.height);
    expect(LayerDetailsPreview.height, 180);
    expect(find.byKey(const Key('details_preview_placeholder')), findsOneWidget);
  });

  testWidgets('ИНФОРМАЦИЯ: name, type, «Добавить как слой»; no «Источник» or «Обновить»', (tester) async {
    await open(tester, 'yandex-hybrid');
    expect(find.text('ИНФОРМАЦИЯ'), findsOneWidget);
    expect(valueOf(tester, 'Имя'), 'Яндекс Гибрид');
    expect(valueOf(tester, 'Тип'), 'Гибрид · Растр · Онлайн');
    expect(valueOf(tester, 'Добавить как слой'), 'Да');
    expect(find.text('Источник'), findsNothing);
    expect(find.text('Обновить'), findsNothing);
    expect(find.text('Обновлено'), findsNothing);
  });

  testWidgets('ПРОЕКЦИЯ: name, id, geoid, zooms', (tester) async {
    await open(tester, 'yandex-hybrid');
    expect(find.text('ПРОЕКЦИЯ'), findsOneWidget);
    expect(valueOf(tester, 'Имя', index: 1), 'EPSG:3857 (Web Mercator)');
    expect(valueOf(tester, 'Id'), 'EPSG:3857');
    expect(valueOf(tester, 'Геоид'), isNotEmpty);
    expect(valueOf(tester, 'Масштабы'), '0–22');
  });

  testWidgets('ФАЙЛЫ of an online map: what its tile cache holds', (tester) async {
    await open(tester, 'yandex-hybrid');
    expect(find.text('ФАЙЛЫ'), findsOneWidget);
    expect(valueOf(tester, 'Размер'), '≈ 1.0 МБ в кэше');
    expect(find.text('Папка'), findsNothing);
  });

  testWidgets('online map with nothing cached has no ФАЙЛЫ', (tester) async {
    await open(tester, 'osm-standard');
    expect(find.text('ФАЙЛЫ'), findsNothing);
  });

  testWidgets('ФАЙЛЫ of the orthophotos: folder, files, size', (tester) async {
    await open(tester, MapStateNotifier.orthophotosKey);
    expect(find.text('Ортофотопланы'), findsWidgets);
    expect(valueOf(tester, 'Папка'), '/o');
    expect(valueOf(tester, 'Файл'), 'Доброполье.mbtiles');
    expect(valueOf(tester, 'Размер'), '3.0 МБ');
    expect(valueOf(tester, 'Добавить как слой'), 'Нет');
  });

  testWidgets('sections collapse and expand', (tester) async {
    await open(tester, 'yandex-hybrid');
    expect(find.text('Геоид'), findsOneWidget);
    await tester.tap(find.byKey(const Key('details_section_Проекция')));
    await tester.pumpAndSettle();
    expect(find.text('Геоид'), findsNothing);
    expect(find.byIcon(Icons.expand_more), findsOneWidget);
    await tester.tap(find.byKey(const Key('details_section_Проекция')));
    await tester.pumpAndSettle();
    expect(find.text('Геоид'), findsOneWidget);
  });

  testWidgets('⋮ opens the layer menu when opened from «Карты на экране»; none from the catalog', (tester) async {
    await open(tester, 'yandex-hybrid', layerMenuId: 'yandex-hybrid');
    await tester.tap(find.byKey(const Key('details_menu')));
    await tester.pumpAndSettle();
    expect(find.byType(LayerContextMenu), findsOneWidget);
  });

  testWidgets('no ⋮ without a layer', (tester) async {
    await open(tester, 'osm-standard');
    expect(find.byKey(const Key('details_menu')), findsNothing);
  });

  testWidgets('the built-in base map: Natural Earth, zooms 0–5, cannot be added as a layer', (tester) async {
    await open(tester, MapStateNotifier.worldKey);
    expect(tester.widget<Text>(find.byKey(const Key('details_subtitle'))).data, 'Базовая карта');
    expect(find.text('Встроена в приложение'), findsOneWidget);
    expect(valueOf(tester, 'Имя'), 'Базовая карта (Natural Earth)');
    expect(valueOf(tester, 'Масштабы'), '0–5');
    expect(valueOf(tester, 'Добавить как слой'), 'Нет');
  });
}
