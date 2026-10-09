import 'edit_mode_target.dart';

/// Состояние режима правки.
class EditModeState {
  const EditModeState({this.target, this.warnings = const []});

  /// Открытый объект; null — режим правки выключен.
  final EditModeTarget? target;

  /// Почему последние команды не применились.
  final List<String> warnings;

  bool get isActive => target != null;
  bool get isDirty => target?.isDirty ?? false;
}
