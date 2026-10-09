/// Настройки данных высот.
class DemSettings {
  const DemSettings({this.useElevationData = true, this.autoDownload = false, this.useBarometric = false});

  final bool useElevationData;
  final bool autoDownload;
  final bool useBarometric;

  DemSettings copyWith({bool? useElevationData, bool? autoDownload, bool? useBarometric}) => DemSettings(
    useElevationData: useElevationData ?? this.useElevationData,
    autoDownload: autoDownload ?? this.autoDownload,
    useBarometric: useBarometric ?? this.useBarometric,
  );

  Map<String, Object?> toJson() => {
    'useElevationData': useElevationData,
    'autoDownload': autoDownload,
    'useBarometric': useBarometric,
  };

  factory DemSettings.fromJson(Map<String, dynamic> json) => DemSettings(
    useElevationData: json['useElevationData'] as bool? ?? true,
    autoDownload: json['autoDownload'] as bool? ?? false,
    useBarometric: json['useBarometric'] as bool? ?? false,
  );

  @override
  bool operator ==(Object other) =>
      other is DemSettings &&
      other.useElevationData == useElevationData &&
      other.autoDownload == autoDownload &&
      other.useBarometric == useBarometric;

  @override
  int get hashCode => Object.hash(useElevationData, autoDownload, useBarometric);
}
