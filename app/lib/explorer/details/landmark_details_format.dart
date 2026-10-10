/// Значения полей детализации: «1,49 кБ», «12,40 км», «2 ч 05 мин».
abstract final class DetailsFormat {
  static String _comma(double v, int digits) => v.toStringAsFixed(digits).replaceAll('.', ',');

  /// «512 Б», «1,49 кБ», «2,30 МБ».
  static String size(int bytes) {
    if (bytes < 1024) return '$bytes Б';
    if (bytes < 1024 * 1024) return '${_comma(bytes / 1024, 2)} кБ';
    if (bytes < 1024 * 1024 * 1024) return '${_comma(bytes / 1024 / 1024, 2)} МБ';
    return '${_comma(bytes / 1024 / 1024 / 1024, 2)} ГБ';
  }

  /// `dd.MM.yyyy HH:mm:ss`, местное время.
  static String dateTime(DateTime t) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(t.day)}.${two(t.month)}.${t.year} ${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
  }

  static String dateTimeMs(int ms) => dateTime(DateTime.fromMillisecondsSinceEpoch(ms));

  /// «850 м», «12,40 км».
  static String distance(double meters) => meters < 1000 ? '${meters.round()} м' : '${_comma(meters / 1000, 2)} км';

  /// «2 ч 05 мин», «14 мин».
  static String duration(int ms) {
    final d = Duration(milliseconds: ms);
    final minutes = (d.inMinutes % 60).toString().padLeft(2, '0');
    return d.inHours > 0 ? '${d.inHours} ч $minutes мин' : '${d.inMinutes} мин';
  }

  static String elevation(double meters) => '${meters.round()} м';

  /// «850 м²», «1,25 км²».
  static String area(double squareMeters) =>
      squareMeters < 1e6 ? '${squareMeters.round()} м²' : '${_comma(squareMeters / 1e6, 2)} км²';

  /// «4,2 км/ч».
  static String speed(double metersPerSecond) => '${_comma(metersPerSecond * 3.6, 1)} км/ч';

  /// «45°».
  static String azimuth(double degrees) => '${degrees.round()}°';
}
