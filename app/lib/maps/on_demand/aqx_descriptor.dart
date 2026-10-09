import 'package:collection/collection.dart';

import 'projection_spec.dart';
import 'url_template.dart';
import 'zoom_range.dart';

/// Сервер онлайн-карты.
class AqxServer {
  const AqxServer({required this.url, this.headers});

  /// Шаблон адреса тайла.
  final String url;

  /// Заголовки запроса.
  final Map<String, String>? headers;

  Map<String, Object?> toJson() => {'url': url, 'headers': headers};

  factory AqxServer.fromJson(Map<String, dynamic> json) => AqxServer(
    url: json['url'] as String,
    headers: (json['headers'] as Map<String, dynamic>?)?.map((k, v) => MapEntry(k, v as String)),
  );

  static const _map = MapEquality<String, String>();

  @override
  bool operator ==(Object other) => other is AqxServer && other.url == url && _map.equals(other.headers, headers);

  @override
  int get hashCode => Object.hash(url, _map.hash(headers));
}

/// Описание онлайн-карты (файл AQX).
class AqxDescriptor {
  const AqxDescriptor({
    required this.id,
    required this.name,
    required this.urlTemplate,
    required this.zoomRange,
    this.description,
    this.projection = const ProjectionSpec(),
    this.maxThreads = 1,
    this.updateDelay,
    this.insecure = false,
    this.clearColorMinR,
    this.clearColorMinG,
    this.clearColorMinB,
    this.clearColorMaxR,
    this.clearColorMaxG,
    this.clearColorMaxB,
    this.servers = const [],
    this.defaultParams = const {},
    this.version = 1,
  });

  final String id;
  final String name;
  final String? description;

  /// Шаблон первого сервера.
  final UrlTemplate urlTemplate;
  final ZoomRange zoomRange;
  final ProjectionSpec projection;

  /// Одновременных загрузок, 1..3.
  final int maxThreads;

  /// Через сколько тайл считается устаревшим.
  final Duration? updateDelay;

  /// Разрешить сертификаты, которым нельзя доверять.
  final bool insecure;

  /// Цвет, который считается «пустым» (прозрачным), по каналам.
  final int? clearColorMinR, clearColorMinG, clearColorMinB;
  final int? clearColorMaxR, clearColorMaxG, clearColorMaxB;
  final List<AqxServer> servers;
  final Map<String, String> defaultParams;
  final int version;

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'description': description,
    'url': urlTemplate.template,
    'zoomMin': zoomRange.min,
    'zoomMax': zoomRange.max,
    'projection': projection.toJson(),
    'maxThreads': maxThreads,
    'updateDelaySeconds': updateDelay?.inSeconds,
    'insecure': insecure,
    'clearMin': [clearColorMinR, clearColorMinG, clearColorMinB],
    'clearMax': [clearColorMaxR, clearColorMaxG, clearColorMaxB],
    'servers': [for (final s in servers) s.toJson()],
    'params': defaultParams,
    'version': version,
  };

  factory AqxDescriptor.fromJson(Map<String, dynamic> json) {
    final clearMin = (json['clearMin'] as List<dynamic>?) ?? const [null, null, null];
    final clearMax = (json['clearMax'] as List<dynamic>?) ?? const [null, null, null];
    final delay = json['updateDelaySeconds'] as int?;
    return AqxDescriptor(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String?,
      urlTemplate: UrlTemplate(json['url'] as String),
      zoomRange: ZoomRange(json['zoomMin'] as int, json['zoomMax'] as int),
      projection: ProjectionSpec.fromJson(json['projection'] as Map<String, dynamic>? ?? const {}),
      maxThreads: json['maxThreads'] as int? ?? 1,
      updateDelay: delay == null ? null : Duration(seconds: delay),
      insecure: json['insecure'] as bool? ?? false,
      clearColorMinR: clearMin[0] as int?,
      clearColorMinG: clearMin[1] as int?,
      clearColorMinB: clearMin[2] as int?,
      clearColorMaxR: clearMax[0] as int?,
      clearColorMaxG: clearMax[1] as int?,
      clearColorMaxB: clearMax[2] as int?,
      servers: [for (final s in json['servers'] as List<dynamic>? ?? const []) AqxServer.fromJson(s as Map<String, dynamic>)],
      defaultParams: (json['params'] as Map<String, dynamic>? ?? const {}).map((k, v) => MapEntry(k, v as String)),
      version: json['version'] as int? ?? 1,
    );
  }

  static const _servers = ListEquality<AqxServer>();
  static const _params = MapEquality<String, String>();

  @override
  bool operator ==(Object other) =>
      other is AqxDescriptor &&
      other.id == id &&
      other.name == name &&
      other.description == description &&
      other.urlTemplate == urlTemplate &&
      other.zoomRange == zoomRange &&
      other.projection == projection &&
      other.maxThreads == maxThreads &&
      other.updateDelay == updateDelay &&
      other.insecure == insecure &&
      other.clearColorMinR == clearColorMinR &&
      other.clearColorMinG == clearColorMinG &&
      other.clearColorMinB == clearColorMinB &&
      other.clearColorMaxR == clearColorMaxR &&
      other.clearColorMaxG == clearColorMaxG &&
      other.clearColorMaxB == clearColorMaxB &&
      _servers.equals(other.servers, servers) &&
      _params.equals(other.defaultParams, defaultParams) &&
      other.version == version;

  @override
  int get hashCode => Object.hash(id, name, urlTemplate, zoomRange, maxThreads, _servers.hash(servers), version);
}
