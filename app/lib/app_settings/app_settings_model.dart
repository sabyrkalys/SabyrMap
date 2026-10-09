import 'defaults.dart';

/// Общие настройки приложения.
class AppSettingsModel {
  const AppSettingsModel({
    this.locale = AppDefaults.locale,
    this.darkMode = AppDefaults.darkMode,
    this.mapRotationEnabled = AppDefaults.mapRotationEnabled,
    this.perspectiveEnabled = AppDefaults.perspectiveEnabled,
    this.lockMapEnabled = AppDefaults.lockMapEnabled,
    this.uiScale = AppDefaults.uiScale,
    this.primaryCoordsFormat = AppDefaults.primaryCoordsFormat,
    this.secondaryCoordsFormat,
    this.displayGrid = AppDefaults.displayGrid,
    this.displayAltGrid = AppDefaults.displayAltGrid,
  });

  final String locale;
  final bool darkMode;
  final bool mapRotationEnabled;
  final bool perspectiveEnabled;
  final bool lockMapEnabled;

  /// 0.8..1.5.
  final double uiScale;

  /// `wgs84` или `sk42`.
  final String primaryCoordsFormat;
  final String? secondaryCoordsFormat;
  final bool displayGrid;
  final bool displayAltGrid;

  static const Object _keep = Object();

  AppSettingsModel copyWith({
    String? locale,
    bool? darkMode,
    bool? mapRotationEnabled,
    bool? perspectiveEnabled,
    bool? lockMapEnabled,
    double? uiScale,
    String? primaryCoordsFormat,
    Object? secondaryCoordsFormat = _keep,
    bool? displayGrid,
    bool? displayAltGrid,
  }) => AppSettingsModel(
    locale: locale ?? this.locale,
    darkMode: darkMode ?? this.darkMode,
    mapRotationEnabled: mapRotationEnabled ?? this.mapRotationEnabled,
    perspectiveEnabled: perspectiveEnabled ?? this.perspectiveEnabled,
    lockMapEnabled: lockMapEnabled ?? this.lockMapEnabled,
    uiScale: uiScale ?? this.uiScale,
    primaryCoordsFormat: primaryCoordsFormat ?? this.primaryCoordsFormat,
    secondaryCoordsFormat: identical(secondaryCoordsFormat, _keep)
        ? this.secondaryCoordsFormat
        : secondaryCoordsFormat as String?,
    displayGrid: displayGrid ?? this.displayGrid,
    displayAltGrid: displayAltGrid ?? this.displayAltGrid,
  );

  @override
  bool operator ==(Object other) =>
      other is AppSettingsModel &&
      other.locale == locale &&
      other.darkMode == darkMode &&
      other.mapRotationEnabled == mapRotationEnabled &&
      other.perspectiveEnabled == perspectiveEnabled &&
      other.lockMapEnabled == lockMapEnabled &&
      other.uiScale == uiScale &&
      other.primaryCoordsFormat == primaryCoordsFormat &&
      other.secondaryCoordsFormat == secondaryCoordsFormat &&
      other.displayGrid == displayGrid &&
      other.displayAltGrid == displayAltGrid;

  @override
  int get hashCode => Object.hash(
    locale,
    darkMode,
    mapRotationEnabled,
    perspectiveEnabled,
    lockMapEnabled,
    uiScale,
    primaryCoordsFormat,
    secondaryCoordsFormat,
    displayGrid,
    displayAltGrid,
  );
}
