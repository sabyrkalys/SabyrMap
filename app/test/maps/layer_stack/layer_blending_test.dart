import 'package:app/maps/layer_stack/layer_blending.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('all 7 blending modes, in a fixed order', () {
    expect(LayerBlending.values.map((b) => b.name), [
      'normal',
      'multiply',
      'screen',
      'overlay',
      'darken',
      'lighten',
      'softLight',
    ]);
  });
}
