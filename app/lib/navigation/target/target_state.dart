import 'package:app/landmarks/models/landmark_location.dart';

import 'target_info.dart';

/// Состояние цели.
class TargetState {
  const TargetState({this.target, this.source, this.info, this.displayLine = true, this.displayInfoBox = true});

  final LandmarkLocation? target;

  /// Откуда тянется линия: центр экрана или положение устройства.
  final LandmarkLocation? source;

  /// Сведения о цели; null — нет исходной точки.
  final TargetInfo? info;
  final bool displayLine;
  final bool displayInfoBox;

  bool get isActive => target != null;
}
