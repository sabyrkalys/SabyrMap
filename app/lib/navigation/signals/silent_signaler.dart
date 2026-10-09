import 'audio_signaler.dart';
import 'signal_kind.dart';

/// Сигналы без звука: по умолчанию, в тестах и при выключенных сигналах.
class SilentSignaler extends AudioSignaler {
  const SilentSignaler();

  @override
  Future<void> play(SignalKind kind) async {}

  @override
  Future<void> stop() async {}
}
