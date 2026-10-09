/// Зона относительно центра оповещения.
enum ProximityZone {
  /// Дальше радиуса.
  outside,

  /// От 1/2 до 1 радиуса.
  outer,

  /// От 1/4 до 1/2 радиуса.
  middle,

  /// Ближе 1/4 радиуса.
  inner;

  /// Внутри радиуса.
  bool get isInside => this != outside;
}
