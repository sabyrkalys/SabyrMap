import 'package:app/landmarks/import_export/registry/format_capability.dart';
import 'package:app/landmarks/import_export/registry/format_descriptor.dart';
import 'package:app/landmarks/import_export/registry/format_registry.dart';
import 'package:app/landmarks/models/landmark_type.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final registry = FormatRegistry.buildDefault();

  test('the default registry has GPX, KML, CSV and GeoJSON', () {
    expect(registry.all.map((d) => d.id), ['gpx', 'kml', 'csv', 'geojson']);
  });

  test('byId and byExtension; unknown is null', () {
    expect(registry.byId('kml')!.displayName, 'KML / KMZ');
    expect(registry.byId('shp'), isNull);
    expect(registry.byExtension('GPX')!.id, 'gpx');
    expect(registry.byExtension('.kmz')!.id, 'kml');
    expect(registry.byExtension('tsv')!.id, 'csv');
    expect(registry.byExtension('json')!.id, 'geojson');
    expect(registry.byExtension('dxf'), isNull);
  });

  test('importers and exporters', () {
    expect(registry.importers.map((d) => d.id), ['gpx', 'kml', 'csv', 'geojson']);
    expect(registry.exporters.map((d) => d.id), ['gpx', 'kml', 'csv']);
    expect(registry.byId('geojson')!.canExport, isFalse);
  });

  test('forObject lists formats that can export the type', () {
    expect(registry.forObject(LandmarkType.waypoint).map((d) => d.id), ['gpx', 'kml', 'csv']);
    expect(registry.forObject(LandmarkType.area).map((d) => d.id), ['kml']);
    expect(registry.forObject(LandmarkType.set), isEmpty);
  });

  test('new formats come in through register', () {
    final custom = FormatRegistry.buildDefault()
      ..register(
        FormatDescriptor(
          id: 'plt',
          displayName: 'Track log',
          extensions: const ['.PLT'],
          capabilities: const {FormatCapability.importTrack},
        ),
      );
    expect(custom.byExtension('plt')!.id, 'plt');
    expect(custom.byId('plt')!.canImport, isFalse);
    expect(custom.byId('plt')!.supports(FormatCapability.importTrack), isTrue);
  });
}
