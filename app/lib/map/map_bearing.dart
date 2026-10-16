import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Поворот карты: повёрнута ли она от севера. Карта сообщает его на каждом
/// движении камеры; нижнее меню показывает компас с замком, пока карта
/// повёрнута, и по нажатию возвращает её на север ([northUp]).
class MapBearing extends Notifier<bool> {
  /// Меньше этого (в любую сторону) — карта считается смотрящей на север.
  static const double toleranceDegrees = 0.5;

  /// Повёрнута ли карта с азимутом [bearing] (0–360).
  static bool isRotated(double bearing) {
    final b = bearing % 360;
    return b > toleranceDegrees && b < 360 - toleranceDegrees;
  }

  void Function()? _northUp;

  @override
  bool build() => false;

  /// Камера карты сейчас с азимутом [bearing].
  void update(double bearing) {
    final rotated = isRotated(bearing);
    if (rotated != state) state = rotated;
  }

  /// Карта отдаёт сюда, как повернуть себя на север.
  void attach(void Function() northUp) => _northUp = northUp;

  void detach() => _northUp = null;

  /// Повернуть карту на север.
  void northUp() => _northUp?.call();
}

final mapBearingProvider = NotifierProvider<MapBearing, bool>(MapBearing.new);
