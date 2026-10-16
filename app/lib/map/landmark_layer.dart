import 'package:maplibre_gl/maplibre_gl.dart';

import '../landmarks/map_data/landmark_features.dart';
import '../landmarks/models/landmark_type.dart';
import '../waypoints/waypoint_types.dart';

/// Значок метки для карты: файл из библиотеки и цвет → имя картинки,
/// уже добавленной в стиль; null — файла нет, точка рисуется кружком.
typedef LandmarkIconImage = Future<String?> Function(String fileName, String colorHex);

/// Метки на карте: один GeoJSON-источник из [LandmarkFeatures] и слои
/// поверх карт — заливки, линии, точки (кружок или значок), надписи.
///
/// Decision: рисует стиль карты, а не менеджеры аннотаций — тысяча меток
/// уходит на карту одним вызовом [update], а не тысячей addCircle.
/// Источник и слои живут в стиле: после каждой загрузки стиля их ставит
/// заново [attach]. Слои добавляются поверх всех, подложки и ортофото
/// встают под аннотации ([MapLibreLayerHost.annotationsBottomLayerId]),
/// то есть под метки.
class LandmarkLayer {
  LandmarkLayer(this._controller);

  final MapLibreMapController _controller;
  bool _attached = false;
  Future<void>? _attaching;

  /// Растёт с каждой новой загрузкой стиля ([detach]): подключение,
  /// начатое на прежнем стиле, не считается подключением к новому.
  int _style = 0;

  /// Пути меток по id объектов из последнего [update].
  List<String> _paths = const [];

  static const String sourceId = 'landmarks';
  static const String fillLayerId = 'landmarks-fill';
  static const String outlineLayerId = 'landmarks-outline';
  static const String lineLayerId = 'landmarks-line';
  static const String haloLayerId = 'landmarks-halo';
  static const String dotLayerId = 'landmarks-dot';
  static const String iconLayerId = 'landmarks-icon';
  static const String labelLayerId = 'landmarks-label';

  /// Слои, по которым нажатие находит метку.
  static const Set<String> tappableLayerIds = {fillLayerId, lineLayerId, dotLayerId, iconLayerId, labelLayerId};

  /// Шрифт надписей: есть на сервере глифов ([LayerManager.glyphsUrl]).
  static const List<String> labelFont = ['Noto Sans Regular'];

  /// Цвет линий и заливок без своего цвета.
  static const String defaultShapeColor = '#1976D2';

  /// Цвет надписи без своего цвета.
  static const String defaultLabelColor = '#212121';

  bool get isAttached => _attached;

  /// Все слои снизу вверх.
  static const List<String> layerIds = [
    fillLayerId,
    outlineLayerId,
    lineLayerId,
    haloLayerId,
    dotLayerId,
    iconLayerId,
    labelLayerId,
  ];

  /// Источник и слои — после загрузки стиля. Повторный вызов на том же
  /// стиле ничего не делает; [detach] — стиль сменился.
  ///
  /// Decision: прежние слои и источник сначала снимаются. Стиль может
  /// сообщить о загрузке дважды, а уже добавленный слой MapLibre второй
  /// раз не принимает — без этого метки пропадали до перезапуска.
  Future<void> attach() {
    if (_attached) return Future.value();
    final previous = _attaching ?? Future.value();
    final next = previous.catchError((Object _) {}).then((_) => _attached ? null : _attach(_style));
    _attaching = next;
    return next.whenComplete(() {
      if (identical(_attaching, next)) _attaching = null;
    });
  }

  Future<void> _attach(int style) async {
    final existing = await _controller.getLayerIds();
    for (final id in layerIds.reversed) {
      if (existing.contains(id)) await _controller.removeLayer(id);
    }
    if ((await _controller.getSourceIds()).contains(sourceId)) await _controller.removeSource(sourceId);
    await _controller.addGeoJsonSource(sourceId, LandmarkFeatures.collection(const []));
    List<Object> role(FeatureRole r) => ['==', ['get', 'role'], r.name];
    const hasIcon = ['has', 'icon_image'];
    final dot = ['all', role(FeatureRole.point), ['!', hasIcon]];
    const color = ['get', 'paint_color'];

    await _controller.addFillLayer(
      sourceId,
      fillLayerId,
      const FillLayerProperties(fillColor: color, fillOpacity: 0.2),
      filter: role(FeatureRole.fill),
    );
    await _controller.addLineLayer(
      sourceId,
      outlineLayerId,
      const LineLayerProperties(lineColor: color, lineWidth: 2, lineJoin: 'round'),
      filter: role(FeatureRole.fill),
      enableInteraction: false,
    );
    await _controller.addLineLayer(
      sourceId,
      lineLayerId,
      const LineLayerProperties(lineColor: color, lineWidth: 3, lineCap: 'round', lineJoin: 'round'),
      filter: role(FeatureRole.line),
    );
    // Белое свечение под кружком: точка видна и на тёмной, и на пёстрой карте.
    await _controller.addCircleLayer(
      sourceId,
      haloLayerId,
      const CircleLayerProperties(circleRadius: 14, circleColor: '#FFFFFF', circleOpacity: 0.55, circleBlur: 0.7),
      filter: dot,
      enableInteraction: false,
    );
    await _controller.addCircleLayer(
      sourceId,
      dotLayerId,
      const CircleLayerProperties(
        circleRadius: 8,
        circleColor: color,
        circleStrokeColor: '#FFFFFF',
        circleStrokeWidth: 1,
      ),
      filter: dot,
    );
    // Все картинки значков одного размера (kIconLogicalSize в пикселях
    // экрана) — масштаб один на всех. Значки не прячутся друг за другом и
    // за подписями карты.
    await _controller.addSymbolLayer(
      sourceId,
      iconLayerId,
      const SymbolLayerProperties(
        iconImage: ['get', 'icon_image'],
        iconSize: 1,
        iconAllowOverlap: true,
        iconIgnorePlacement: true,
      ),
      filter: ['all', role(FeatureRole.point), hasIcon],
    );
    await _controller.addSymbolLayer(
      sourceId,
      labelLayerId,
      const SymbolLayerProperties(
        textField: ['get', 'text'],
        textFont: labelFont,
        textSize: ['coalesce', ['get', 'text_size'], 14],
        textRotate: ['coalesce', ['get', 'rotation'], 0],
        textRotationAlignment: 'map',
        textColor: color,
        textHaloColor: '#FFFFFF',
        textHaloWidth: 1.5,
        textAllowOverlap: true,
        textIgnorePlacement: true,
      ),
      filter: role(FeatureRole.label),
    );
    _attached = style == _style;
  }

  /// Стиль загружен заново: прежних источника и слоёв в нём больше нет.
  void detach() {
    _style++;
    _attached = false;
    _paths = const [];
  }

  /// Ставит на карту объекты [features] ([LandmarkFeatures.of]);
  /// [iconImage] даёт картинку значка точке со своим значком.
  Future<void> update(List<Map<String, dynamic>> features, LandmarkIconImage iconImage) async {
    if (!_attached) return;
    final images = <String, String?>{};
    for (final f in features) {
      final props = f['properties'] as Map<String, dynamic>;
      final icon = props['user_icon'] as String?;
      if (icon == null || props['role'] != FeatureRole.point.name) continue;
      final key = '$icon|${paintColor(props)}';
      if (!images.containsKey(key)) images[key] = await iconImage(icon, paintColor(props));
    }
    final prepared = prepare(features, (icon, color) => images['$icon|$color']);
    await _controller.setGeoJsonSource(sourceId, LandmarkFeatures.collection(prepared.features));
    _paths = prepared.paths;
  }

  /// Путь метки по нажатию: [featureId] и [layerId] из onFeatureTapped;
  /// null — нажатие не по метке.
  String? pathOf(String featureId, String layerId) {
    if (!tappableLayerIds.contains(layerId)) return null;
    final i = int.tryParse(featureId);
    return i == null || i < 0 || i >= _paths.length ? null : _paths[i];
  }

  /// Объекты для источника: у каждого id — номер в списке путей, цвет
  /// `paint_color`, у точки со значком — `icon_image`.
  static ({List<Map<String, dynamic>> features, List<String> paths}) prepare(
    List<Map<String, dynamic>> features,
    String? Function(String fileName, String colorHex) iconImage,
  ) {
    final paths = <String>[];
    final out = <Map<String, dynamic>>[];
    for (final f in features) {
      final props = f['properties'] as Map<String, dynamic>;
      final color = paintColor(props);
      final icon = props['user_icon'] as String?;
      final image = icon != null && props['role'] == FeatureRole.point.name ? iconImage(icon, color) : null;
      out.add({
        ...f,
        'id': '${paths.length}',
        'properties': {...props, 'paint_color': color, 'icon_image': ?image},
      });
      paths.add(props['path'] as String);
    }
    return (features: out, paths: paths);
  }

  /// Цвет объекта: свой; у точки — цвет её типа метки; у остального — по
  /// умолчанию для линий и надписей.
  static String paintColor(Map<String, dynamic> props) {
    if (props['color'] case final String color) return color;
    return switch (props['role']) {
      'point' when props['type'] == LandmarkType.waypoint.name =>
        waypointTypeColors[props['kind']] ?? waypointTypeColors[defaultWaypointType]!,
      'point' => defaultShapeColor,
      'label' => defaultLabelColor,
      _ => defaultShapeColor,
    };
  }
}
