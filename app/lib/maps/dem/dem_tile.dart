import 'dart:typed_data';

import 'dem_descriptor.dart';

/// Загруженный тайл высот.
class DemTile {
  const DemTile({required this.descriptor, required this.elevations});

  /// Значение «нет данных» в файле (−32768 как 16 бит).
  static const int voidValue = 0x8000;

  final DemDescriptor descriptor;

  /// Строки с севера на юг, как в файле; samplesPerRow² значений.
  /// Decision: числа в файле знаковые; здесь хранятся как беззнаковые 16
  /// бит (как требует модель) и переводятся в знак при чтении.
  final Uint16List elevations;

  /// Высота билинейно по 4 соседним точкам; [lonFrac], [latFrac] — доля
  /// от юго-западного угла тайла (0..1). Вне тайла — null.
  ///
  /// Decision: соседи «нет данных» пропускаются, веса остальных
  /// нормируются; null — только если нет ни одного соседа с данными и
  /// ненулевым весом.
  double? sample(double lonFrac, double latFrac) {
    if (lonFrac < 0 || lonFrac > 1 || latFrac < 0 || latFrac > 1) return null;
    final n = descriptor.samplesPerRow;
    final col = lonFrac * (n - 1);
    final row = (1 - latFrac) * (n - 1);
    final c0 = col.floor().clamp(0, n - 1);
    final r0 = row.floor().clamp(0, n - 1);
    final c1 = (c0 + 1).clamp(0, n - 1);
    final r1 = (r0 + 1).clamp(0, n - 1);
    final tx = col - c0;
    final ty = row - r0;
    var sum = 0.0;
    var weight = 0.0;
    for (final (r, c, w) in [
      (r0, c0, (1 - tx) * (1 - ty)),
      (r0, c1, tx * (1 - ty)),
      (r1, c0, (1 - tx) * ty),
      (r1, c1, tx * ty),
    ]) {
      final v = _at(r, c);
      if (v == null || w == 0) continue;
      sum += v * w;
      weight += w;
    }
    return weight == 0 ? null : sum / weight;
  }

  int? _at(int row, int col) {
    final raw = elevations[row * descriptor.samplesPerRow + col];
    if (raw == voidValue) return null;
    return raw >= 0x8000 ? raw - 0x10000 : raw;
  }
}
