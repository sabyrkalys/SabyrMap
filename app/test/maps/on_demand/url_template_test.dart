import 'package:app/maps/file_maps/map_bounds.dart';
import 'package:app/maps/on_demand/url_template.dart';
import 'package:app/maps/on_demand/url_variable.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('x, y, z', () {
    final t = UrlTemplate(r'https://tiles.example/{$z}/{$x}/{$y}.png');
    expect(t.resolve(x: 3, y: 5, z: 4), 'https://tiles.example/4/3/5.png');
    expect(t.usedVariables, {UrlVariable.x, UrlVariable.y, UrlVariable.z});
  });

  test('TMS y = 2^z − 1 − y', () {
    expect(UrlTemplate(r'/{$z}/{$x}/{$!y}').resolve(x: 3, y: 5, z: 4), '/4/3/10');
  });

  test('quadkey', () {
    expect(UrlTemplate(r'/q{$q}').resolve(x: 3, y: 5, z: 3), '/q213');
    expect(UrlTemplate.quadKey(0, 0, 1), '0');
    expect(UrlTemplate.quadKey(1, 1, 1), '3');
  });

  test('bbox and ibbox', () {
    final t = UrlTemplate(r'/wms?bbox={$bbox}&i={$ibbox}');
    expect(
      t.resolve(x: 0, y: 0, z: 0, bbox: const MapBounds(northLat: 51, southLat: 50, westLon: 30, eastLon: 31)),
      '/wms?bbox=30,50,31,51&i=50,30,51,31',
    );
    final world = t.resolve(x: 0, y: 0, z: 0);
    expect(world, startsWith('/wms?bbox=-180,-85.0511288,180,85.0511288'));
  });

  test('params from the map; missing ones are empty', () {
    final t = UrlTemplate(r'/{$param:layer}/{$z}?k={$param:key}');
    expect(t.resolve(x: 0, y: 0, z: 2, params: {'layer': 'topo'}), '/topo/2?k=');
    expect(t.usedVariables, containsAll([UrlVariable.param, UrlVariable.z]));
  });
}
