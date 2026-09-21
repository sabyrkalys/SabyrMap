import 'dart:io';

import 'package:app/app_icons.dart';
import 'package:app/widgets/app_icon.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('every AppIcons path points to an existing asset file', () {
    final source = File('lib/app_icons.dart').readAsStringSync();
    final names = RegExp(r"'\$_base/([\w-]+\.svg)'").allMatches(source).map((m) => m.group(1)!).toList();
    expect(names, isNotEmpty);
    for (final name in names) {
      expect(File('assets/icons/$name').existsSync(), isTrue, reason: name);
    }
  });

  testWidgets('AppIcon renders the svg and tints it with the icon theme color', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: IconTheme(
          data: IconThemeData(color: Color(0xFF123456), size: 24),
          child: Center(child: AppIcon(AppIcons.map)),
        ),
      ),
    );
    final picture = tester.widget<SvgPicture>(find.byType(SvgPicture));
    expect(picture.colorFilter, const ColorFilter.mode(Color(0xFF123456), BlendMode.srcIn));
    expect(tester.getSize(find.byType(SvgPicture)), const Size(24, 24));
  });
}
