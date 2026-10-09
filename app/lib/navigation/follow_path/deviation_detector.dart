/// Состояние относительно трека.
enum DeviationState { onTrack, approaching, deviatingFar, deviatingVeryFar }

/// Оценка отклонения от трека.
class DeviationDetector {
  const DeviationDetector();

  /// Во сколько раз дальше порога отклонение становится «очень далёким».
  static const double veryFarFactor = 1.5;

  /// Decision: после поданного сигнала ([wasSignaled]) возврат на трек
  /// засчитывается только ближе этой доли порога — чтобы на границе
  /// сигнал не включался и не выключался на каждом шаге.
  static const double returnFactor = 0.8;

  DeviationState evaluate({
    required double currentDistance,
    required double previousDistance,
    required double threshold,
    required bool wasSignaled,
  }) {
    final onTrackLimit = wasSignaled ? threshold * returnFactor : threshold;
    if (currentDistance <= onTrackLimit) return DeviationState.onTrack;
    if (currentDistance < previousDistance) return DeviationState.approaching;
    if (currentDistance > threshold * veryFarFactor) return DeviationState.deviatingVeryFar;
    return DeviationState.deviatingFar;
  }
}
