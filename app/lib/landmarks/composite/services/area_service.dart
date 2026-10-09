import 'package:app/landmarks/composite/operations/polygon_ops.dart';
import 'package:app/landmarks/drafts/metadata_patch.dart';
import 'package:app/landmarks/models/landmark_file.dart';

import 'composite_service.dart';

/// Правка области: многоугольники, точки контура, вырезы.
/// Каждая операция — отдельная запись файла.
class AreaService extends CompositeService<AreaObject> {
  AreaService(super.repository, {super.editor, super.calculator});

  @override
  LandmarkType get type => LandmarkType.area;

  Future<AreaObject> addPolygon(String path, AreaPolygon polygon) =>
      mutate(path, (o) => withPolygons(o, [...o.polygons, polygon]));

  Future<AreaObject> removePolygon(String path, int index) => mutate(path, (o) {
    RangeError.checkValidIndex(index, o.polygons, 'index');
    return withPolygons(o, [...o.polygons]..removeAt(index));
  });

  /// Метаданные многоугольника (без версии и времени).
  Future<AreaObject> updatePolygonMetadata(String path, int index, MetadataPatch patch) => mutate(
    path,
    (o) => changePolygon(
      o,
      index,
      (p) => AreaPolygon(userMetadata: editor.merge(p.userMetadata, patch), outline: p.outline, holes: p.holes),
    ),
  );

  /// Вставляет точку контура на место [locIndex].
  Future<AreaObject> addOutlinePoint(String path, int polyIndex, int locIndex, LandmarkLocation loc) =>
      mutate(path, (o) => changePolygon(o, polyIndex, (p) => PolygonOps.addOutlinePoint(p, loc, atIndex: locIndex)));

  Future<AreaObject> removeOutlinePoint(String path, int polyIndex, int locIndex) =>
      mutate(path, (o) => changePolygon(o, polyIndex, (p) => PolygonOps.removeOutlinePoint(p, locIndex)));

  Future<AreaObject> moveOutlinePoint(String path, int polyIndex, int locIndex, LandmarkLocation newLoc) =>
      mutate(path, (o) => changePolygon(o, polyIndex, (p) => PolygonOps.moveOutlinePoint(p, locIndex, newLoc)));

  Future<AreaObject> reorderOutline(String path, int polyIndex, int from, int to) =>
      mutate(path, (o) => changePolygon(o, polyIndex, (p) => PolygonOps.reorderOutline(p, from, to)));

  Future<AreaObject> addHole(String path, int polyIndex, List<LandmarkLocation> outline) =>
      mutate(path, (o) => changePolygon(o, polyIndex, (p) => PolygonOps.addHole(p, outline)));

  Future<AreaObject> removeHole(String path, int polyIndex, int holeIndex) =>
      mutate(path, (o) => changePolygon(o, polyIndex, (p) => PolygonOps.removeHole(p, holeIndex)));

  /// Копия области с изменённым многоугольником [index].
  static AreaObject changePolygon(AreaObject o, int index, AreaPolygon Function(AreaPolygon) change) {
    RangeError.checkValidIndex(index, o.polygons, 'polyIndex');
    return withPolygons(o, [...o.polygons]..[index] = change(o.polygons[index]));
  }

  static AreaObject withPolygons(AreaObject o, List<AreaPolygon> polygons) =>
      AreaObject(polygons: polygons, userMetadata: o.userMetadata, technicalMetadata: o.technicalMetadata);
}
