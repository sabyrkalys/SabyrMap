Задача: реализовать архитектуру карт с двумя режимами хранения, поддержкой наложения слоёв и совместной работой Google + Яндекс + других источников.

═══════════════════════════════════════
1. МОДЕЛИ ДАННЫХ
═══════════════════════════════════════

Создай в lib/map/models/:

enum StorageMode {
  onlineOnly,      // только онлайн, без офлайн-загрузки (Google, Яндекс)
  onlineCache,     // плавный кеш + возможность офлайн-региона (OpenFreeMap, MapTiler)
  offlineRegion,   // только офлайн-файл (пользовательские .mbtiles)
}

enum TileFormat { vector, raster }

enum MapLayerType { base, overlay }

class MapSource {
  final String id;              // уникальный, используется как source id в MapLibre
  final String name;
  final String? styleUrl;       // для векторных стилей
  final String? tileUrlTemplate; // для растровых: {z}/{x}/{y}
  final TileFormat format;
  final StorageMode storageMode;
  final String? attribution;    // обязательно для Google: "© Google"
  final int minZoom;
  final int maxZoom;
  final bool canBeOverlay;      // можно ли накладывать поверх
  final String? thumbnailAsset;
  final double defaultOpacity;  // для overlay: 1.0 для векторных, <1.0 для растровых
  final Map<String, String>? extraParams; // apikey, session и т.п.
}

class MapProvider {
  final String id;
  final String name;
  final String? attribution;
  final List<MapSource> sources;
}

class ActiveLayer {
  final String sourceId;
  final MapLayerType type;      // base или overlay
  final double opacity;         // 0.0–1.0
  final bool visible;
  final int zIndex;             // порядок наложения оверлеев
}

class MapState {
  final String? baseSourceId;
  final List<ActiveLayer> overlays;
  final List<String> favoriteIds;
  final List<MapPreset> presets;
}

class MapPreset {
  final String id;
  final String name;
  final String baseSourceId;
  final List<ActiveLayer> overlays;
}

═══════════════════════════════════════
2. КАТАЛОГ ИСТОЧНИКОВ
═══════════════════════════════════════

Создай lib/map/catalog/:
- assets/maps/builtin_catalog.json — встроенный список провайдеров и источников.
- CatalogRepository: загрузка из assets, метод обновления с удалённого URL, слияние с локальными .mbtiles из mediafile/maps (через существующий MediaFileFolderService).

Встроенный каталог должен включать:

OpenStreetMap Maps:
- OpenFreeMap Liberty (vector, onlineCache, styleUrl https://tiles.openfreemap.org/styles/liberty)
- OpenFreeMap Positron (vector, onlineCache)
- OSM Standard Raster (raster, onlineCache, https://tile.openstreetmap.org/{z}/{x}/{y}.png)

Google Maps (все onlineOnly, raster, attribution "© Google", canBeOverlay: true, defaultOpacity 0.6–0.7):
- Google Map (roadmap)
- Google Satellite
- Google Terrain
- Google Hybrid
- Google Bike (велосипедные дорожки)

Яндекс (все onlineOnly, raster, attribution "© Яндекс", canBeOverlay: true, defaultOpacity 0.75):
- Яндекс Карта (l=map)
- Яндекс Спутник (l=sat)
- Яндекс Гибрид (l=skl)

Провайдеры Google и Яндекс — обязательны. UI должен предупреждать, что эти источники работают только онлайн.

═══════════════════════════════════════
3. GOOGLE MAPS TILES API
═══════════════════════════════════════

Создай lib/map/services/google_tiles_service.dart:

- Метод createSession() — POST на https://tile.googleapis.com/v1/createSession?key=API_KEY с body {mapType, language, region}, возвращает session UUID.
- Метод buildTileUrl(session, mapType) — собирает https://tile.googleapis.com/v1/2dtiles/{z}/{x}/{y}?session=SESSION&key=API_KEY.
- Кеширование session в памяти с TTL (Google выдаёт на ~2 недели, обновляй за сутки до истечения).
- Держать один session на весь жизненный цикл приложения.
- Обновлять при 401/403 или по TTL.
- Если session истёк и обновить не удалось — временно скрыть Google-слои, показать SnackBar «Google-слой недоступен, проверьте подключение», не ронять всё приложение.
- Обработка ошибок сети.

API_KEY хранится в lib/config.dart как константа (проект приватный, dart-define не нужен).

mapType маппинг: Google Map→roadmap, Satellite→satellite, Terrain→terrain, Hybrid→hybrid, Bike→bike (проверь актуальные значения в документации Tile API).

═══════════════════════════════════════
4. ЯНДЕКС TILES API
═══════════════════════════════════════

Создай lib/map/services/yandex_tiles_service.dart:

URL-шаблон:
https://tiles.api-maps.yandex.ru/v1/tiles/?x={x}&y={y}&z={z}&lang=ru_RU&l={layer}&projection=web_mercator&apikey=API_KEY

layer: map / sat / skl.
API_KEY в lib/config.dart.

apikey статичен, ничего обновлять не надо.
При ошибке 403 — показать сообщение в UI, скрыть слой, не ронять приложение.

═══════════════════════════════════════
5. LAYER MANAGER
═══════════════════════════════════════

Создай lib/map/services/layer_manager.dart — управляет стеком слоёв через MapLibreMapController.

Методы:
- setBaseSource(MapSource) — сохранить текущие оверлеи (snapshot), вызвать controller.setStyle(styleUrl) для векторных ИЛИ setStyle('{}') + addSource/addLayer для растровых, дождаться загрузки стиля, затем восстановить оверлеи.
- addOverlay(MapSource, {opacity}) — addSource + addLayer, id = source.id, layerId = '${source.id}-layer'.
- removeOverlay(String sourceId) — removeLayer + removeSource.
- setOpacity(String sourceId, double opacity) — setLayerProperties с RasterLayerProperties(rasterOpacity: opacity).
- setVisibility(String sourceId, bool visible) — opacity 0.0 или 1.0.
- reorderOverlays(List<String> orderedIds) — пересобрать порядок через removeLayer + addLayer.
- restoreOverlays() — вызывается после setStyle.
- getActiveLayers() — текущий snapshot.

ВАЖНО: setStyle сбрасывает все добавленные слои. После смены базовой подложки обязательно вызывать restoreOverlays().

Для Google-источников: перед addSource асинхронно получить session через GoogleTilesService.
Для Яндекс-источников: подставить apikey в URL.

Правило: ошибка одного onlineOnly-источника не должна ломать остальные слои.

═══════════════════════════════════════
6. ОФЛАЙН-РЕГИОНЫ
═══════════════════════════════════════

Создай lib/map/services/offline_service.dart — обёртка над maplibre_gl OfflineManager/OfflineRegion.

Методы:
- createRegion(bounds, styleUrl, minZoom, maxZoom, metadata) — только для источников с storageMode != onlineOnly.
- listRegions() — список с прогрессом и размером.
- deleteRegion(id).
- pauseRegion(id) / resumeRegion(id).
- getTotalCacheSize() — суммарный размер всех регионов для отображения в UI.

Проверка: если source.storageMode == StorageMode.onlineOnly — метод createRegion должен бросать исключение или возвращать null с понятной ошибкой. В UI пункт «Сохранить участок карты» для таких источников скрыт.

═══════════════════════════════════════
7. UI: ЭКРАН «ДОСТУПНЫЕ КАРТЫ»
═══════════════════════════════════════

Создай lib/map/screens/available_maps_screen.dart. Открывается из _MapsPanel.

Структура:
- AppBar «Онлайн-карты» / «Установленные карты» (табы или сегменты)
- Индикатор общего размера кеша сверху (LinearProgressIndicator + текст)
- ExpansionTile по провайдерам (OpenStreetMap Maps, Google Maps, Яндекс)
- Внутри провайдера — ListTile для каждого источника:
  - leading: превью (asset или миниатюра)
  - title: название
  - subtitle: размер кеша + значок режима (🌐 onlineOnly / 💾 onlineCache / 📦 offlineRegion)
  - trailing: PopupMenuButton с пунктами:
    - «Показать» → layerManager.setBaseSource(source)
    - «Добавить как слой» → layerManager.addOverlay(source), неактивен если !source.canBeOverlay
    - «В избранное» → toggle в MapState.favoriteIds
    - «Детали» → диалог с URL, лицензией, min/max zoom
    - «Очистить кэш» → offlineService.deleteRegion для offlineRegion; для onlineCache — заглушка с сообщением; для onlineOnly — пункт скрыт
    - «Сохранить участок карты» → только для storageMode != onlineOnly, открывает экран выбора области
- FloatingActionButton «+» → диалог добавления Style URL или JSON-файла

Провайдеры Google Maps и Яндекс должны иметь в шапке ExpansionTile пометку «Только онлайн».

═══════════════════════════════════════
8. UI: ПАНЕЛЬ СЛОЁВ
═══════════════════════════════════════

Создай lib/map/screens/layers_panel.dart — открывается из _MapsPanel → «Карты на экране».

Структура:
- Секция «Базовая подложка» — RadioListTile по доступным источникам
- Секция «Наложенные слои» — ReorderableListView:
  - Каждая строка: drag-handle, чекбокс видимости, название, Slider прозрачности (0–100%), кнопка удаления
- Кнопка «+ Добавить слой» → открывает available_maps_screen в режиме выбора оверлея
- Секция «Пресеты» — быстрые комбинации (см. пункт 11.3)

Изменения применяются через LayerManager немедленно.

═══════════════════════════════════════
9. ИНТЕГРАЦИЯ С MapScreen
═══════════════════════════════════════

В lib/map/map_screen.dart:
- Подписаться на MapState через Riverpod.
- При изменении baseSourceId — вызвать layerManager.setBaseSource.
- При изменении overlays — синхронизировать через addOverlay/removeOverlay/setOpacity.
- Подключить контроллер MapLibreMap к LayerManager.
- Добавить виджет AttributionBar внизу карты (см. пункт 11.5).

═══════════════════════════════════════
10. ОБРАБОТКА РАЗРЕШЕНИЙ
═══════════════════════════════════════

- Проверить AndroidManifest.xml: добавить READ_EXTERNAL_STORAGE, WRITE_EXTERNAL_STORAGE (maxSdkVersion 32).
- Для Android 10+ — использовать SAF через file_picker.getDirectoryPath() при первом запуске, сохранить путь в SharedPreferences.
- Существующий MediaFileFolderService должен уметь работать с выбранной SAF-папкой.

═══════════════════════════════════════
11. СОВМЕСТНАЯ РАБОТА GOOGLE + ЯНДЕКС + ОВЕРЛЕЕВ
═══════════════════════════════════════

Ключевой сценарий, который должен работать без сбоев:

Пользователь выбирает базовую подложку — Google Satellite (onlineOnly, raster).
Поверх неё добавляет Яндекс.Дороги (onlineOnly, raster) как overlay.
Поверх может добавить ещё OpenFreeMap Roads Layer (vector или raster) как второй overlay.
Плюс треки и метки рисуются сверху всего.

Итоговый стек (снизу вверх):
  [1] Base: Google Satellite        (raster, onlineOnly)
  [2] Overlay: Яндекс.Дороги         (raster, onlineOnly)
  [3] Overlay: OpenFreeMap Roads     (vector/raster, onlineCache)
  [4] Треки, метки, геометрия        (vector, локальные)

Это должно работать одновременно, без конфликтов.

───────────────────────────────
11.1. Правила порядка слоёв
───────────────────────────────

В MapLibre порядок задаётся при добавлении слоя. Используй belowLayerId для точной вставки.

Для каждого overlay назначай zIndex в ActiveLayer:
  - Базовый слой — zIndex = 0 (задаётся через style)
  - Overlay 1 — zIndex = 10
  - Overlay 2 — zIndex = 20
  - Треки/метки — zIndex = 100

При addOverlay вычисляй belowLayerId так:
  - найти слой с наименьшим zIndex, который больше текущего
  - если такой есть — belowLayerId = '${его sourceId}-layer'
  - если нет — belowLayerId = null (рисуется поверх всего)

При reorderOverlays — пересобрать все оверлеи заново в новом порядке.

───────────────────────────────
11.2. Растровые оверлеи поверх растровой подложки
───────────────────────────────

Google Satellite — непрозрачный растр. Яндекс.Дороги — тоже растр.
Проблема: Яндекс.Дороги полностью перекроют Google Satellite, если у них нет прозрачности.

Решение:
- Яндекс.Дороги (l=map) — использовать с rasterOpacity 0.75 по умолчанию, чтобы подложка просвечивала.
- Пользователь может менять прозрачность слайдером (0.0–1.0) в layers_panel.
- При opacity = 1.0 Яндекс полностью перекрывает Google — это тоже валидный режим.

Значение по умолчанию для overlay:
  - Яндекс.Дороги → 0.75
  - Яндекс.Гибрид → 0.75
  - Google Hybrid → 0.6
  - Google Bike → 0.7
  - Google Satellite → 0.6
  - OpenFreeMap Roads → 1.0 (векторный, рисуется поверх корректно)

───────────────────────────────
11.3. Комбинированные пресеты
───────────────────────────────

Добавь в UI готовые пресеты — быстрое переключение между типовыми комбинациями:

- «Google Satellite + Яндекс.Дороги» — base Google Satellite, overlay Яндекс.Дороги (0.75)
- «Google Hybrid + OSM Notes» — base Google Hybrid, overlay OSM Notes
- «Яндекс.Спутник + Яндекс.Дороги» — base Яндекс.Спутник, overlay Яндекс.Дороги (0.75)
- «OpenFreeMap Liberty» — чистый векторный базовый слой без оверлеев
- «OpenFreeMap + Google Satellite (полупрозрачно)» — base OpenFreeMap, overlay Google Satellite (0.4) для сравнения

Пресеты хранить в MapState, переключаться одним тапом из _MapsPanel.

───────────────────────────────
11.4. Управление сессиями Google и ключами Яндекс
───────────────────────────────

Особенность совместной работы: Google требует Session Token, Яндекс — apikey.
Оба могут быть активны одновременно.

GoogleTilesService:
  - держать один session на весь жизненный цикл приложения,
  - обновлять при 401/403 или по TTL,
  - если session истёк и обновить не удалось — временно скрыть Google-слои, показать SnackBar,
  - не ронять всё приложение из-за одного источника.

YandexTilesService:
  - apikey статичен,
  - при ошибке 403 — показать сообщение в UI, скрыть слой.

Правило: ошибка одного onlineOnly-источника не должна ломать остальные слои.

───────────────────────────────
11.5. Атрибуция при нескольких источниках
───────────────────────────────

Когда активны Google и Яндекс одновременно — нужно показать обе атрибуции.

Реализация:
  - отдельный виджет AttributionBar внизу карты,
  - собирает attribution из всех активных слоёв (base + overlays),
  - формат: «© Google · © Яндекс · © OpenStreetMap contributors»,
  - стиль: полупрозрачная плашка, мелкий шрифт, не перекрывает элементы управления.

Скрывать атрибуцию нельзя — это требование обоих провайдеров.

───────────────────────────────
11.6. Порядок сброса и восстановления
───────────────────────────────

При смене базовой подложки через setStyle:
  1. Сохранить snapshot текущих overlays (id, opacity, visible, zIndex).
  2. Вызвать controller.setStyle(newBaseStyle) ИЛИ setStyle('{}') + addSource для растровой базы.
  3. Дождаться завершения загрузки стиля.
  4. Для каждого overlay в snapshot — вызвать addOverlay с сохранёнными параметрами.
  5. Если Google требует session — получить его до addOverlay.
  6. Восстановить порядок через reorderOverlays.

При перезапуске приложения:
  1. Прочитать MapState из SharedPreferences / Riverpod persistence.
  2. Восстановить base + overlays.
  3. Обновить Google session если нужно.

───────────────────────────────
11.7. Производительность при 3+ активных слоях
───────────────────────────────

Каждый растровый слой — отдельная текстура на GPU.

Рекомендации:
  - ограничить максимум активных растровых overlays до 3,
  - при попытке добавить 4-й — показать предупреждение,
  - в UI показывать индикатор нагрузки (например, «3/3 слоя»),
  - при слабом устройстве (device_info_plus) — ограничить до 2.

───────────────────────────────
11.8. UI: индикация активного режима
───────────────────────────────

В _MapsPanel и в шапке карты показывать текущую комбинацию:

  ┌─────────────────────────────────┐
  │ Base: Google Satellite          │
  │ Overlays: Яндекс.Дороги (75%)   │
  │           OpenFreeMap (100%)    │
  │ 🌐 Онлайн · 🌐 Онлайн · 💾 Кеш  │
  └─────────────────────────────────┘

═══════════════════════════════════════
ТРЕБОВАНИЯ К РЕАЛИЗАЦИИ
═══════════════════════════════════════

1. Не дублировать существующий код — использовать MediaFileFolderService, HomeShell, _MapsPanel.
2. Riverpod для состояния (MapStateNotifier, CatalogNotifier, LayerManagerProvider).
3. Все строки UI — на русском, как в существующих экранах.
4. Логотип «© Google» и «© Яндекс» — обязателен, реализуй через attribution в RasterSourceProperties и через AttributionBar.
5. Для Google/Яндекс — storageMode: onlineOnly, пункт «Сохранить участок карты» скрыт.
6. Не использовать dart-define для ключей — просто константы в config.dart.
7. Код на Dart 3, null-safety, без deprecated API.
8. По завершении каждого крупного блока — компилируй и проверяй.
9. Обязательно поддержать режим одновременной работы Google + Яндекс + OpenFreeMap + треков. Это ключевой сценарий, а не крайний случай.
10. Порядок слоёв управляется через zIndex в ActiveLayer и belowLayerId при addLayer.
11. Растровые оверлеи по умолчанию должны иметь opacity < 1.0. Точные значения — см. пункт 11.2.
12. При смене базового стиля все оверлеи должны восстанавливаться автоматически (snapshot → setStyle → restore).
13. Ошибка одного onlineOnly-источника не должна ломать остальные слои.
14. Атрибуция собирается со всех активных слоёв и отображается в AttributionBar.
15. Добавить готовые пресеты комбинаций слоёв — см. пункт 11.3.
16. Ограничить максимум активных растровых overlays до 3 (на слабых — до 2).

═══════════════════════════════════════
ПОРЯДОК РАБОТЫ
═══════════════════════════════════════

Начни с пунктов 1–2 (модели и каталог), покажи структуру файлов и код.
Дальше двигайся по списку, спрашивая подтверждение перед переходом к следующему блоку.
После каждого блока — компилируй и проверяй, чтобы не накапливать ошибки.