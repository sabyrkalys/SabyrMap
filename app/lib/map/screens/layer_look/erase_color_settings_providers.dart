import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/landmark_services_provider.dart';
import '../../../maps/color/color_range.dart';
import '../../../maps/settings/maps_settings.dart';

/// Ширина диапазона удаления цвета (±N), общая для всех слоёв; хранится в
/// настройках карт. Без них (тесты) — только в памяти.
class ColorRangesWidthNotifier extends Notifier<int> {
  MapsSettings? get _settings {
    try {
      return ref.read(landmarkServicesProvider).mapsSettings;
    } on Object {
      return null;
    }
  }

  @override
  int build() => _settings?.colorRangesWidth ?? ColorRange.defaultWidth;

  Future<void> set(int width) async {
    state = width;
    await _settings?.setColorRangesWidth(width);
  }
}

final colorRangesWidthProvider = NotifierProvider<ColorRangesWidthNotifier, int>(ColorRangesWidthNotifier.new);

/// Цвет (ARGB) пикселя карты под прицелом; null — недоступен. Платформенная
/// реализация не подключена: пипетка всегда отвечает «Цвет недоступен».
final centerPixelProvider = Provider<Future<int?> Function()>((ref) => () async => null);
