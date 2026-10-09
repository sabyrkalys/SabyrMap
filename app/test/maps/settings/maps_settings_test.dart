import 'package:app/maps/dem/dem_settings.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

void main() {
  test('defaults', () async {
    final s = await freshMapsSettings();
    expect(s.useOnlyLocalStorage, isFalse);
    expect(s.showLocalCoverage, isFalse);
    expect(s.autoDownloadElevation, isFalse);
    expect(s.informationBox, isTrue);
    expect(s.colorRangesWidth, 5);
    expect(s.keepCacheDays, 30);
    expect(s.currentSource, isNull);
    expect(s.demSettings, const DemSettings());
  });

  test('every setter round-trips', () async {
    final s = await freshMapsSettings();
    await s.setUseOnlyLocalStorage(true);
    await s.setShowLocalCoverage(true);
    await s.setAutoDownloadElevation(true);
    await s.setInformationBox(false);
    await s.setColorRangesWidth(12);
    await s.setKeepCacheDays(7);
    await s.setCurrentSource('topo');
    expect(
      (s.useOnlyLocalStorage, s.showLocalCoverage, s.autoDownloadElevation, s.informationBox),
      (true, true, true, false),
    );
    expect((s.colorRangesWidth, s.keepCacheDays, s.currentSource), (12, 7, 'topo'));
    await s.setCurrentSource(null);
    expect(s.currentSource, isNull);
    expect(() => s.setColorRangesWidth(0), throwsArgumentError);
    expect(() => s.setKeepCacheDays(-1), throwsArgumentError);
  });

  test('DEM settings round-trip', () async {
    final s = await freshMapsSettings();
    const dem = DemSettings(useElevationData: false, autoDownload: true, useBarometric: true);
    await s.setDemSettings(dem);
    expect(s.demSettings, dem);
    expect(dem.copyWith(useBarometric: false).useBarometric, isFalse);
  });
}
