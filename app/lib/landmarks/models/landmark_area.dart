import 'package:collection/collection.dart';

import 'landmark_location.dart';
import 'landmark_metadata.dart';
import 'landmark_object.dart';
import 'landmark_type.dart';

/// Область из одного или нескольких многоугольников (файл `.are`).
class AreaObject extends LandmarkObject {
  const AreaObject({
    this.polygons = const [],
    this.userMetadata = const LandmarkMetadata(),
    this.technicalMetadata = const LandmarkMetadata(),
  });

  final List<AreaPolygon> polygons;

  @override
  final LandmarkMetadata userMetadata;

  @override
  final LandmarkMetadata technicalMetadata;

  @override
  LandmarkType get type => LandmarkType.area;

  @override
  AreaObject withTechnicalMetadata(LandmarkMetadata technicalMetadata) =>
      AreaObject(polygons: polygons, userMetadata: userMetadata, technicalMetadata: technicalMetadata);

  static const _equality = ListEquality<AreaPolygon>();

  @override
  bool operator ==(Object other) =>
      other is AreaObject &&
      _equality.equals(other.polygons, polygons) &&
      other.userMetadata == userMetadata &&
      other.technicalMetadata == technicalMetadata;

  @override
  int get hashCode => Object.hash(_equality.hash(polygons), userMetadata, technicalMetadata);
}

/// Многоугольник области: внешний контур и вырезы.
class AreaPolygon {
  const AreaPolygon({this.userMetadata = const LandmarkMetadata(), this.outline = const [], this.holes = const []});

  final LandmarkMetadata userMetadata;

  /// Внешний контур, без повтора первой точки в конце.
  final List<LandmarkLocation> outline;

  /// Вырезы внутри контура.
  final List<List<LandmarkLocation>> holes;

  static const _equality = DeepCollectionEquality();

  @override
  bool operator ==(Object other) =>
      other is AreaPolygon &&
      other.userMetadata == userMetadata &&
      _equality.equals(other.outline, outline) &&
      _equality.equals(other.holes, holes);

  @override
  int get hashCode => Object.hash(userMetadata, _equality.hash(outline), _equality.hash(holes));
}
