import 'package:app/theme/app_text_styles.dart';
import 'package:app/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<BuildContext> _pump(WidgetTester tester, ThemeData theme) async {
  late BuildContext captured;
  await tester.pumpWidget(
    MaterialApp(
      theme: theme,
      home: Builder(builder: (context) {
        captured = context;
        return const SizedBox();
      }),
    ),
  );
  return captured;
}

void main() {
  test('both themes use bundled Roboto with a Noto Sans fallback', () {
    for (final theme in [AppTheme.light, AppTheme.dark]) {
      expect(theme.textTheme.bodyMedium?.fontFamily, 'Roboto');
      expect(theme.textTheme.bodyMedium?.fontFamilyFallback, ['Noto Sans']);
    }
  });

  testWidgets('sectionHeader matches the spec in the light theme', (tester) async {
    final style = AppTextStyles.sectionHeader(await _pump(tester, AppTheme.light));
    expect(style.fontFamily, 'Roboto');
    expect(style.fontSize, 12);
    expect(style.fontWeight, FontWeight.w500);
    expect(style.fontStyle, FontStyle.normal);
    expect(style.letterSpacing, closeTo(0.96, 1e-9));
    expect(style.color, const Color(0xFF8A8A8E));
  });

  testWidgets('menuItem and menuItemDisabled match the spec in the light theme', (tester) async {
    final context = await _pump(tester, AppTheme.light);
    final item = AppTextStyles.menuItem(context);
    expect(item.fontSize, 16);
    expect(item.fontWeight, FontWeight.w400);
    expect(item.fontStyle, FontStyle.normal);
    expect(item.height, 1.3);
    expect(item.color, const Color(0xFF16181A));
    expect(AppTextStyles.menuItemDisabled(context).color, const Color(0xFFA0A3A8));
  });

  testWidgets('dark theme derives colors from the color scheme', (tester) async {
    final context = await _pump(tester, AppTheme.dark);
    final scheme = Theme.of(context).colorScheme;
    expect(AppTextStyles.menuItem(context).color, scheme.onSurface);
    expect(AppTextStyles.sectionHeader(context).color, scheme.onSurfaceVariant);
  });
}
