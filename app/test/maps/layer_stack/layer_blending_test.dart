import 'package:app/maps/layer_stack/layer_blending.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('6 blending modes, in the order of the menu', () {
    expect(LayerBlending.values.map((b) => b.name), [
      'normal',
      'lighten',
      'screen',
      'overlay',
      'multiply',
      'darken',
    ]);
  });
}
