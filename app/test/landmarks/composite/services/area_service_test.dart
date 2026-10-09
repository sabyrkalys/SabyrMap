import 'package:app/landmarks/composite/drafts/area_draft.dart';
import 'package:app/landmarks/drafts/metadata_patch.dart';
import 'package:app/landmarks/models/landmark_file.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../services/fixture.dart';
import '../helpers.dart';

void main() {
  late ServicesFixture f;
  late String path;
  final outline = [loc(0, 0), loc(0, 0.01), loc(0.01, 0.01), loc(0.01, 0)];
  final hole = [loc(0.002, 0.002), loc(0.002, 0.004), loc(0.004, 0.004)];
  setUp(() async {
    f = await ServicesFixture.create();
    path = await f.services.compositeCreation.createArea(AreaDraft(initialOutline: outline), loc(0, 0));
  });
  tearDown(() => f.dispose());

  test('addOutlinePoint puts the point into the outline', () async {
    final a = await f.services.areaService.addOutlinePoint(path, 0, 2, loc(0.005, 0.012));
    expect(a.polygons.single.outline[2], loc(0.005, 0.012));
    expect(a.polygons.single.outline, hasLength(5));
    expect(a.userMetadata.version, 1);
  });

  test('addHole: one more hole, area shrinks', () async {
    final before = (await f.services.areaService.load(path)).userMetadata.entries['area_m2'] as double;
    final a = await f.services.areaService.addHole(path, 0, hole);
    expect(a.polygons.single.holes, hasLength(1));
    expect(a.userMetadata.entries['area_m2'] as double, lessThan(before));
  });

  test('removeHole removes the right one', () async {
    await f.services.areaService.addHole(path, 0, hole);
    await f.services.areaService.addHole(path, 0, [loc(0.006, 0.006), loc(0.006, 0.008), loc(0.008, 0.008)]);
    final a = await f.services.areaService.removeHole(path, 0, 0);
    expect(a.polygons.single.holes.single.first, loc(0.006, 0.006));
  });

  test('move, remove and reorder outline points', () async {
    await f.services.areaService.moveOutlinePoint(path, 0, 0, loc(-0.001, -0.001));
    await f.services.areaService.reorderOutline(path, 0, 0, 3);
    final a = await f.services.areaService.removeOutlinePoint(path, 0, 0);
    expect(a.polygons.single.outline, [loc(0.01, 0.01), loc(0.01, 0), loc(-0.001, -0.001)]);
  });

  test('polygons and their metadata', () async {
    await f.services.areaService.addPolygon(path, AreaPolygon(outline: outline));
    var a = await f.services.areaService.updatePolygonMetadata(path, 1, const MetadataPatch(set: {'name': 'second'}));
    expect(a.polygons, hasLength(2));
    expect(a.polygons[1].userMetadata.name, 'second');
    a = await f.services.areaService.removePolygon(path, 0);
    expect(a.polygons.single.userMetadata.name, 'second');
    await expectLater(f.services.areaService.removePolygon(path, 3), throwsRangeError);
  });
}
