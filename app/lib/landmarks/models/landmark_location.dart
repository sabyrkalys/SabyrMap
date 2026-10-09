import 'dart:typed_data';

import 'package:collection/collection.dart';

/// Точка в WGS84 с необязательными измерениями (высота, точность, время...).
class LandmarkLocation {
  const LandmarkLocation({required this.longitude, required this.latitude, this.values = const []});

  /// Долгота, градусы WGS84.
  final double longitude;

  /// Широта, градусы WGS84.
  final double latitude;

  /// Дополнительные значения в порядке записи.
  final List<LocationValue> values;

  /// Первое значение типа [type] (см. [LocationValueType]), если есть.
  LocationValue? valueOf(int type) => values.firstWhereOrNull((v) => v.type == type);

  static const _equality = ListEquality<LocationValue>();

  @override
  bool operator ==(Object other) =>
      other is LandmarkLocation &&
      other.longitude == longitude &&
      other.latitude == latitude &&
      _equality.equals(other.values, values);

  @override
  int get hashCode => Object.hash(longitude, latitude, _equality.hash(values));

  @override
  String toString() => 'LandmarkLocation($latitude, $longitude, $values)';
}

/// Одно измерение точки. [value] хранится в «сыром» масштабе формата
/// (см. [LocationValueType]): [int] для числовых типов, [Uint8List] для
/// байтовых (`cellular`, `satellites`).
class LocationValue {
  const LocationValue({required this.type, required this.value});

  /// Код типа из [LocationValueType].
  final int type;

  /// [int] или [Uint8List] в зависимости от [type].
  final Object value;

  static const _equality = DeepCollectionEquality();

  @override
  bool operator ==(Object other) => other is LocationValue && other.type == type && _equality.equals(other.value, value);

  @override
  int get hashCode => Object.hash(type, _equality.hash(value));

  @override
  String toString() => 'LocationValue(0x${type.toRadixString(16)}, $value)';
}

/// Известные типы [LocationValue] и их представление в файле.
abstract final class LocationValueType {
  /// int: горизонтальная точность, метры × 1e2.
  static const int accuracy = 0x61;

  /// byte: заряд батареи, 0..100.
  static const int battery = 0x62;

  /// int: высота, метры × 1e3.
  static const int elevation = 0x65;

  /// 2 байта: данные сотовой сети.
  static const int cellular = 0x6e;

  /// int: давление, гПа × 1e3.
  static const int pressure = 0x70;

  /// 8 байт: данные о спутниках.
  static const int satellites = 0x73;

  /// long: время UTC, Unix ms.
  static const int utcTime = 0x74;

  /// int: вертикальная точность, метры × 1e2.
  static const int verticalAcc = 0x76;

  /// Все известные типы.
  static const List<int> all = [accuracy, battery, elevation, cellular, pressure, satellites, utcTime, verticalAcc];
}
