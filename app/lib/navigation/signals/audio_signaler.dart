import 'signal_kind.dart';

/// Воспроизведение сигналов. Реальная реализация (звук) — в
/// платформенном слое.
abstract class AudioSignaler {
  const AudioSignaler();

  Future<void> play(SignalKind kind);

  /// Прервать звучащий сигнал.
  Future<void> stop();
}
