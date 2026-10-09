import 'position_snapshot.dart';

/// Источник положения устройства. Реальная реализация (GPS) — в
/// платформенном слое.
abstract class PositionSource {
  const PositionSource();

  /// Текущее положение; null — неизвестно.
  Future<PositionSnapshot?> getCurrent();

  /// Поток положений с желаемым интервалом.
  Stream<PositionSnapshot> watch({Duration interval = const Duration(seconds: 1)});
}

/// Источник, у которого положения нет: до подключения платформенного.
class StubPositionSource extends PositionSource {
  const StubPositionSource();

  @override
  Future<PositionSnapshot?> getCurrent() async => null;

  @override
  Stream<PositionSnapshot> watch({Duration interval = const Duration(seconds: 1)}) => const Stream.empty();
}
