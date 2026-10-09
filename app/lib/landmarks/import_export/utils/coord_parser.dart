/// Разбор координат из строк: десятичные градусы, с буквами N/S/E/W,
/// градусы-минуты-секунды. UTM не поддерживается ([UnsupportedError]).
abstract final class CoordParser {
  static final RegExp _utm = RegExp(r'^\s*\d{1,2}\s?[C-HJ-NP-X]\s+\d{5,7}(\.\d+)?\s+\d{6,8}(\.\d+)?\s*$', caseSensitive: false);
  static final RegExp _hemisphere = RegExp(r'[NSEWnsew]');
  static final RegExp _dms = RegExp(
    r'''^([+-]?\d+(?:\.\d+)?)\s*(?:°|d)?\s*(?:(\d+(?:\.\d+)?)\s*(?:'|′|m)?\s*)?(?:(\d+(?:\.\d+)?)\s*(?:"|″|''|s)?\s*)?$''',
  );

  /// Пара «широта, долгота». Разделитель — запятая, точка с запятой или
  /// пробел; с буквами полушарий порядок может быть любым
  /// (`37.6E 55.7N`). Неверная строка — [FormatException].
  static (double lat, double lon) parse(String text) {
    final input = text.trim();
    if (_utm.hasMatch(input)) throw UnsupportedError('UTM coordinates are not supported: "$input"');
    final parts = _split(input);
    if (parts.length != 2) throw FormatException('Expected latitude and longitude', text);
    final a = parts[0];
    final b = parts[1];
    final aLon = _isLongitudeLabel(a);
    final bLat = _isLatitudeLabel(b);
    final (latText, lonText) = aLon || bLat ? (b, a) : (a, b);
    final lat = parseValue(latText, isLatitude: true);
    final lon = parseValue(lonText, isLatitude: false);
    return (lat, lon);
  }

  /// Одно значение в градусах: `55.7558`, `55.7558N`, `S 33.9`,
  /// `55°45'21"N`, `55 45 21.5`. [isLatitude] — проверка диапазона и букв
  /// (N/S для широты, E/W для долготы; null — любые).
  static double parseValue(String text, {bool? isLatitude}) {
    var s = text.trim();
    if (s.isEmpty) throw FormatException('Empty coordinate', text);
    var sign = 1.0;
    final letters = _hemisphere.allMatches(s).map((m) => m.group(0)!.toUpperCase()).toList();
    if (letters.length > 1) throw FormatException('More than one hemisphere letter', text);
    if (letters.length == 1) {
      final h = letters.single;
      if (isLatitude == true && (h == 'E' || h == 'W')) throw FormatException('Longitude letter in latitude', text);
      if (isLatitude == false && (h == 'N' || h == 'S')) throw FormatException('Latitude letter in longitude', text);
      if (h == 'S' || h == 'W') sign = -1;
      isLatitude ??= h == 'N' || h == 'S';
      s = s.replaceAll(_hemisphere, '').trim();
    }
    final match = _dms.firstMatch(s);
    if (match == null) throw FormatException('Not a coordinate', text);
    final degrees = double.parse(match.group(1)!);
    final minutes = match.group(2) == null ? 0.0 : double.parse(match.group(2)!);
    final seconds = match.group(3) == null ? 0.0 : double.parse(match.group(3)!);
    if (minutes >= 60 || seconds >= 60) throw FormatException('Minutes and seconds must be below 60', text);
    if ((minutes > 0 || seconds > 0) && degrees != degrees.truncateToDouble()) {
      throw FormatException('Fractional degrees with minutes', text);
    }
    if (degrees < 0 && sign < 0) throw FormatException('Both a minus and S/W', text);
    final magnitude = degrees.abs() + minutes / 60 + seconds / 3600;
    final value = (degrees < 0 ? -magnitude : magnitude) * sign;
    final limit = isLatitude == true ? 90 : 180;
    if (value.abs() > limit) throw FormatException('Coordinate out of range', text);
    return value;
  }

  static List<String> _split(String input) {
    for (final separator in [';', ',']) {
      if (input.contains(separator)) {
        return input.split(separator).map((p) => p.trim()).where((p) => p.isNotEmpty).toList();
      }
    }
    // Без запятой: «55.7N 37.6E» или «55.7 37.6» — делим по пробелу после
    // буквы полушария или между двумя числами.
    final byLetter = RegExp(r'^(.*?[NSEWnsew])\s+(.+)$').firstMatch(input) ??
        RegExp(r'^([NSEWnsew]\s*[^NSEWnsew]+?)\s+([NSEWnsew].+)$').firstMatch(input);
    if (byLetter != null) return [byLetter.group(1)!.trim(), byLetter.group(2)!.trim()];
    final parts = input.split(RegExp(r'\s+'));
    return parts.length == 2 ? parts : [input];
  }

  static bool _isLongitudeLabel(String s) => RegExp('[EWew]').hasMatch(s);
  static bool _isLatitudeLabel(String s) => RegExp('[NSns]').hasMatch(s);
}
