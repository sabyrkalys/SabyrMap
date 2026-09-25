import 'package:app/licenses.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the MDI sunrise/sunset icons carry their Apache-2.0 licence', () async {
    registerThirdPartyLicenses();
    final entries = await LicenseRegistry.licenses.toList();
    final mdi = entries.where((e) => e.packages.contains('Material Design Icons (sunrise, sunset)'));
    expect(mdi, isNotEmpty);
    final text = mdi.first.paragraphs.map((p) => p.text).join('\n');
    expect(text, contains('Apache License'));
    expect(text, contains('Pictogrammers'));
  });
}
