import 'package:app/intents/google_maps_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('/@lat,lon', () {
    final p = GoogleMapsParser.parse('https://www.google.com/maps/@50.4501,30.5234,15z')!;
    expect((p.location!.latitude, p.location!.longitude), (50.4501, 30.5234));
    expect(p.name, isNull);
  });

  test('?q=lat,lon and ?ll=, ?query=', () {
    expect(GoogleMapsParser.parse('https://maps.google.com/?q=50.45,30.52')!.location!.longitude, 30.52);
    expect(GoogleMapsParser.parse('http://maps.google.com/maps?ll=-33.9,18.4&z=10')!.location!.latitude, -33.9);
    expect(GoogleMapsParser.parse('https://www.google.com/maps/search/?api=1&query=47.5,19.04')!.location!.latitude, 47.5);
  });

  test('/place/<name>/@lat,lon gives the name', () {
    final p = GoogleMapsParser.parse('https://www.google.com/maps/place/Maidan+Nezalezhnosti/@50.4501,30.5234,17z')!;
    expect(p.name, 'Maidan Nezalezhnosti');
    expect(p.location!.latitude, 50.4501);
  });

  test('unknown hosts, links without coordinates and garbage give null', () {
    expect(GoogleMapsParser.parse('https://example.com/maps/@50,30'), isNull);
    expect(GoogleMapsParser.parse('https://www.google.com/search?q=50,30'), isNull);
    expect(GoogleMapsParser.parse('https://goo.gl/maps/AbCdEf'), isNull);
    expect(GoogleMapsParser.parse('https://maps.google.com/?q=Kyiv'), isNull);
    expect(GoogleMapsParser.parse('https://maps.google.com/?q=95,30'), isNull);
  });
}
