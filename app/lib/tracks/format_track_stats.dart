String formatTrackLength(double meters) {
  if (meters < 1000) {
    return '${meters.round()} м';
  }
  final km = meters / 1000;
  return '${km.toStringAsFixed(1)} км';
}

String formatTrackDuration(int? seconds) {
  if (seconds == null) return '—';
  final duration = Duration(seconds: seconds);
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60);
  if (hours > 0) {
    return '$hours ч $minutes мин';
  }
  return '$minutes мин';
}

String formatElevationGain(double? meters) {
  if (meters == null) return '—';
  return '+${meters.round()} м';
}

String formatTrackDate(DateTime dateTime) {
  final local = dateTime.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(local.day)}.${two(local.month)}.${local.year}';
}
