import 'package:app/maps/file_maps/file_map_scanner.dart';
import 'package:app/maps/file_maps/map_bounds.dart';

import 'url_variable.dart';

/// Шаблон адреса тайла с переменными `{$x}`, `{$y}`, `{$z}`, `{$!y}`,
/// `{$q}`, `{$bbox}`, `{$ibbox}`, `{$param:имя}`.
class UrlTemplate {
  UrlTemplate(this.template) : usedVariables = Set.unmodifiable(_scan(template));

  final String template;
  final Set<UrlVariable> usedVariables;

  static final RegExp _param = RegExp(r'\{\$param:([^}]*)\}');

  /// Адрес тайла. Неизвестный параметр подставляется пустой строкой.
  /// Decision: без [bbox] границы считаются по тайлу (Web Mercator) в
  /// градусах; числа — с 7 знаками после точки.
  String resolve({required int x, required int y, required int z, Map<String, String>? params, MapBounds? bbox}) {
    final box = bbox ??
        MapBounds(
          northLat: FileMapScanner.tileLat(y, z),
          southLat: FileMapScanner.tileLat(y + 1, z),
          westLon: FileMapScanner.tileLon(x, z),
          eastLon: FileMapScanner.tileLon(x + 1, z),
        );
    String n(double v) => v.toStringAsFixed(7).replaceFirst(RegExp(r'\.?0+$'), '');
    return template
        .replaceAllMapped(_param, (m) => params?[m[1]] ?? '')
        .replaceAll(UrlVariable.yTms.token, '${(1 << z) - 1 - y}')
        .replaceAll(UrlVariable.x.token, '$x')
        .replaceAll(UrlVariable.y.token, '$y')
        .replaceAll(UrlVariable.z.token, '$z')
        .replaceAll(UrlVariable.q.token, quadKey(x, y, z))
        .replaceAll(UrlVariable.ibbox.token, [box.southLat, box.westLon, box.northLat, box.eastLon].map(n).join(','))
        .replaceAll(UrlVariable.bbox.token, [box.westLon, box.southLat, box.eastLon, box.northLat].map(n).join(','));
  }

  /// Ключ квадродерева тайла.
  static String quadKey(int x, int y, int z) {
    final b = StringBuffer();
    for (var i = z; i > 0; i--) {
      final mask = 1 << (i - 1);
      var digit = 0;
      if (x & mask != 0) digit += 1;
      if (y & mask != 0) digit += 2;
      b.write(digit);
    }
    return b.toString();
  }

  static Set<UrlVariable> _scan(String template) => {
    for (final v in UrlVariable.values)
      if (template.contains(v.token)) v,
  };

  @override
  bool operator ==(Object other) => other is UrlTemplate && other.template == template;

  @override
  int get hashCode => template.hashCode;
}
