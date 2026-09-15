import 'package:app/compass/compass_source.dart';

/// A compass source with no sensor available, so widget tests never render a
/// perpetually-animating CircularProgressIndicator (which would hang
/// pumpAndSettle) and instead land immediately on the "unavailable" state.
class FakeUnavailableCompassSource implements CompassSource {
  @override
  Stream<double?>? get headingStream => null;
}

/// A compass source backed by a controllable stream, for tests that need to
/// assert on rendered heading values.
class FakeCompassSource implements CompassSource {
  FakeCompassSource(this._stream);

  final Stream<double?> _stream;

  @override
  Stream<double?>? get headingStream => _stream;
}
