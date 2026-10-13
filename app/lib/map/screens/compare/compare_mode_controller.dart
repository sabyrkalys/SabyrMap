import 'package:flutter/foundation.dart';

/// Какой из сравниваемых слоёв сейчас на карте. Слайдер 0..1 и номер
/// слоя связаны: номер = round(слайдер × (count − 1)).
class CompareModeController extends ChangeNotifier {
  CompareModeController(List<String> layerIds, {int initialIndex = 0})
      : assert(layerIds.length >= 2),
        layerIds = List.unmodifiable(layerIds) {
    _index = initialIndex.clamp(0, layerIds.length - 1);
  }

  /// Сверху вниз, как в «Картах на экране».
  final List<String> layerIds;
  late int _index;

  int get count => layerIds.length;
  int get currentIndex => _index;
  String get currentLayerId => layerIds[_index];
  double get sliderValue => _index / (count - 1);

  void setIndex(int index) {
    final next = index.clamp(0, count - 1);
    if (next == _index) return;
    _index = next;
    notifyListeners();
  }

  set sliderValue(double value) => setIndex((value.clamp(0.0, 1.0) * (count - 1)).round());

  void next() => setIndex(_index + 1);

  void previous() => setIndex(_index - 1);
}
