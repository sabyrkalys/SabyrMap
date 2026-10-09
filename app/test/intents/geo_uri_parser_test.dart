import 'package:app/intents/geo_uri_parser.dart';
import 'package:app/intents/intent_kind.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('geo:55.75,37.61', () {
    final p = GeoUriParser.parse('geo:55.75,37.61')!;
    expect(p.kind, IntentKind.displayLocation);
    expect((p.location!.latitude, p.location!.longitude), (55.75, 37.61));
    expect(p.moveTo, isTrue);
  });

  test('with altitude, zoom, crs=wgs84 and a name in brackets', () {
    final p = GeoUriParser.parse('geo:55.75,37.61,150;crs=wgs84?z=12')!;
    expect(p.elevationMeters, 150);
    final named = GeoUriParser.parse('geo:55.75,37.61(Москва)')!;
    expect(named.name, 'Москва');
    final encoded = GeoUriParser.parse('geo:55.75,37.61(%D0%9C%D0%BE%D1%81%D0%BA%D0%B2%D0%B0)')!;
    expect(encoded.name, 'Москва');
  });

  test('geo:0,0?q=lat,lon(label)', () {
    final p = GeoUriParser.parse('geo:0,0?q=50.45,30.52(Kyiv+centre)')!;
    expect((p.location!.latitude, p.location!.longitude), (50.45, 30.52));
    expect(p.name, 'Kyiv centre');
  });

  test('UTM or another CRS gives null', () {
    expect(GeoUriParser.parse('geo:412345,6178901;crs=utm'), isNull);
    expect(GeoUriParser.parse('geo:1,2;crs=EPSG:3857'), isNull);
  });

  test('invalid strings give null', () {
    for (final bad in ['55.75,37.61', 'geo:', 'geo:abc', 'geo:95,30', 'http://x']) {
      expect(GeoUriParser.parse(bad), isNull, reason: bad);
    }
  });
}
