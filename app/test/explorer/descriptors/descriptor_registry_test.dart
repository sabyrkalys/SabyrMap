import 'package:app/explorer/descriptors/descriptor_registry.dart';
import 'package:app/explorer/descriptors/landmark_type_descriptor.dart';
import 'package:app/landmarks/models/landmark_type.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final registry = DescriptorRegistry.buildDefault();

  test('buildDefault registers all six types', () {
    expect(registry.all.map((d) => d.type).toSet(), LandmarkType.values.toSet());
    expect(registry.all, hasLength(6));
  });

  test('byType returns the matching descriptor', () {
    for (final type in LandmarkType.values) {
      expect(registry.byType(type)!.type, type);
      expect(registry.of(type).type, type);
    }
    expect(DescriptorRegistry().byType(LandmarkType.track), isNull);
    expect(() => DescriptorRegistry().of(LandmarkType.track), throwsStateError);
  });

  test('every descriptor has titles, an icon and the builders', () {
    for (final d in registry.all) {
      expect(d.sectionTitle, isNotEmpty, reason: d.type.name);
      expect(d.sectionTitle, d.sectionTitle.toUpperCase());
      expect(d.displayName, isNotEmpty);
      expect(d.icon, isA<IconData>());
      expect(d.buildItemMenu, isNotNull);
      expect(d.buildSectionMenu, isNotNull);
      expect(d.buildDetailsSections, isNotNull);
    }
  });

  test('section titles and menu titles', () {
    expect(registry.of(LandmarkType.track).sectionTitle, 'ТРЕКИ');
    expect(registry.of(LandmarkType.track).sectionMenuTitle, 'Треки');
    expect(registry.of(LandmarkType.set).sectionMenuTitle, 'Наборы точек');
    expect(registry.of(LandmarkType.area).sectionMenuTitle, 'Области');
    expect(registry.of(LandmarkType.ldkFile).sectionMenuTitle, 'Файлы меток');
  });

  test('only landmark files lack coordinates and default to preview', () {
    for (final d in registry.all) {
      expect(d.hasLocation, d.type != LandmarkType.ldkFile, reason: d.type.name);
      expect(d.defaultViewMode, d.type == LandmarkType.ldkFile ? SectionViewMode.preview : SectionViewMode.list);
    }
  });

  test('a later registration replaces the earlier one', () {
    final r = DescriptorRegistry.buildDefault();
    final track = r.of(LandmarkType.track);
    r.register(
      LandmarkTypeDescriptor(
        type: LandmarkType.track,
        displayName: 'Трек',
        sectionTitle: 'ТРЕКИ 2',
        icon: Icons.abc,
        iconColor: 0,
        buildItemMenu: track.buildItemMenu,
        buildSectionMenu: track.buildSectionMenu,
        buildDetailsSections: track.buildDetailsSections,
      ),
    );
    expect(r.of(LandmarkType.track).sectionTitle, 'ТРЕКИ 2');
    expect(r.all, hasLength(6));
  });
}
