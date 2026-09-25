import 'dart:math' as math;

/// The map never zooms past this; also the denominator of «6/20».
const double mapMaxZoom = 20;

const double _earthCircumference = 40075016.686;
const double _tileSize = 512;
// Nominal Android density: 160 dp per inch.
const double _metersPerDp = 0.0254 / 160;

/// Ground metres covered by one logical pixel at [zoom] and [lat]
/// (MapLibre native renders 512-px tiles in logical pixels).
double metersPerDp(double zoom, double lat) {
  final cosLat = math.cos(lat.clamp(-85.0, 85.0) * math.pi / 180);
  return _earthCircumference * cosLat / (_tileSize * math.pow(2, zoom));
}

String _grouped(int value) {
  final digits = value.toString();
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(' ');
    buffer.write(digits[i]);
  }
  return buffer.toString();
}

/// «1:5 000» under 10 000, «1:14 546K» from 10 000 up.
String scaleText(double zoom, double lat) {
  final ratio = (metersPerDp(zoom, lat) / _metersPerDp).round();
  if (ratio < 10000) return '1:${_grouped(ratio)}';
  return '1:${_grouped((ratio / 1000).round())}K';
}

/// «6/20»: rounded current zoom over the map's maximum.
String zoomText(double zoom) {
  final current = zoom.round().clamp(0, mapMaxZoom.toInt());
  return '$current/${mapMaxZoom.toInt()}';
}

/// The largest 1/2/5·10ⁿ-metre distance that fits in [maxWidthDp].
({double meters, double widthDp, String label}) scaleBar(double zoom, double lat, {double maxWidthDp = 100}) {
  final perDp = metersPerDp(zoom, lat);
  final maxMeters = perDp * maxWidthDp;
  final power = math.pow(10, (math.log(maxMeters) / math.ln10).floor()).toDouble();
  var meters = power;
  for (final step in const [5, 2, 1]) {
    if (step * power <= maxMeters) {
      meters = step * power;
      break;
    }
  }
  final label = meters >= 1000 ? '${(meters / 1000).round()} км' : '${meters.round()} м';
  return (meters: meters, widthDp: meters / perDp, label: label);
}

/// «→ 232,03 км 348.6°»; under a kilometre «→ 350 м 12.0°».
String targetText(double meters, double azimuth) {
  final distance = meters < 999.995
      ? '${meters.round()} м'
      : '${(meters / 1000).toStringAsFixed(2).replaceAll('.', ',')} км';
  return '→ $distance ${azimuth.toStringAsFixed(1)}°';
}
