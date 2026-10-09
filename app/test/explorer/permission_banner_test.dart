import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'explorer_test_harness.dart';

void main() {
  testWidgets('no access → banner; «АКТИВИРОВАТЬ» asks; denied → SnackBar', (tester) async {
    final h = await ExplorerHarness.create(tester, denied: (h) => {h.f.paths.landmarks});
    await h.pumpApp(tester);
    expect(find.byKey(const Key('permission_banner')), findsOneWidget);
    expect(find.text('Вы не предоставили приложению право доступа к файлам.'), findsOneWidget);

    await h.tap(tester, find.byKey(const Key('permission_activate')));
    expect(h.permissions.requests, 1);
    expect(find.text('Доступ не предоставлен'), findsOneWidget);
    await h.dispose(tester);
  });

  testWidgets('with access there is no banner', (tester) async {
    final h = await ExplorerHarness.create(tester);
    await h.pumpApp(tester);
    expect(find.byKey(const Key('permission_banner')), findsNothing);
    await h.dispose(tester);
  });

  testWidgets('granted on request → the list is reloaded', (tester) async {
    final h = await ExplorerHarness.create(tester, denied: (h) => {h.f.paths.landmarks});
    h.permissions.grantOnRequest = true;
    await h.pumpApp(tester);
    await h.tap(tester, find.byKey(const Key('permission_activate')));
    expect(h.permissions.requests, 1);
    expect(find.text('Доступ не предоставлен'), findsNothing);
    await h.dispose(tester);
  });
}
