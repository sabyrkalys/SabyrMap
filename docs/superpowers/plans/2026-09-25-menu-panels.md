# Menu Panels Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Every bottom-nav icon opens a floating, blurred panel over an always-visible map; five panels (НАСТРОЙКИ, КАРТЫ, МЕТКИ, ПОЗИЦИОНИРОВАНИЕ, ОРИЕНТИРОВАНИЕ) are built from shared components, with persisted checkbox/switch state.

**Architecture:** `lib/menu/` holds the persisted toggle state (`menu_toggles.dart`), the shared widgets (`menu_widgets.dart`) and the five panel contents (`menu_panels.dart`). `HomeShell` keeps `MapScreen` permanently mounted and overlays the open panel plus a tap-to-close barrier. Waypoint creation at the crosshair moves into a shared action fed by a crosshair provider so both the map FAB and the МЕТКИ panel use it.

**Tech Stack:** Flutter 3.35.5, flutter_riverpod 3.x (`Notifier`), flutter_secure_storage 10 (`FlutterSecureStorage.setMockInitialValues` in tests), maplibre_gl `LatLng`.

**Spec:** `docs/superpowers/specs/2026-09-25-menu-panels-design.md`

## Global Constraints

- All labels exactly as in the spec (Russian, section titles and panel titles UPPER CASE: `НАСТРОЙКИ`, `КАРТЫ`, `МЕТКИ`, `ПОЗИЦИОНИРОВАНИЕ`, `ОРИЕНТИРОВАНИЕ`, `ОПЦИИ`, `ИНФОРМЕРЫ`). Do not invent or rename any label.
- Panel background: `Colors.white` at alpha 0.85 + `BackdropFilter` blur sigma 10; max width 400 dp; thin grey dividers between sections.
- Sections start collapsed; tapping a section header toggles it.
- Placeholder items (no action) use `AppTextStyles.menuItemDisabled`; items with an action use `AppTextStyles.menuItem`.
- Nav: nothing selected at launch; same icon again or tapping the map closes; another icon switches.
- Compass icon label: `Ориентирование`.
- Run Flutter commands from `app/`. Local test runs are slow on this 8 GB machine; always pass `--timeout 60s`.
- Commit messages end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Review Focus

1. Landscape phone (short height): the panel must scroll instead of overflowing — test in Task 2 pumps the panel into a 800x300 surface and expects no overflow.
2. A tap on the map while a panel is open must close the panel and not reach the map — Task 5 barrier test.
3. Leaving `CompassScreen` via system back must turn the «Компас» switch off again — Task 4 pops the route and checks the switch.
4. Corrupt or partial saved toggle data must not crash the app and must fall back to defaults per key — Task 1 tests both.
5. «Новая метка» before the map has settled once must show «Карта ещё не готова», not throw — Task 3 test with a null crosshair.

---

### Task 1: Persisted menu toggle state

**Files:**
- Create: `app/lib/menu/menu_toggles.dart`
- Test: `app/test/menu/menu_toggles_test.dart`

**Interfaces:**
- Produces: `enum MenuToggle` (values below, `.defaultValue`), `abstract class MenuTogglesStore { Future<Map<String, bool>> load(); Future<void> save(Map<String, bool> values); }`, `SecureMenuTogglesStore`, `menuTogglesStoreProvider`, `menuTogglesProvider` (`NotifierProvider<MenuTogglesController, Map<MenuToggle, bool>>`), `MenuTogglesController.set(MenuToggle, bool)`.

- [ ] **Step 1: Write the failing test**

```dart
import 'package:app/menu/menu_toggles.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

class _MemoryStore implements MenuTogglesStore {
  _MemoryStore([Map<String, bool>? initial]) : saved = {...?initial};
  Map<String, bool> saved;
  @override
  Future<Map<String, bool>> load() async => {...saved};
  @override
  Future<void> save(Map<String, bool> values) async => saved = {...values};
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  ProviderContainer containerWith(MenuTogglesStore store) {
    final container = ProviderContainer(overrides: [menuTogglesStoreProvider.overrideWithValue(store)]);
    addTearDown(container.dispose);
    return container;
  }

  test('starts with the mockup defaults', () {
    final state = containerWith(_MemoryStore()).read(menuTogglesProvider);
    expect(state[MenuToggle.waypointsNames], isTrue);
    expect(state[MenuToggle.positioningRotateByMovement], isFalse);
    expect(state[MenuToggle.orientationRotateByCompass], isTrue);
    expect(state[MenuToggle.orientationShowCompass], isFalse);
    expect(state.length, MenuToggle.values.length);
  });

  test('saved values override defaults once loaded; unknown keys are ignored', () async {
    final container = containerWith(_MemoryStore({'waypointsNames': false, 'noSuchToggle': true}));
    container.read(menuTogglesProvider);
    await Future<void>.delayed(Duration.zero);
    final state = container.read(menuTogglesProvider);
    expect(state[MenuToggle.waypointsNames], isFalse);
    expect(state[MenuToggle.waypointsTargetLine], isTrue);
  });

  test('set updates state and saves every value by name', () async {
    final store = _MemoryStore();
    final container = containerWith(store);
    container.read(menuTogglesProvider);
    await Future<void>.delayed(Duration.zero);

    container.read(menuTogglesProvider.notifier).set(MenuToggle.mapsScaleBar, true);
    await Future<void>.delayed(Duration.zero);

    expect(container.read(menuTogglesProvider)[MenuToggle.mapsScaleBar], isTrue);
    expect(store.saved['mapsScaleBar'], isTrue);
    expect(store.saved.length, MenuToggle.values.length);
  });

  group('SecureMenuTogglesStore', () {
    test('round-trips values', () async {
      FlutterSecureStorage.setMockInitialValues({});
      await SecureMenuTogglesStore().save({'a': true, 'b': false});
      expect(await SecureMenuTogglesStore().load(), {'a': true, 'b': false});
    });

    test('corrupt data loads as empty', () async {
      FlutterSecureStorage.setMockInitialValues({'menu_toggles': 'not json'});
      expect(await SecureMenuTogglesStore().load(), isEmpty);
    });

    test('non-bool entries are skipped', () async {
      FlutterSecureStorage.setMockInitialValues({'menu_toggles': '{"a": true, "b": 3}'});
      expect(await SecureMenuTogglesStore().load(), {'a': true});
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/menu/menu_toggles_test.dart --timeout 60s`
Expected: compile error, `menu_toggles.dart` does not exist.

- [ ] **Step 3: Write the implementation**

```dart
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Every persisted checkbox/switch in the menu panels, with its default
/// from the mockup. Values are saved by [Enum.name], so renaming a value
/// resets it to its default.
enum MenuToggle {
  settingsSk42Grid(false),
  settingsNightMode(false),
  settingsCenterCoordinates(false),
  mapsCacheOnly(false),
  mapsLoadingIndicators(false),
  mapsMapName(false),
  mapsMapScale(false),
  mapsScaleBar(false),
  waypointsNames(true),
  waypointsTargetLine(true),
  waypointsTargetStatus(true),
  positioningGeolocation(false),
  positioningRotateByMovement(false),
  positioningDistanceLine(true),
  positioningStatus(true),
  positioningRecordingStatus(true),
  orientationRotateByCompass(true),
  orientationShowCompass(false),
  orientationCompassStatus(true);

  const MenuToggle(this.defaultValue);

  final bool defaultValue;
}

abstract class MenuTogglesStore {
  Future<Map<String, bool>> load();
  Future<void> save(Map<String, bool> values);
}

/// Local-only, like the map camera and waypoint icon assignments.
class SecureMenuTogglesStore implements MenuTogglesStore {
  SecureMenuTogglesStore([FlutterSecureStorage? storage]) : _storage = storage ?? const FlutterSecureStorage();

  static const _key = 'menu_toggles';

  final FlutterSecureStorage _storage;

  @override
  Future<Map<String, bool>> load() async {
    final raw = await _storage.read(key: _key);
    if (raw == null) return {};
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      return {
        for (final entry in json.entries)
          if (entry.value is bool) entry.key: entry.value as bool,
      };
    } catch (_) {
      return {};
    }
  }

  @override
  Future<void> save(Map<String, bool> values) => _storage.write(key: _key, value: jsonEncode(values));
}

final menuTogglesStoreProvider = Provider<MenuTogglesStore>((ref) => SecureMenuTogglesStore());

/// Starts from the defaults and applies saved values once they are read. A
/// toggle the user changes before the read finishes keeps the user's value.
class MenuTogglesController extends Notifier<Map<MenuToggle, bool>> {
  final Set<MenuToggle> _changedBeforeLoad = {};

  @override
  Map<MenuToggle, bool> build() {
    _load();
    return {for (final toggle in MenuToggle.values) toggle: toggle.defaultValue};
  }

  Future<void> _load() async {
    final Map<String, bool> saved;
    try {
      saved = await ref.read(menuTogglesStoreProvider).load();
    } catch (_) {
      return;
    }
    final next = {...state};
    for (final toggle in MenuToggle.values) {
      final value = saved[toggle.name];
      if (value != null && !_changedBeforeLoad.contains(toggle)) next[toggle] = value;
    }
    state = next;
  }

  void set(MenuToggle toggle, bool value) {
    _changedBeforeLoad.add(toggle);
    state = {...state, toggle: value};
    ref
        .read(menuTogglesStoreProvider)
        .save({for (final entry in state.entries) entry.key.name: entry.value})
        .catchError((_) {});
  }
}

final menuTogglesProvider = NotifierProvider<MenuTogglesController, Map<MenuToggle, bool>>(MenuTogglesController.new);
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/menu/menu_toggles_test.dart --timeout 60s`
Expected: all 6 tests pass.

- [ ] **Step 5: Commit**

```bash
git add app/lib/menu/menu_toggles.dart app/test/menu/menu_toggles_test.dart
git commit -m "feat(app): persisted menu toggle state"
```

---

### Task 2: Shared menu widgets

**Files:**
- Create: `app/lib/menu/menu_widgets.dart`
- Test: `app/test/menu/menu_widgets_test.dart`

**Interfaces:**
- Consumes: `AppIcons`, `AppIcon`, `AppTextStyles` (existing).
- Produces:
  - `MenuPanel({Key? key, required String title, required List<Widget> items, List<MenuSection> sections = const [], required double arrowCenterX})` — keys inside: `menu_panel_card`, `menu_panel_arrow`, `menu_panel_help`.
  - `MenuListItem({Key? key, required String icon, required String label, VoidCallback? onTap})` — `onTap == null` renders the disabled placeholder style.
  - `MenuSwitchItem({Key? key, String? icon, required String label, required bool value, required ValueChanged<bool> onChanged})`.
  - `MenuCheckboxItem({Key? key, required String label, required bool value, required ValueChanged<bool> onChanged})`.
  - `MenuSection({Key? key, required String title, required List<Widget> children})` — header key `menu_section_<title>`.
  - `MenuPanel.arrowWidth = 16`, `MenuPanel.arrowHeight = 8`, `MenuPanel.maxWidth = 400`.

- [ ] **Step 1: Write the failing test**

```dart
import 'dart:ui';

import 'package:app/app_icons.dart';
import 'package:app/menu/menu_widgets.dart';
import 'package:app/theme/app_text_styles.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pump(WidgetTester tester, Widget panel) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: Align(alignment: Alignment.bottomLeft, child: panel))));
  }

  MenuPanel samplePanel({VoidCallback? onTap, ValueChanged<bool>? onChecked, bool checked = false}) {
    return MenuPanel(
      title: 'МЕТКИ',
      arrowCenterX: 75,
      items: [
        MenuListItem(icon: AppIcons.flag, label: 'Все метки', onTap: onTap),
        const MenuListItem(icon: AppIcons.search, label: 'Поиск на карте'),
      ],
      sections: [
        MenuSection(title: 'ОПЦИИ', children: [
          MenuCheckboxItem(label: 'Названия меток', value: checked, onChanged: onChecked ?? (_) {}),
        ]),
        const MenuSection(title: 'ИНФОРМЕРЫ', children: []),
      ],
    );
  }

  testWidgets('shows the title, help button, items and section headers; sections start collapsed', (tester) async {
    await pump(tester, samplePanel());

    expect(find.text('МЕТКИ'), findsOneWidget);
    expect(find.byKey(const Key('menu_panel_help')), findsOneWidget);
    expect(find.text('Все метки'), findsOneWidget);
    expect(find.text('ОПЦИИ'), findsOneWidget);
    expect(find.text('ИНФОРМЕРЫ'), findsOneWidget);
    expect(find.text('Названия меток'), findsNothing);
  });

  testWidgets('tapping a section header expands and collapses it', (tester) async {
    await pump(tester, samplePanel());

    await tester.tap(find.byKey(const Key('menu_section_ОПЦИИ')));
    await tester.pumpAndSettle();
    expect(find.text('Названия меток'), findsOneWidget);

    await tester.tap(find.byKey(const Key('menu_section_ОПЦИИ')));
    await tester.pumpAndSettle();
    expect(find.text('Названия меток'), findsNothing);
  });

  testWidgets('items with an action use the normal style, placeholders the disabled style', (tester) async {
    var taps = 0;
    await pump(tester, samplePanel(onTap: () => taps++));

    final context = tester.element(find.text('Все метки'));
    expect(tester.widget<Text>(find.text('Все метки')).style, AppTextStyles.menuItem(context));
    expect(tester.widget<Text>(find.text('Поиск на карте')).style, AppTextStyles.menuItemDisabled(context));

    await tester.tap(find.text('Все метки'));
    expect(taps, 1);
  });

  testWidgets('checkbox reports changes', (tester) async {
    bool? reported;
    await pump(tester, samplePanel(onChecked: (v) => reported = v));
    await tester.tap(find.byKey(const Key('menu_section_ОПЦИИ')));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Названия меток'));
    expect(reported, isTrue);
  });

  testWidgets('switch item reports changes', (tester) async {
    bool? reported;
    await pump(
      tester,
      MenuPanel(
        title: 'ОРИЕНТИРОВАНИЕ',
        arrowCenterX: 225,
        items: [MenuSwitchItem(icon: AppIcons.compass, label: 'Компас', value: false, onChanged: (v) => reported = v)],
      ),
    );

    await tester.tap(find.byType(Switch));
    expect(reported, isTrue);
  });

  testWidgets('background is 85% white with a 10 px blur, width capped at 400', (tester) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await pump(tester, samplePanel());

    final card = find.byKey(const Key('menu_panel_card'));
    expect(tester.getSize(card).width, 400);
    final material = tester.widget<Material>(find.descendant(of: card, matching: find.byType(Material)).first);
    expect(material.color, Colors.white.withValues(alpha: 0.85));
    final filter = tester.widget<BackdropFilter>(find.descendant(of: card, matching: find.byType(BackdropFilter)));
    expect(filter.filter, ImageFilter.blur(sigmaX: 10, sigmaY: 10));
  });

  testWidgets('arrow is centered at arrowCenterX', (tester) async {
    await pump(tester, samplePanel());

    final arrow = find.byKey(const Key('menu_panel_arrow'));
    expect(tester.getSize(arrow), const Size(16, 8));
    expect(tester.getCenter(arrow).dx, 75);
  });

  testWidgets('scrolls instead of overflowing on a short landscape screen', (tester) async {
    tester.view.physicalSize = const Size(800, 300);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await pump(tester, samplePanel());
    await tester.tap(find.byKey(const Key('menu_section_ОПЦИИ')));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(SingleChildScrollView), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/menu/menu_widgets_test.dart --timeout 60s`
Expected: compile error, `menu_widgets.dart` does not exist.

- [ ] **Step 3: Write the implementation**

```dart
import 'dart:ui';

import 'package:flutter/material.dart';

import '../app_icons.dart';
import '../theme/app_text_styles.dart';
import '../widgets/app_icon.dart';

const double _itemHeight = 52;
const double _headerHeight = 48;
const double _iconSize = 24;
const double _horizontalPadding = 16;
const double _iconTextGap = 16;
const Color _dividerColor = Color(0xFFDADCE0);

/// Floating menu panel shown over the map: a title with a help button,
/// the main items, then collapsible sections, and a down-arrow pointing at
/// the nav icon that opened it. Scrolls when taller than the space it gets.
class MenuPanel extends StatelessWidget {
  const MenuPanel({
    super.key,
    required this.title,
    required this.items,
    this.sections = const [],
    required this.arrowCenterX,
  });

  static const double arrowWidth = 16;
  static const double arrowHeight = 8;
  static const double maxWidth = 400;
  static final Color background = Colors.white.withValues(alpha: 0.85);

  final String title;
  final List<Widget> items;
  final List<MenuSection> sections;

  /// Horizontal center of the arrow, from the panel's left edge.
  final double arrowCenterX;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: maxWidth),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Flexible(
            child: ClipRRect(
              key: const Key('menu_panel_card'),
              borderRadius: BorderRadius.circular(12),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                child: Material(
                  color: background,
                  child: SingleChildScrollView(
                    child: AnimatedSize(
                      duration: const Duration(milliseconds: 200),
                      curve: Curves.easeOut,
                      alignment: Alignment.bottomCenter,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _PanelHeader(title: title),
                          ...items,
                          for (final section in sections) ...[
                            const Divider(height: 1, thickness: 0.5, color: _dividerColor),
                            section,
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.only(left: arrowCenterX - arrowWidth / 2),
            child: CustomPaint(
              key: const Key('menu_panel_arrow'),
              size: const Size(arrowWidth, arrowHeight),
              painter: _DownArrowPainter(background),
            ),
          ),
        ],
      ),
    );
  }
}

class _PanelHeader extends StatelessWidget {
  const _PanelHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final style = AppTextStyles.sectionHeader(context);
    return SizedBox(
      height: _headerHeight,
      child: Padding(
        padding: const EdgeInsets.only(left: _horizontalPadding, right: 4),
        child: Row(
          children: [
            Expanded(child: Text(title, style: style)),
            // Help content is not designed yet.
            IconButton(
              key: const Key('menu_panel_help'),
              onPressed: null,
              icon: AppIcon(AppIcons.helpCircle, size: _iconSize, color: style.color),
            ),
          ],
        ),
      ),
    );
  }
}

/// Icon + label row. Without [onTap] it is a placeholder in the disabled style.
class MenuListItem extends StatelessWidget {
  const MenuListItem({super.key, required this.icon, required this.label, this.onTap});

  final String icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final style = onTap == null ? AppTextStyles.menuItemDisabled(context) : AppTextStyles.menuItem(context);
    return InkWell(
      onTap: onTap,
      child: _MenuRow(
        leading: AppIcon(icon, size: _iconSize, color: style.color),
        label: Text(label, style: style),
      ),
    );
  }
}

class MenuSwitchItem extends StatelessWidget {
  const MenuSwitchItem({super.key, this.icon, required this.label, required this.value, required this.onChanged});

  final String? icon;
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final style = AppTextStyles.menuItem(context);
    final icon = this.icon;
    return InkWell(
      onTap: () => onChanged(!value),
      child: _MenuRow(
        leading: icon == null ? null : AppIcon(icon, size: _iconSize, color: style.color),
        label: Text(label, style: style),
        trailing: Switch(value: value, onChanged: onChanged),
      ),
    );
  }
}

class MenuCheckboxItem extends StatelessWidget {
  const MenuCheckboxItem({super.key, required this.label, required this.value, required this.onChanged});

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => onChanged(!value),
      child: _MenuRow(
        label: Text(label, style: AppTextStyles.menuItem(context)),
        trailing: Checkbox(value: value, onChanged: (v) => onChanged(v ?? false)),
      ),
    );
  }
}

/// Collapsible section: an upper-case title with a gear icon; tapping the
/// header shows or hides [children]. Starts collapsed.
class MenuSection extends StatefulWidget {
  const MenuSection({super.key, required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  State<MenuSection> createState() => _MenuSectionState();
}

class _MenuSectionState extends State<MenuSection> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final style = AppTextStyles.sectionHeader(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          key: Key('menu_section_${widget.title}'),
          onTap: () => setState(() => _expanded = !_expanded),
          child: SizedBox(
            height: _headerHeight,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: _horizontalPadding),
              child: Row(
                children: [
                  Expanded(child: Text(widget.title, style: style)),
                  AppIcon(AppIcons.gear, size: _iconSize, color: style.color),
                ],
              ),
            ),
          ),
        ),
        if (_expanded) ...widget.children,
      ],
    );
  }
}

class _MenuRow extends StatelessWidget {
  const _MenuRow({this.leading, required this.label, this.trailing});

  final Widget? leading;
  final Widget label;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final leading = this.leading;
    final trailing = this.trailing;
    return SizedBox(
      height: _itemHeight,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: _horizontalPadding),
        child: Row(
          children: [
            if (leading != null) ...[leading, const SizedBox(width: _iconTextGap)],
            Expanded(child: label),
            if (trailing != null) ...[const SizedBox(width: _iconTextGap), trailing],
          ],
        ),
      ),
    );
  }
}

class _DownArrowPainter extends CustomPainter {
  const _DownArrowPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width / 2, size.height)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_DownArrowPainter oldDelegate) => oldDelegate.color != color;
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/menu/menu_widgets_test.dart --timeout 60s`
Expected: all 8 tests pass. If the width test fails because `ClipRRect` is not the widest box, check that `Align` in the test gives loose constraints (it does) and that the `Column` uses `CrossAxisAlignment.start` with `ConstrainedBox` max 400 — the card must fill the 400 cap on a 1600 px screen; if it shrinks to content, wrap the `Flexible` child in `SizedBox(width: double.infinity, ...)`.

- [ ] **Step 5: Commit**

```bash
git add app/lib/menu/menu_widgets.dart app/test/menu/menu_widgets_test.dart
git commit -m "feat(app): shared menu panel widgets"
```

---

### Task 3: Shared «create waypoint at crosshair» action

**Files:**
- Create: `app/lib/map/map_crosshair.dart`
- Create: `app/lib/waypoints/waypoint_create_action.dart`
- Modify: `app/lib/map/map_screen.dart` (`_onCameraIdle`, `_createWaypointAtCrosshair` → removed, FAB `onPressed`)
- Test: `app/test/waypoints/waypoint_create_action_test.dart`

**Interfaces:**
- Produces: `mapCrosshairProvider` (`NotifierProvider<MapCrosshair, LatLng?>`, `MapCrosshair.set(LatLng)`); `Future<void> createWaypointAtCrosshair(BuildContext context, WidgetRef ref, {IconLibraryScanner? iconScanner})`.

- [ ] **Step 1: Write the failing test**

```dart
import 'package:app/map/map_crosshair.dart';
import 'package:app/waypoints/waypoint_create_action.dart';
import 'package:app/waypoints/waypoints_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../waypoints/fakes.dart';

void main() {
  Future<ProviderContainer> pumpButton(WidgetTester tester) async {
    final container = ProviderContainer(
      overrides: [waypointsRepositoryProvider.overrideWithValue(FakeWaypointsRepository())],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) => TextButton(
                onPressed: () => createWaypointAtCrosshair(context, ref),
                child: const Text('go'),
              ),
            ),
          ),
        ),
      ),
    );
    return container;
  }

  testWidgets('before the map has settled it reports the map is not ready', (tester) async {
    await pumpButton(tester);

    await tester.tap(find.text('go'));
    await tester.pump();

    expect(find.text('Карта ещё не готова'), findsOneWidget);
  });

  testWidgets('with a crosshair position it opens the waypoint form', (tester) async {
    final container = await pumpButton(tester);
    container.read(mapCrosshairProvider.notifier).set(const LatLng(48, 37.8));

    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('waypoint_name_field')), findsOneWidget);
  });
}
```

Before writing this test, confirm the name field key: `grep -n "Key('waypoint_" app/lib/waypoints/waypoint_form_sheet.dart`, and use the key of the name `TextField` found there. Add `import 'package:maplibre_gl/maplibre_gl.dart';` for `LatLng`.

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/waypoints/waypoint_create_action_test.dart --timeout 60s`
Expected: compile error, files do not exist.

- [ ] **Step 3: Write the implementation**

`app/lib/map/map_crosshair.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

/// Where the map's crosshair last settled; null until the map settles once.
/// Published by MapScreen so actions outside it (the МЕТКИ panel) can use it.
class MapCrosshair extends Notifier<LatLng?> {
  @override
  LatLng? build() => null;

  void set(LatLng position) => state = position;
}

final mapCrosshairProvider = NotifierProvider<MapCrosshair, LatLng?>(MapCrosshair.new);
```

`app/lib/waypoints/waypoint_create_action.dart` — the body is the current `MapScreen._createWaypointAtCrosshair`, moved and reading the crosshair from the provider:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../icons/icon_library_scanner.dart';
import '../icons/waypoint_icon_assignments_controller.dart';
import '../map/map_crosshair.dart';
import 'waypoint_form_sheet.dart';
import 'waypoint_models.dart';
import 'waypoints_controller.dart';

/// Opens the new-waypoint form and creates the waypoint at the map's
/// crosshair. Shared by the map's «Метка здесь» button and the МЕТКИ panel.
Future<void> createWaypointAtCrosshair(BuildContext context, WidgetRef ref, {IconLibraryScanner? iconScanner}) async {
  final coordinates = ref.read(mapCrosshairProvider);
  if (coordinates == null) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Карта ещё не готова')));
    return;
  }
  final result = await showWaypointFormSheet(context, iconScanner: iconScanner);
  if (result == null || !context.mounted) return;
  try {
    final created = await ref.read(waypointsControllerProvider.notifier).createWaypoint(
          name: result.name,
          type: result.type,
          note: result.note,
          color: result.color,
          lat: coordinates.latitude,
          lng: coordinates.longitude,
        );
    try {
      await ref.read(waypointIconAssignmentsControllerProvider.notifier).setIcon(created.id, result.iconFileName);
    } catch (_) {
      // The waypoint itself was created; a local icon-bookkeeping failure
      // is a soft failure and shouldn't be reported as a failed creation.
      // Same reasoning as editWaypoint/deleteWaypoint in waypoint_actions.dart.
    }
  } on WaypointException catch (e) {
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
  }
}
```

Check where `WaypointException` is declared (`grep -rn "class WaypointException" app/lib`) and import that file instead of `waypoint_models.dart` if it differs.

In `app/lib/map/map_screen.dart`:
- Add imports `../map/map_crosshair.dart` → `'map_crosshair.dart'` and `'../waypoints/waypoint_create_action.dart'`.
- In `_onCameraIdle`, after `setState(...)`, add `ref.read(mapCrosshairProvider.notifier).set(position.target);`.
- Delete the whole `_createWaypointAtCrosshair` method.
- FAB: `onPressed: () => createWaypointAtCrosshair(context, ref, iconScanner: _iconLibraryScanner),`.
- Remove imports that become unused (`flutter analyze` lists them).

- [ ] **Step 4: Run tests**

Run: `flutter test test/waypoints/waypoint_create_action_test.dart test/map --timeout 60s`
Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add app/lib/map/map_crosshair.dart app/lib/waypoints/waypoint_create_action.dart app/lib/map/map_screen.dart app/test/waypoints/waypoint_create_action_test.dart
git commit -m "refactor(app): share create-waypoint-at-crosshair action"
```

---

### Task 4: The five panel contents

**Files:**
- Create: `app/lib/menu/menu_panels.dart`
- Test: `app/test/menu/menu_panels_test.dart`

**Interfaces:**
- Consumes: Task 1 (`MenuToggle`, `menuTogglesProvider`), Task 2 widgets, Task 3 `createWaypointAtCrosshair`, existing `toggleTrackRecording`, `trackRecordingControllerProvider`, `TrackRecordingActive`, `WaypointsListScreen`, `CompassScreen`.
- Produces: `enum MenuTab { settings, maps, waypoints, positioning, orientation }` and `Widget menuPanelFor(MenuTab tab, {required double arrowCenterX})`.

- [ ] **Step 1: Write the failing test**

```dart
import 'package:app/compass/compass_screen.dart';
import 'package:app/compass/compass_source.dart';
import 'package:app/menu/menu_panels.dart';
import 'package:app/menu/menu_toggles.dart';
import 'package:app/tracks/track_models.dart';
import 'package:app/tracks/track_recording_controller.dart';
import 'package:app/tracks/tracks_controller.dart';
import 'package:app/waypoints/waypoints_controller.dart';
import 'package:app/waypoints/waypoints_list_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../compass/fakes.dart';
import '../tracks/fake_location_source.dart';
import '../tracks/fakes.dart';
import '../waypoints/fakes.dart';

class _MemoryStore implements MenuTogglesStore {
  Map<String, bool> saved = {};
  @override
  Future<Map<String, bool>> load() async => {...saved};
  @override
  Future<void> save(Map<String, bool> values) async => saved = {...values};
}

void main() {
  Future<ProviderContainer> pumpPanel(
    WidgetTester tester,
    MenuTab tab, {
    FakeLocationSource? locationSource,
    FakeTracksRepository? tracksRepo,
  }) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    final container = ProviderContainer(
      overrides: [
        menuTogglesStoreProvider.overrideWithValue(_MemoryStore()),
        waypointsRepositoryProvider.overrideWithValue(FakeWaypointsRepository()),
        tracksRepositoryProvider.overrideWithValue(tracksRepo ?? FakeTracksRepository()),
        compassSourceProvider.overrideWithValue(FakeUnavailableCompassSource()),
        if (locationSource != null) locationSourceProvider.overrideWithValue(locationSource),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(body: Align(alignment: Alignment.bottomLeft, child: menuPanelFor(tab, arrowCenterX: 25))),
        ),
      ),
    );
    await tester.pump();
    return container;
  }

  Future<void> expand(WidgetTester tester, String section) async {
    await tester.tap(find.byKey(Key('menu_section_$section')));
    await tester.pumpAndSettle();
  }

  void expectTexts(List<String> texts) {
    for (final text in texts) {
      expect(find.text(text), findsOneWidget, reason: text);
    }
  }

  testWidgets('НАСТРОЙКИ content', (tester) async {
    await pumpPanel(tester, MenuTab.settings);
    expectTexts(['НАСТРОЙКИ', 'Скрыть кнопки меню', 'Блокировка экрана', 'Снимок экрана', 'Настройки', 'ОПЦИИ']);
    await expand(tester, 'ОПЦИИ');
    expectTexts(['Координатная сетка СК-42 (Гаусса-Крюгера)', 'Ночной режим', 'Координаты центра экрана']);
  });

  testWidgets('КАРТЫ content', (tester) async {
    await pumpPanel(tester, MenuTab.maps);
    expectTexts(['КАРТЫ', 'Доступные карты', 'Карты на экране', 'Сохранить участок карты', 'Избранные карты', 'ОПЦИИ']);
    await expand(tester, 'ОПЦИИ');
    expectTexts([
      'Использовать только сохранённый кэш карты',
      'Индикаторы загрузки карты',
      'Название карты',
      'Масштаб карты',
      'Масштабная линейка',
    ]);
  });

  testWidgets('МЕТКИ content', (tester) async {
    await pumpPanel(tester, MenuTab.waypoints);
    expectTexts(['МЕТКИ', 'Все метки', 'Метки на экране', 'Новая метка', 'Поиск на карте', 'ОПЦИИ', 'ИНФОРМЕРЫ']);
    await expand(tester, 'ОПЦИИ');
    await expand(tester, 'ИНФОРМЕРЫ');
    expectTexts(['Названия меток', 'Линия до цели', 'Статус цели']);
  });

  testWidgets('ПОЗИЦИОНИРОВАНИЕ content', (tester) async {
    await pumpPanel(tester, MenuTab.positioning);
    expectTexts(['ПОЗИЦИОНИРОВАНИЕ', 'Путевой компьютер', 'Геолокация', 'Запись трека', 'ОПЦИИ', 'ИНФОРМЕРЫ']);
    await expand(tester, 'ОПЦИИ');
    await expand(tester, 'ИНФОРМЕРЫ');
    expectTexts(['Вращать карту по движению', 'Линия расстояния', 'Статус позиционирования', 'Статус записи трека']);
  });

  testWidgets('ОРИЕНТИРОВАНИЕ content', (tester) async {
    await pumpPanel(tester, MenuTab.orientation);
    expectTexts(['ОРИЕНТИРОВАНИЕ', 'Компас', 'ОПЦИИ', 'ИНФОРМЕРЫ']);
    await expand(tester, 'ОПЦИИ');
    await expand(tester, 'ИНФОРМЕРЫ');
    expectTexts(['Вращать карту по компасу', 'Показать компас', 'Статус компаса']);
  });

  testWidgets('checkboxes show the stored value and toggle it', (tester) async {
    final container = await pumpPanel(tester, MenuTab.waypoints);
    await expand(tester, 'ОПЦИИ');

    Checkbox checkboxOf(String label) => tester.widget<Checkbox>(
          find.descendant(of: find.widgetWithText(InkWell, label), matching: find.byType(Checkbox)),
        );
    expect(checkboxOf('Названия меток').value, isTrue);

    await tester.tap(find.text('Названия меток'));
    await tester.pump();
    expect(container.read(menuTogglesProvider)[MenuToggle.waypointsNames], isFalse);
    expect(checkboxOf('Названия меток').value, isFalse);
  });

  testWidgets('«Все метки» opens the waypoints list', (tester) async {
    await pumpPanel(tester, MenuTab.waypoints);
    await tester.tap(find.text('Все метки'));
    await tester.pumpAndSettle();
    expect(find.byType(WaypointsListScreen), findsOneWidget);
  });

  testWidgets('«Компас» switch opens the compass screen and turns off after going back', (tester) async {
    await pumpPanel(tester, MenuTab.orientation);
    Switch compassSwitch() => tester.widget<Switch>(
          find.descendant(of: find.byKey(const Key('compass_switch'), skipOffstage: false), matching: find.byType(Switch, skipOffstage: false)),
        );

    await tester.tap(find.byKey(const Key('compass_switch')));
    await tester.pumpAndSettle();
    expect(find.byType(CompassScreen), findsOneWidget);
    expect(compassSwitch().value, isTrue);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(CompassScreen), findsNothing);
    expect(compassSwitch().value, isFalse);
  });

  testWidgets('«Запись трека» switch mirrors and toggles recording', (tester) async {
    final locationSource = FakeLocationSource();
    final container = await pumpPanel(tester, MenuTab.positioning, locationSource: locationSource);
    Switch recordSwitch() => tester.widget<Switch>(
          find.descendant(of: find.byKey(const Key('track_record_toggle')), matching: find.byType(Switch)),
        );
    expect(recordSwitch().value, isFalse);

    await tester.tap(find.byKey(const Key('track_record_toggle')));
    await tester.pumpAndSettle();
    expect(container.read(trackRecordingControllerProvider), isA<TrackRecordingActive>());
    expect(recordSwitch().value, isTrue);
  });

  testWidgets('stopping a too-short recording shows a message and does not open the save form', (tester) async {
    final locationSource = FakeLocationSource();
    await pumpPanel(tester, MenuTab.positioning, locationSource: locationSource);

    await tester.tap(find.byKey(const Key('track_record_toggle')));
    await tester.pumpAndSettle();
    locationSource.emit(const TrackPoint(lat: 1.0, lng: 2.0));
    await tester.pump();
    await tester.tap(find.byKey(const Key('track_record_toggle')));
    await tester.pumpAndSettle();

    expect(find.text('Трек слишком короткий, чтобы сохранить'), findsOneWidget);
    expect(find.byKey(const Key('track_name_field')), findsNothing);
  });
}
```

Also move the third test of `test/positioning/positioning_screen_test.dart` («a TrackException on save shows a SnackBar with the error message») into this file: same body, but `pumpPanel(tester, MenuTab.positioning, locationSource: locationSource, tracksRepo: FakeTracksRepository()..createResult = const TrackException('Could not create track'))` in place of pumping `PositioningScreen`, and keep its remaining steps and assertions unchanged (read them from that file before deleting it in Task 5).

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/menu/menu_panels_test.dart --timeout 60s`
Expected: compile error, `menu_panels.dart` does not exist.

- [ ] **Step 3: Write the implementation**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app_icons.dart';
import '../compass/compass_screen.dart';
import '../tracks/track_recording_actions.dart';
import '../tracks/track_recording_controller.dart';
import '../waypoints/waypoint_create_action.dart';
import '../waypoints/waypoints_list_screen.dart';
import 'menu_toggles.dart';
import 'menu_widgets.dart';

/// Bottom-nav destinations, in nav order; each opens its own panel.
enum MenuTab { settings, maps, waypoints, positioning, orientation }

Widget menuPanelFor(MenuTab tab, {required double arrowCenterX}) {
  return switch (tab) {
    MenuTab.settings => _SettingsPanel(arrowCenterX: arrowCenterX),
    MenuTab.maps => _MapsPanel(arrowCenterX: arrowCenterX),
    MenuTab.waypoints => _WaypointsPanel(arrowCenterX: arrowCenterX),
    MenuTab.positioning => _PositioningPanel(arrowCenterX: arrowCenterX),
    MenuTab.orientation => _OrientationPanel(arrowCenterX: arrowCenterX),
  };
}

/// Checkbox bound to one persisted [MenuToggle].
class _ToggleCheckbox extends ConsumerWidget {
  const _ToggleCheckbox(this.toggle, this.label);

  final MenuToggle toggle;
  final String label;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MenuCheckboxItem(
      label: label,
      value: ref.watch(menuTogglesProvider)[toggle]!,
      onChanged: (value) => ref.read(menuTogglesProvider.notifier).set(toggle, value),
    );
  }
}

class _SettingsPanel extends StatelessWidget {
  const _SettingsPanel({required this.arrowCenterX});

  final double arrowCenterX;

  @override
  Widget build(BuildContext context) {
    return MenuPanel(
      key: const Key('settings_panel'),
      title: 'НАСТРОЙКИ',
      arrowCenterX: arrowCenterX,
      items: const [
        MenuListItem(icon: AppIcons.fullscreen, label: 'Скрыть кнопки меню'),
        MenuListItem(icon: AppIcons.lock, label: 'Блокировка экрана'),
        MenuListItem(icon: AppIcons.camera, label: 'Снимок экрана'),
        MenuListItem(icon: AppIcons.settings, label: 'Настройки'),
      ],
      sections: const [
        MenuSection(title: 'ОПЦИИ', children: [
          _ToggleCheckbox(MenuToggle.settingsSk42Grid, 'Координатная сетка СК-42 (Гаусса-Крюгера)'),
          _ToggleCheckbox(MenuToggle.settingsNightMode, 'Ночной режим'),
          _ToggleCheckbox(MenuToggle.settingsCenterCoordinates, 'Координаты центра экрана'),
        ]),
      ],
    );
  }
}

class _MapsPanel extends StatelessWidget {
  const _MapsPanel({required this.arrowCenterX});

  final double arrowCenterX;

  @override
  Widget build(BuildContext context) {
    return MenuPanel(
      key: const Key('maps_panel'),
      title: 'КАРТЫ',
      arrowCenterX: arrowCenterX,
      items: const [
        MenuListItem(icon: AppIcons.folderMap, label: 'Доступные карты'),
        MenuListItem(icon: AppIcons.layers, label: 'Карты на экране'),
        MenuListItem(icon: AppIcons.download, label: 'Сохранить участок карты'),
        MenuListItem(icon: AppIcons.star, label: 'Избранные карты'),
      ],
      sections: const [
        MenuSection(title: 'ОПЦИИ', children: [
          _ToggleCheckbox(MenuToggle.mapsCacheOnly, 'Использовать только сохранённый кэш карты'),
          _ToggleCheckbox(MenuToggle.mapsLoadingIndicators, 'Индикаторы загрузки карты'),
          _ToggleCheckbox(MenuToggle.mapsMapName, 'Название карты'),
          _ToggleCheckbox(MenuToggle.mapsMapScale, 'Масштаб карты'),
          _ToggleCheckbox(MenuToggle.mapsScaleBar, 'Масштабная линейка'),
        ]),
      ],
    );
  }
}

class _WaypointsPanel extends ConsumerWidget {
  const _WaypointsPanel({required this.arrowCenterX});

  final double arrowCenterX;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MenuPanel(
      key: const Key('waypoints_panel'),
      title: 'МЕТКИ',
      arrowCenterX: arrowCenterX,
      items: [
        MenuListItem(
          icon: AppIcons.flag,
          label: 'Все метки',
          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const WaypointsListScreen())),
        ),
        const MenuListItem(icon: AppIcons.list, label: 'Метки на экране'),
        MenuListItem(
          icon: AppIcons.flagPlus,
          label: 'Новая метка',
          onTap: () => createWaypointAtCrosshair(context, ref),
        ),
        const MenuListItem(icon: AppIcons.search, label: 'Поиск на карте'),
      ],
      sections: const [
        MenuSection(title: 'ОПЦИИ', children: [
          _ToggleCheckbox(MenuToggle.waypointsNames, 'Названия меток'),
          _ToggleCheckbox(MenuToggle.waypointsTargetLine, 'Линия до цели'),
        ]),
        MenuSection(title: 'ИНФОРМЕРЫ', children: [
          _ToggleCheckbox(MenuToggle.waypointsTargetStatus, 'Статус цели'),
        ]),
      ],
    );
  }
}

class _PositioningPanel extends ConsumerWidget {
  const _PositioningPanel({required this.arrowCenterX});

  final double arrowCenterX;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recordingState = ref.watch(trackRecordingControllerProvider);
    final toggles = ref.watch(menuTogglesProvider);
    return MenuPanel(
      key: const Key('positioning_panel'),
      title: 'ПОЗИЦИОНИРОВАНИЕ',
      arrowCenterX: arrowCenterX,
      items: [
        const MenuListItem(icon: AppIcons.gauge, label: 'Путевой компьютер'),
        MenuSwitchItem(
          label: 'Геолокация',
          value: toggles[MenuToggle.positioningGeolocation]!,
          onChanged: (value) => ref.read(menuTogglesProvider.notifier).set(MenuToggle.positioningGeolocation, value),
        ),
        MenuSwitchItem(
          key: const Key('track_record_toggle'),
          label: 'Запись трека',
          value: recordingState is TrackRecordingActive,
          onChanged: (_) => toggleTrackRecording(context, ref, recordingState),
        ),
      ],
      sections: const [
        MenuSection(title: 'ОПЦИИ', children: [
          _ToggleCheckbox(MenuToggle.positioningRotateByMovement, 'Вращать карту по движению'),
          _ToggleCheckbox(MenuToggle.positioningDistanceLine, 'Линия расстояния'),
        ]),
        MenuSection(title: 'ИНФОРМЕРЫ', children: [
          _ToggleCheckbox(MenuToggle.positioningStatus, 'Статус позиционирования'),
          _ToggleCheckbox(MenuToggle.positioningRecordingStatus, 'Статус записи трека'),
        ]),
      ],
    );
  }
}

/// The «Компас» switch is on while CompassScreen is open and goes off when
/// the user leaves it; it is not persisted.
class _OrientationPanel extends StatefulWidget {
  const _OrientationPanel({required this.arrowCenterX});

  final double arrowCenterX;

  @override
  State<_OrientationPanel> createState() => _OrientationPanelState();
}

class _OrientationPanelState extends State<_OrientationPanel> {
  bool _compassOpen = false;

  Future<void> _openCompass() async {
    setState(() => _compassOpen = true);
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CompassScreen()));
    if (mounted) setState(() => _compassOpen = false);
  }

  @override
  Widget build(BuildContext context) {
    return MenuPanel(
      key: const Key('orientation_panel'),
      title: 'ОРИЕНТИРОВАНИЕ',
      arrowCenterX: widget.arrowCenterX,
      items: [
        MenuSwitchItem(
          key: const Key('compass_switch'),
          icon: AppIcons.compass,
          label: 'Компас',
          value: _compassOpen,
          onChanged: (value) {
            if (value && !_compassOpen) _openCompass();
          },
        ),
      ],
      sections: const [
        MenuSection(title: 'ОПЦИИ', children: [
          _ToggleCheckbox(MenuToggle.orientationRotateByCompass, 'Вращать карту по компасу'),
          _ToggleCheckbox(MenuToggle.orientationShowCompass, 'Показать компас'),
        ]),
        MenuSection(title: 'ИНФОРМЕРЫ', children: [
          _ToggleCheckbox(MenuToggle.orientationCompassStatus, 'Статус компаса'),
        ]),
      ],
    );
  }
}
```

Note: the `Key('track_record_toggle')` / `Key('compass_switch')` sit on the `MenuSwitchItem` row, not on the `Switch`; the test helpers already look the `Switch` up as a descendant, and taps on the key work because the whole row is tappable.

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/menu/menu_panels_test.dart --timeout 60s`
Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add app/lib/menu/menu_panels.dart app/test/menu/menu_panels_test.dart
git commit -m "feat(app): menu panel contents for all five tabs"
```

---

### Task 5: HomeShell navigation over an always-visible map

**Files:**
- Modify: `app/lib/home/home_shell.dart`
- Delete: `app/lib/settings/settings_panel.dart`, `app/test/settings/settings_panel_test.dart`, `app/lib/positioning/positioning_screen.dart`, `app/test/positioning/positioning_screen_test.dart`
- Test: `app/test/home/home_shell_test.dart` (rewrite)

**Interfaces:**
- Consumes: Task 4 `MenuTab`, `menuPanelFor`; Task 1 `menuTogglesStoreProvider` (tests override it).

- [ ] **Step 1: Rewrite the test**

Replace `app/test/home/home_shell_test.dart` with:

```dart
import 'package:app/compass/compass_source.dart';
import 'package:app/home/home_shell.dart';
import 'package:app/map/map_screen.dart';
import 'package:app/menu/menu_toggles.dart';
import 'package:app/tracks/tracks_controller.dart';
import 'package:app/waypoints/waypoints_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';

import '../compass/fakes.dart';
import '../tracks/fakes.dart';
import '../waypoints/fakes.dart';

class _MemoryStore implements MenuTogglesStore {
  @override
  Future<Map<String, bool>> load() async => {};
  @override
  Future<void> save(Map<String, bool> values) async {}
}

void main() {
  Future<void> pumpShell(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          waypointsRepositoryProvider.overrideWithValue(FakeWaypointsRepository()),
          tracksRepositoryProvider.overrideWithValue(FakeTracksRepository()),
          compassSourceProvider.overrideWithValue(FakeUnavailableCompassSource()),
          menuTogglesStoreProvider.overrideWithValue(_MemoryStore()),
        ],
        child: const MaterialApp(home: HomeShell()),
      ),
    );
    await tester.pump();
  }

  const navKeys = ['nav_settings', 'nav_map', 'nav_waypoints', 'nav_positioning', 'nav_compass'];
  const panelKeys = ['settings_panel', 'maps_panel', 'waypoints_panel', 'positioning_panel', 'orientation_panel'];

  // Index of the destination showing the selection indicator, or null.
  int? selectedIndex(WidgetTester tester) {
    final selected = [
      for (var i = 0; i < navKeys.length; i++)
        if (find
            .descendant(of: find.byKey(Key(navKeys[i])), matching: find.byKey(const Key('nav_indicator')))
            .evaluate()
            .isNotEmpty)
          i,
    ];
    expect(selected.length, lessThanOrEqualTo(1));
    return selected.isEmpty ? null : selected.single;
  }

  Future<void> tapNav(WidgetTester tester, int index) async {
    await tester.tap(find.byKey(Key(navKeys[index])));
    await tester.pumpAndSettle();
  }

  testWidgets('starts on the map with no tab selected and no panel', (tester) async {
    await pumpShell(tester);

    expect(find.byType(MapScreen), findsOneWidget);
    expect(selectedIndex(tester), isNull);
    for (final key in panelKeys) {
      expect(find.byKey(Key(key)), findsNothing);
    }
  });

  testWidgets('each icon opens its own panel over the map, arrow under that icon', (tester) async {
    await pumpShell(tester);

    for (var i = 0; i < navKeys.length; i++) {
      await tapNav(tester, i);
      expect(selectedIndex(tester), i);
      expect(find.byKey(Key(panelKeys[i])), findsOneWidget);
      expect(find.byType(MapScreen), findsOneWidget);

      final icon = find.descendant(of: find.byKey(Key(navKeys[i])), matching: find.byType(SvgPicture));
      final arrow = find.byKey(const Key('menu_panel_arrow'));
      expect(tester.getCenter(arrow).dx, tester.getCenter(icon).dx);
      expect(tester.getBottomLeft(arrow).dy, tester.getTopLeft(find.byKey(const Key('bottom_nav'))).dy);
    }
  });

  testWidgets('tapping the same icon again closes the panel', (tester) async {
    await pumpShell(tester);
    await tapNav(tester, 1);
    await tapNav(tester, 1);

    expect(find.byKey(const Key('maps_panel')), findsNothing);
    expect(selectedIndex(tester), isNull);
  });

  testWidgets('tapping the map closes the panel', (tester) async {
    await pumpShell(tester);
    await tapNav(tester, 2);

    await tester.tapAt(const Offset(300, 60));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('waypoints_panel')), findsNothing);
    expect(selectedIndex(tester), isNull);
  });

  testWidgets('another icon switches panels', (tester) async {
    await pumpShell(tester);
    await tapNav(tester, 0);
    await tapNav(tester, 4);

    expect(find.byKey(const Key('settings_panel')), findsNothing);
    expect(find.byKey(const Key('orientation_panel')), findsOneWidget);
    expect(selectedIndex(tester), 4);
  });

  testWidgets('compass icon is labelled Ориентирование', (tester) async {
    await pumpShell(tester);

    expect(find.bySemanticsLabel('Ориентирование'), findsOneWidget);
  });

  testWidgets('bottom nav is a 250x60 panel 5 dp from the left edge, icons 40 dp at a 10 dp gap', (tester) async {
    await pumpShell(tester);

    final bar = find.byKey(const Key('bottom_nav'));
    expect(tester.getSize(bar), const Size(250, 60));
    expect(tester.getTopLeft(bar).dx, 5);

    for (var i = 0; i < navKeys.length; i++) {
      final icon = find.descendant(of: find.byKey(Key(navKeys[i])), matching: find.byType(SvgPicture));
      expect(tester.getSize(icon), const Size(40, 40));
      expect(tester.getTopLeft(icon).dx, 10 + i * 50.0);
      expect(tester.getCenter(icon).dy, tester.getCenter(bar).dy);
    }
  });

  testWidgets('bottom nav background is half transparent and the body extends under it', (tester) async {
    await pumpShell(tester);

    final decoration = tester.widget<Container>(find.byKey(const Key('bottom_nav'))).decoration! as BoxDecoration;
    expect(decoration.color!.a, closeTo(0.5, 0.01));
    expect(tester.widget<Scaffold>(find.byType(Scaffold).first).extendBody, isTrue);
  });

  testWidgets('selection indicator is 48 dp square', (tester) async {
    await pumpShell(tester);
    await tapNav(tester, 1);

    expect(tester.getSize(find.byKey(const Key('nav_indicator'))), const Size(48, 48));
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/home/home_shell_test.dart --timeout 60s`
Expected: FAIL — the shell still starts with Карты selected and has no `maps_panel`.

- [ ] **Step 3: Implement**

In `app/lib/home/home_shell.dart`:
- Imports: drop `compass_screen.dart`, `positioning_screen.dart`, `settings_panel.dart`, `waypoints_list_screen.dart`; add `'../menu/menu_panels.dart'`.
- Replace the class doc comment, `_HomeShellState` fields and `build` with:

```dart
/// The map is always on screen. Each bottom-nav icon opens its [MenuTab]
/// panel over it; the same icon again, or a tap on the map, closes it.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  static const double _panelMargin = 5;

  MenuTab? _openTab;

  static const _destinations = [
    _NavDestination(key: Key('nav_settings'), icon: AppIcons.peakMark, label: 'Настройки'),
    _NavDestination(key: Key('nav_map'), icon: AppIcons.map, label: 'Карты'),
    _NavDestination(key: Key('nav_waypoints'), icon: AppIcons.flag, label: 'Метки'),
    _NavDestination(key: Key('nav_positioning'), icon: AppIcons.target, label: 'Позиционирование'),
    _NavDestination(key: Key('nav_compass'), icon: AppIcons.compass, label: 'Ориентирование'),
  ];

  void _onNavSelected(int index) {
    final tab = MenuTab.values[index];
    setState(() => _openTab = _openTab == tab ? null : tab);
  }

  @override
  Widget build(BuildContext context) {
    final openTab = _openTab;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: systemNavigationBarStyle(Theme.of(context).brightness),
      child: Scaffold(
        // The nav panel is half transparent and doesn't span the full width,
        // so the map must continue underneath it.
        extendBody: true,
        // Builder: the extendBody bottom padding only exists below the Scaffold.
        body: Builder(
          builder: (context) {
            final padding = MediaQuery.paddingOf(context);
            return Stack(
              children: [
                const MapScreen(),
                if (openTab != null) ...[
                  // Catches the tap that closes the panel so it never
                  // reaches the map underneath.
                  Positioned.fill(
                    child: GestureDetector(
                      key: const Key('menu_panel_barrier'),
                      behavior: HitTestBehavior.opaque,
                      onTap: () => setState(() => _openTab = null),
                    ),
                  ),
                  Positioned(
                    left: _panelMargin,
                    right: _panelMargin,
                    top: padding.top + _panelMargin,
                    // With extendBody the bottom padding is the nav panel's
                    // height; the panel's arrow fills the gap down to it.
                    bottom: padding.bottom,
                    child: Align(
                      alignment: Alignment.bottomLeft,
                      child: menuPanelFor(
                        openTab,
                        arrowCenterX: _BottomNav.iconCenterX(openTab.index) - _panelMargin,
                      ),
                    ),
                  ),
                ],
              ],
            );
          },
        ),
        bottomNavigationBar: _BottomNav(
          destinations: _destinations,
          selectedIndex: openTab?.index,
          onSelected: _onNavSelected,
        ),
      ),
    );
  }
}
```

- In `_BottomNav`: change `final int selectedIndex;` to `final int? selectedIndex;`, and replace `firstIconCenterX` with:

```dart
  /// Horizontal center of the icon at [index], from the screen edge.
  static double iconCenterX(int index) => _screenMargin + _itemWidth / 2 + index * _itemWidth;
```

- Delete `app/lib/settings/settings_panel.dart`, `app/test/settings/settings_panel_test.dart`, `app/lib/positioning/positioning_screen.dart`, `app/test/positioning/positioning_screen_test.dart` (its third test was moved in Task 4 — check it is there before deleting). Remove the now-empty `settings/` and `positioning/` folders.
- Update the comment in `app/lib/tracks/track_recording_actions.dart` that says «currently the Позиционирование tab» to «currently the ПОЗИЦИОНИРОВАНИЕ menu panel».

- [ ] **Step 4: Run the whole suite and analyzer**

Run: `flutter analyze` then `flutter test --timeout 60s`
Expected: `No issues found!` and all tests pass. `test/app_test.dart` pumps the real app; if it fails on secure storage for menu toggles, the controller already swallows load errors — check the failure message before changing anything.

- [ ] **Step 5: Commit**

```bash
git add -A app/lib app/test
git commit -m "feat(app): nav icons open menu panels over an always-visible map"
```

---

### Task 6: Ship and check on the device

- [ ] **Step 1:** `git push origin main`; wait for the GitHub Actions «Flutter build» run to succeed.
- [ ] **Step 2:** User downloads the `app-debug-apk` artifact to Downloads. Install with `adb install -r` (the CI signing key is now cached — only if it fails with `INSTALL_FAILED_UPDATE_INCOMPATIBLE`, ask the user before uninstalling).
- [ ] **Step 3:** On the phone, via adb screenshots: launch shows only the map; each icon opens its panel with the arrow under it; same icon / map tap closes; sections expand; a checkbox survives an app restart; «Все метки», «Новая метка», «Запись трека» and «Компас» work; rotate to landscape and confirm the panel scrolls.
- [ ] **Step 4:** Report results to the user with screenshots of anything wrong.
