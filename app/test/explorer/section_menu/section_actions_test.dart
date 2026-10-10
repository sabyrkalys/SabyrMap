import 'dart:io';

import 'package:app/explorer/descriptors/descriptor_registry.dart';
import 'package:app/explorer/descriptors/landmark_type_descriptor.dart';
import 'package:app/explorer/section_menu/section_actions.dart';
import 'package:app/landmarks/composite/statistics/energy_estimate.dart';
import 'package:app/landmarks/explorer/listing/landmark_item.dart';
import 'package:app/landmarks/explorer/listing/sort_options.dart';
import 'package:app/landmarks/models/landmark_type.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../landmarks/services/fixture.dart';
import '../landmark_test_helpers.dart';

LandmarkItem _item(String name, {double? length, int? durationMs, double? gain, double? loss, double? maxElevation}) =>
    LandmarkItem(
      path: '/x/$name.trk',
      name: name,
      type: LandmarkType.track,
      colorValue: 0,
      createdAt: 0,
      updatedAt: 0,
      fileSizeBytes: 0,
      fileModifiedAt: DateTime(2026),
      lengthMeters: length,
      durationMs: durationMs,
      elevationGainMeters: gain,
      elevationLossMeters: loss,
      maxElevationMeters: maxElevation,
    );

void main() {
  group('statistics sorts', () {
    final items = [
      _item('flat-long', length: 20000, durationMs: 4 * 3600000, gain: 100, loss: 100, maxElevation: 900),
      _item('steep', length: 5000, durationMs: 3 * 3600000, gain: 1200, loss: 1200, maxElevation: 3100),
      _item('fast', length: 10000, durationMs: 3600000, gain: 0, loss: 0, maxElevation: 700),
      _item('empty'),
    ];
    List<String> names(SortField field) =>
        SortOptions(field: field, direction: SortDirection.descending).apply(items).map((i) => i.name).toList();

    test('max elevation, slope, speed, calories; unknown values last', () {
      expect(names(SortField.maxElevation), ['steep', 'flat-long', 'fast', 'empty']);
      expect(names(SortField.slope), ['steep', 'flat-long', 'fast', 'empty']);
      expect(names(SortField.speed), ['fast', 'flat-long', 'steep', 'empty']);
      expect(names(SortField.calories), ['flat-long', 'steep', 'fast', 'empty']);
    });

    test('energy estimate: flat part and climb part', () {
      expect(EnergyEstimate.kcal(1000), closeTo(52.5, 1e-9));
      expect(EnergyEstimate.kcal(0, gainMeters: 100), closeTo(70 * 9.81 * 100 / 0.25 / 4184, 1e-9));
    });

    test('sort encoding round-trips the new fields', () {
      for (final field in [SortField.maxElevation, SortField.slope, SortField.speed, SortField.calories]) {
        final sort = SortOptions(field: field, direction: SortDirection.descending);
        expect(SortOptions.decode(sort.encode()), sort);
      }
    });
  });

  group('section settings and bulk actions', () {
    late ServicesFixture f;
    final registry = DescriptorRegistry.buildDefault();

    setUp(() async => f = await ServicesFixture.create());
    tearDown(() => f.root.deleteSync(recursive: true));

    test('view mode: descriptor default until saved', () async {
      final s = f.services;
      final track = registry.of(LandmarkType.track);
      final files = registry.of(LandmarkType.ldkFile);
      expect(SectionActions.viewModeOf(s, track), SectionViewMode.list);
      expect(SectionActions.viewModeOf(s, files), SectionViewMode.preview);
      await SectionActions.setViewMode(s, LandmarkType.track, SectionViewMode.preview);
      expect(s.settings.getString('explorer.view_mode.trk'), 'preview');
      expect(SectionActions.viewModeOf(s, track), SectionViewMode.preview);
    });

    test('sort: falls back to the list sort until saved', () async {
      final s = f.services;
      expect(SectionActions.sortOf(s, LandmarkType.area), isNull);
      expect(SectionActions.effectiveSort(s, LandmarkType.area), s.explorerController.state.sort);
      const byArea = SortOptions(field: SortField.area, direction: SortDirection.descending);
      await SectionActions.setSort(s, LandmarkType.area, byArea);
      expect(s.settings.getString('explorer.sort.are'), 'area:descending');
      expect(SectionActions.effectiveSort(s, LandmarkType.area), byArea);
    });

    test('bulk actions touch only the section of the open folder', () async {
      final s = f.services;
      final paths = await createOneOfEach(s, f.paths.landmarks);
      await s.explorerController.openFolder(f.paths.landmarks);
      expect(SectionActions.pathsOf(s, LandmarkType.track), {paths[LandmarkType.track]});

      expect(SectionActions.showAll(s, LandmarkType.track), 'Показано на карте: 1');
      expect(s.displayRegistry.isDisplayed(paths[LandmarkType.track]!), isTrue);
      expect(s.displayRegistry.isDisplayed(paths[LandmarkType.area]!), isFalse);
      SectionActions.hideAll(s, LandmarkType.track);
      expect(s.displayRegistry.count, 0);

      expect(await SectionActions.setColorAll(s, LandmarkType.track, 0xFF1565C0), 'Цвет изменён: 1');
      expect((await s.repository.load(paths[LandmarkType.track]!)).content.userMetadata.colorValue, 0xFF1565C0);

      await SectionActions.copyAll(s, LandmarkType.set);
      expect(s.explorerController.clipboard.entries.single.sourcePath, paths[LandmarkType.set]);

      SectionActions.selectAll(s, LandmarkType.route);
      expect(s.explorerController.selection.snapshot(), {paths[LandmarkType.route]});
      SectionActions.clearSelection(s);
      expect(s.explorerController.selection.snapshot(), isEmpty);

      expect(await SectionActions.deleteAll(s, LandmarkType.area), 'Удалено: 1');
      expect(File(paths[LandmarkType.area]!).existsSync(), isFalse);
      expect(File(paths[LandmarkType.track]!).existsSync(), isTrue);
    });
  });
}
