/// Переменные шаблона адреса тайла.
enum UrlVariable {
  /// `{$x}` — номер тайла по X.
  x,

  /// `{$y}` — номер тайла по Y (XYZ, от севера).
  y,

  /// `{$z}` — зум.
  z,

  /// `{$!y}` — Y в схеме TMS (от юга): 2^z − 1 − y.
  yTms,

  /// `{$q}` — ключ квадродерева.
  q,

  /// `{$bbox}` — границы тайла `west,south,east,north`.
  bbox,

  /// `{$ibbox}` — границы тайла `south,west,north,east`.
  ibbox,

  /// `{$param:name}` — параметр по имени.
  param;

  /// Как переменная записана в шаблоне (для [param] — без имени).
  String get token => switch (this) {
    x => r'{$x}',
    y => r'{$y}',
    z => r'{$z}',
    yTms => r'{$!y}',
    q => r'{$q}',
    bbox => r'{$bbox}',
    ibbox => r'{$ibbox}',
    param => r'{$param:',
  };
}
