/// Оценка расхода энергии на пеший маршрут.
///
/// Decision: формула простая и честно приблизительная — человек 70 кг,
/// 0,75 ккал на кг на километр по ровному и подъём с КПД мышц 25 %
/// (m·g·h / 0,25). Спуск не учитывается. Нужна для сравнения треков
/// между собой, а не для точного счёта.
abstract final class EnergyEstimate {
  static const double bodyMassKg = 70;
  static const double flatKcalPerKgKm = 0.75;
  static const double muscleEfficiency = 0.25;
  static const double _joulesPerKcal = 4184;
  static const double _g = 9.81;

  /// Килокалории на [lengthMeters] пути с набором [gainMeters].
  static double kcal(double lengthMeters, {double gainMeters = 0}) {
    final flat = bodyMassKg * flatKcalPerKgKm * lengthMeters / 1000;
    final climb = bodyMassKg * _g * gainMeters / muscleEfficiency / _joulesPerKcal;
    return flat + climb;
  }
}
