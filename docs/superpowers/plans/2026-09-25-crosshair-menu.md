# Crosshair Menu Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Tapping the map crosshair opens a context card (Задать/Убрать цель, Новая метка..., Инструменты... submenu, placeholder pin/camera/info icons); a target point draws an orange-labelled line from the crosshair; round zoom buttons replace the «Метка здесь» FAB.

**Architecture:** Pure state in `lib/map/map_target.dart` (target controller, menu-open flag, distance formatting). Presentational widgets in `lib/map/crosshair_menu.dart` and `lib/map/map_overlays.dart`. `MapScreen` wires them: crosshair tap target, card + outside-tap barrier, `onMapClick` for picking, a MapLibre line annotation refreshed on camera changes, the distance label, zoom buttons. `HomeShell` closes the card when a nav panel opens.

**Tech Stack:** Flutter 3.35.5, flutter_riverpod 3.x `Notifier`, maplibre_gl 0.26.2 (`onMapClick`, `addLine`/`updateLine`/`removeLine`, controller is a `ChangeNotifier`, `CameraUpdate.zoomIn/zoomOut`).

**Spec:** `docs/superpowers/specs/2026-09-25-crosshair-menu-design.md`

## Global Constraints

- Labels exactly: «Задать цель», «Убрать цель», «Новая метка...», «Инструменты...», «Инструменты» (tools back row); tools: «Поиск на карте (по имени)», «Спроектировать местоположение», «Автомаршрутизация», «Измерение», «Уклон», «Оповещение о сближении», «Поделиться».
- Icons: pin `AppIcons.pinPlus`, camera `AppIcons.camera`, info `AppIcons.info`; Задать цель `AppIcons.arrowRight`; Убрать цель `AppIcons.close`; Новая метка `AppIcons.flagPlus`; Инструменты `AppIcons.wrench`.
- Card: above the crosshair, down-pointing triangle aimed at it, white at alpha 0.85 + blur sigma 10 (reuse `MenuPanel.background`), rounded 12.
- Target: memory only (never persisted); any map point; line crosshair→target; orange distance label above the crosshair; «Линия до цели» (`MenuToggle.waypointsTargetLine`) gates the line, «Статус цели» (`MenuToggle.waypointsTargetStatus`) gates the label.
- Distance text: `< 1000 m` → «N м» (rounded), else «X.X км» (one decimal).
- Zoom: two round buttons, «+» above «−», light background, dark icons, shadow; bottom-right; FAB «Метка здесь» removed.
- Run Flutter from `app/`, always `--timeout 60s`. Commit messages end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Review Focus

1. Picking armed, then the user opens a nav panel or the card instead of tapping the map — picking must not stay armed forever and silently eat a later unrelated tap: Task 1 test «opening the menu cancels picking».
2. Style reload (MapLibre re-creates annotation managers) while a target is set must not leave a stale `Line` handle that throws on update: Task 4 resets `_targetLine` in `_onStyleLoaded`; covered by code review, not unit-testable without a platform view.
3. Toggling «Линия до цели» off while a target is set must remove the line, and back on must redraw it: Task 4 listens to `menuTogglesProvider` and calls `_syncTargetLine`.
4. Rapid camera changes must not start overlapping add/update line calls (duplicate lines): Task 4's `_syncTargetLine` is serialized with a busy/pending flag.
5. Target 0 m away (target == crosshair) shows «0 м», not a blank or NaN: Task 1 formatting test.

---

### Task 1: Target state, menu flag, distance formatting

**Files:**
- Create: `app/lib/map/map_target.dart`
- Test: `app/test/map/map_target_test.dart`

**Interfaces:**
- Produces:
  - `sealed class MapTargetState` with `MapTargetNone`, `MapTargetPicking`, `MapTargetSet(LatLng point)`; getter `LatLng? get point` on the base (null unless set).
  - `mapTargetProvider` = `NotifierProvider<MapTargetController, MapTargetState>`; methods `startPicking()`, `pick(LatLng)` (only acts while picking), `clear()`, `cancelPicking()` (picking → none, otherwise no-op).
  - `crosshairMenuOpenProvider` = `NotifierProvider<CrosshairMenuOpen, bool>`; methods `open()` (also cancels picking), `close()`, `toggle()` (opening via toggle also cancels picking).
  - `String formatDistance(double meters)`.

- [ ] **Step 1: Write the failing test**

```dart
import 'package:app/map/map_target.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

void main() {
  ProviderContainer container() {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    return c;
  }

  test('starts with no target', () {
    expect(container().read(mapTargetProvider), isA<MapTargetNone>());
  });

  test('pick only sets a target while picking', () {
    final c = container();
    c.read(mapTargetProvider.notifier).pick(const LatLng(1, 2));
    expect(c.read(mapTargetProvider), isA<MapTargetNone>());

    c.read(mapTargetProvider.notifier).startPicking();
    expect(c.read(mapTargetProvider), isA<MapTargetPicking>());
    c.read(mapTargetProvider.notifier).pick(const LatLng(1, 2));
    expect(c.read(mapTargetProvider).point, const LatLng(1, 2));

    c.read(mapTargetProvider.notifier).pick(const LatLng(3, 4));
    expect(c.read(mapTargetProvider).point, const LatLng(1, 2), reason: 'not picking any more');
  });

  test('clear removes the target', () {
    final c = container();
    c.read(mapTargetProvider.notifier)
      ..startPicking()
      ..pick(const LatLng(1, 2))
      ..clear();
    expect(c.read(mapTargetProvider), isA<MapTargetNone>());
  });

  test('opening the menu cancels picking but keeps a set target', () {
    final c = container();
    c.read(mapTargetProvider.notifier).startPicking();
    c.read(crosshairMenuOpenProvider.notifier).open();
    expect(c.read(mapTargetProvider), isA<MapTargetNone>());

    c.read(mapTargetProvider.notifier)
      ..startPicking()
      ..pick(const LatLng(1, 2));
    c.read(crosshairMenuOpenProvider.notifier).toggle();
    expect(c.read(crosshairMenuOpenProvider), isTrue);
    expect(c.read(mapTargetProvider).point, const LatLng(1, 2));

    c.read(crosshairMenuOpenProvider.notifier).toggle();
    expect(c.read(crosshairMenuOpenProvider), isFalse);
    c.read(crosshairMenuOpenProvider.notifier).open();
    c.read(crosshairMenuOpenProvider.notifier).close();
    expect(c.read(crosshairMenuOpenProvider), isFalse);
  });

  test('formatDistance', () {
    expect(formatDistance(0), '0 м');
    expect(formatDistance(349.6), '350 м');
    expect(formatDistance(999.4), '999 м');
    expect(formatDistance(1000), '1.0 км');
    expect(formatDistance(1234), '1.2 км');
  });
}
```

- [ ] **Step 2: Run it** — `flutter test test/map/map_target_test.dart --timeout 60s`. Expected: compile error, file missing.

- [ ] **Step 3: Implement** `app/lib/map/map_target.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

/// The «Задать цель» measuring tool: a point the crosshair measures to.
/// Memory only -- it is a tool, not an object, and is gone after a restart.
sealed class MapTargetState {
  const MapTargetState();

  LatLng? get point => null;
}

class MapTargetNone extends MapTargetState {
  const MapTargetNone();
}

/// Armed by «Задать цель»: the next map tap becomes the target.
class MapTargetPicking extends MapTargetState {
  const MapTargetPicking();
}

class MapTargetSet extends MapTargetState {
  const MapTargetSet(this._point);

  final LatLng _point;

  @override
  LatLng get point => _point;
}

class MapTargetController extends Notifier<MapTargetState> {
  @override
  MapTargetState build() => const MapTargetNone();

  void startPicking() => state = const MapTargetPicking();

  void pick(LatLng point) {
    if (state is MapTargetPicking) state = MapTargetSet(point);
  }

  void cancelPicking() {
    if (state is MapTargetPicking) state = const MapTargetNone();
  }

  void clear() => state = const MapTargetNone();
}

final mapTargetProvider = NotifierProvider<MapTargetController, MapTargetState>(MapTargetController.new);

/// Whether the crosshair context card is open. Opening it cancels a pending
/// target pick, so an armed «Задать цель» never swallows a later tap.
class CrosshairMenuOpen extends Notifier<bool> {
  @override
  bool build() => false;

  void open() {
    ref.read(mapTargetProvider.notifier).cancelPicking();
    state = true;
  }

  void close() => state = false;

  void toggle() => state ? close() : open();
}

final crosshairMenuOpenProvider = NotifierProvider<CrosshairMenuOpen, bool>(CrosshairMenuOpen.new);

/// «350 м» under a kilometre, «1.2 км» from one kilometre up.
String formatDistance(double meters) {
  if (meters < 999.5) return '${meters.round()} м';
  return '${(meters / 1000).toStringAsFixed(1)} км';
}
```

Note: `999.4` must give «999 м» and `1000` «1.0 км`; the `999.5` threshold keeps «1000 м» from ever appearing.

- [ ] **Step 4: Run it** — same command. Expected: 5 pass.

- [ ] **Step 5: Commit** — `git add app/lib/map/map_target.dart app/test/map/map_target_test.dart && git commit -m "feat(app): map target state and distance formatting"`

---

### Task 2: Crosshair context card

**Files:**
- Create: `app/lib/map/crosshair_menu.dart`
- Modify: `app/lib/menu/menu_widgets.dart` (`MenuListItem.icon` becomes optional)
- Test: `app/test/map/crosshair_menu_test.dart`

**Interfaces:**
- Consumes: `MenuListItem`, `MenuPanel.background` (Task: existing `menu_widgets.dart`).
- Produces: `CrosshairMenu({Key? key, required bool hasTarget, required VoidCallback onSetTarget, required VoidCallback onRemoveTarget, required VoidCallback onNewWaypoint})`; keys `crosshair_menu` (card), `crosshair_menu_triangle`, `crosshair_menu_pin`, `crosshair_menu_camera`, `crosshair_menu_info`, `crosshair_menu_tools_back`; `CrosshairMenu.triangleHeight = 8`, `CrosshairMenu.maxWidth = 320`.

- [ ] **Step 1: Write the failing test**

```dart
import 'package:app/map/crosshair_menu.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const tools = [
    'Поиск на карте (по имени)',
    'Спроектировать местоположение',
    'Автомаршрутизация',
    'Измерение',
    'Уклон',
    'Оповещение о сближении',
    'Поделиться',
  ];

  Future<List<String>> pump(WidgetTester tester, {bool hasTarget = false}) async {
    final calls = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: CrosshairMenu(
              hasTarget: hasTarget,
              onSetTarget: () => calls.add('set'),
              onRemoveTarget: () => calls.add('remove'),
              onNewWaypoint: () => calls.add('new'),
            ),
          ),
        ),
      ),
    );
    return calls;
  }

  double top(WidgetTester tester, Finder f) => tester.getTopLeft(f).dy;

  testWidgets('icon row on top, then the three items in order', (tester) async {
    await pump(tester);

    final pin = find.byKey(const Key('crosshair_menu_pin'));
    expect(pin, findsOneWidget);
    expect(find.byKey(const Key('crosshair_menu_camera')), findsOneWidget);
    expect(find.byKey(const Key('crosshair_menu_info')), findsOneWidget);
    expect(top(tester, pin), lessThan(top(tester, find.text('Задать цель'))));
    expect(top(tester, find.text('Задать цель')), lessThan(top(tester, find.text('Новая метка...'))));
    expect(top(tester, find.text('Новая метка...')), lessThan(top(tester, find.text('Инструменты...'))));
    expect(find.byType(Divider), findsOneWidget);
  });

  testWidgets('pin, camera and info are disabled placeholders', (tester) async {
    await pump(tester);
    for (final key in ['crosshair_menu_pin', 'crosshair_menu_camera', 'crosshair_menu_info']) {
      expect(tester.widget<IconButton>(find.byKey(Key(key))).onPressed, isNull, reason: key);
    }
  });

  testWidgets('items call their callbacks', (tester) async {
    final calls = await pump(tester);
    await tester.tap(find.text('Задать цель'));
    await tester.tap(find.text('Новая метка...'));
    expect(calls, ['set', 'new']);
  });

  testWidgets('with a target the first item is «Убрать цель»', (tester) async {
    final calls = await pump(tester, hasTarget: true);
    expect(find.text('Задать цель'), findsNothing);
    await tester.tap(find.text('Убрать цель'));
    expect(calls, ['remove']);
  });

  testWidgets('«Инструменты...» shows the tools list and back returns', (tester) async {
    await pump(tester);
    await tester.tap(find.text('Инструменты...'));
    await tester.pumpAndSettle();

    for (final tool in tools) {
      expect(find.text(tool), findsOneWidget, reason: tool);
    }
    expect(find.text('Задать цель'), findsNothing);

    await tester.tap(find.byKey(const Key('crosshair_menu_tools_back')));
    await tester.pumpAndSettle();
    expect(find.text('Задать цель'), findsOneWidget);
    expect(find.text(tools.first), findsNothing);
  });

  testWidgets('triangle sits under the card, horizontally centred', (tester) async {
    await pump(tester);
    final card = find.byKey(const Key('crosshair_menu'));
    final triangle = find.byKey(const Key('crosshair_menu_triangle'));
    expect(tester.getSize(triangle), const Size(16, 8));
    expect(tester.getTopLeft(triangle).dy, tester.getBottomLeft(card).dy);
    expect(tester.getCenter(triangle).dx, tester.getCenter(card).dx);
    expect(tester.getSize(card).width, lessThanOrEqualTo(320));
  });
}
```

- [ ] **Step 2: Run it** — `flutter test test/map/crosshair_menu_test.dart --timeout 60s`. Expected: compile error.

- [ ] **Step 3: Implement**

In `app/lib/menu/menu_widgets.dart`, make the icon optional in `MenuListItem`:

```dart
  const MenuListItem({super.key, this.icon, required this.label, this.onTap});

  final String? icon;
```

and in its `build`:

```dart
    final icon = this.icon;
    return InkWell(
      onTap: onTap,
      child: _MenuRow(
        leading: icon == null ? null : AppIcon(icon, size: _iconSize, color: style.color),
        label: Text(label, style: style),
      ),
    );
```

Create `app/lib/map/crosshair_menu.dart`:

```dart
import 'dart:ui';

import 'package:flutter/material.dart';

import '../app_icons.dart';
import '../menu/menu_widgets.dart';
import '../theme/app_text_styles.dart';
import '../widgets/app_icon.dart';

/// Context card opened by tapping the map crosshair. The pin / camera /
/// info icons are a separate function from the items, so they sit in their
/// own row above a divider. Tools are placeholders for now.
class CrosshairMenu extends StatefulWidget {
  const CrosshairMenu({
    super.key,
    required this.hasTarget,
    required this.onSetTarget,
    required this.onRemoveTarget,
    required this.onNewWaypoint,
  });

  static const double triangleWidth = 16;
  static const double triangleHeight = 8;
  static const double maxWidth = 320;

  static const tools = [
    'Поиск на карте (по имени)',
    'Спроектировать местоположение',
    'Автомаршрутизация',
    'Измерение',
    'Уклон',
    'Оповещение о сближении',
    'Поделиться',
  ];

  final bool hasTarget;
  final VoidCallback onSetTarget;
  final VoidCallback onRemoveTarget;
  final VoidCallback onNewWaypoint;

  @override
  State<CrosshairMenu> createState() => _CrosshairMenuState();
}

class _CrosshairMenuState extends State<CrosshairMenu> {
  bool _showTools = false;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: CrosshairMenu.maxWidth),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: ClipRRect(
              key: const Key('crosshair_menu'),
              borderRadius: BorderRadius.circular(12),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                child: Material(
                  color: MenuPanel.background,
                  child: SingleChildScrollView(
                    child: AnimatedSize(
                      duration: const Duration(milliseconds: 200),
                      curve: Curves.easeOut,
                      child: _showTools ? _buildTools(context) : _buildMain(context),
                    ),
                  ),
                ),
              ),
            ),
          ),
          CustomPaint(
            key: const Key('crosshair_menu_triangle'),
            size: const Size(CrosshairMenu.triangleWidth, CrosshairMenu.triangleHeight),
            painter: _TrianglePainter(MenuPanel.background),
          ),
        ],
      ),
    );
  }

  Widget _buildMain(BuildContext context) {
    final disabled = AppTextStyles.menuItemDisabled(context).color;
    Widget placeholderIcon(String key, String icon) => IconButton(
          key: Key(key),
          onPressed: null,
          icon: AppIcon(icon, size: 24, color: disabled),
        );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              placeholderIcon('crosshair_menu_pin', AppIcons.pinPlus),
              placeholderIcon('crosshair_menu_camera', AppIcons.camera),
              placeholderIcon('crosshair_menu_info', AppIcons.info),
            ],
          ),
        ),
        const Divider(height: 1, thickness: 0.5, color: Color(0xFFDADCE0)),
        if (widget.hasTarget)
          MenuListItem(icon: AppIcons.close, label: 'Убрать цель', onTap: widget.onRemoveTarget)
        else
          MenuListItem(icon: AppIcons.arrowRight, label: 'Задать цель', onTap: widget.onSetTarget),
        MenuListItem(icon: AppIcons.flagPlus, label: 'Новая метка...', onTap: widget.onNewWaypoint),
        MenuListItem(
          icon: AppIcons.wrench,
          label: 'Инструменты...',
          onTap: () => setState(() => _showTools = true),
        ),
      ],
    );
  }

  Widget _buildTools(BuildContext context) {
    final style = AppTextStyles.sectionHeader(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          key: const Key('crosshair_menu_tools_back'),
          onTap: () => setState(() => _showTools = false),
          child: SizedBox(
            height: 48,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Transform.flip(
                    flipX: true,
                    child: AppIcon(AppIcons.arrowRight, size: 24, color: style.color),
                  ),
                  const SizedBox(width: 16),
                  Text('Инструменты', style: style),
                ],
              ),
            ),
          ),
        ),
        const Divider(height: 1, thickness: 0.5, color: Color(0xFFDADCE0)),
        for (final tool in CrosshairMenu.tools) MenuListItem(label: tool),
      ],
    );
  }
}

class _TrianglePainter extends CustomPainter {
  const _TrianglePainter(this.color);

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
  bool shouldRepaint(_TrianglePainter oldDelegate) => oldDelegate.color != color;
}
```

- [ ] **Step 4: Run** `flutter test test/map/crosshair_menu_test.dart test/menu --timeout 60s`. Expected: all pass (menu tests guard the `MenuListItem` change).

- [ ] **Step 5: Commit** — `git add app/lib/map/crosshair_menu.dart app/lib/menu/menu_widgets.dart app/test/map/crosshair_menu_test.dart && git commit -m "feat(app): crosshair context card"`

---

### Task 3: Zoom buttons and target distance label

**Files:**
- Create: `app/lib/map/map_overlays.dart`
- Test: `app/test/map/map_overlays_test.dart`

**Interfaces:**
- Consumes: Task 1 `formatDistance`; existing `distanceMeters` from `lib/map/geo_utils.dart`.
- Produces: `MapZoomButtons({Key? key, required VoidCallback onZoomIn, required VoidCallback onZoomOut})` with keys `zoom_in_button`, `zoom_out_button`; `TargetDistanceLabel({Key? key, required LatLng from, required LatLng to})`; `const Color targetColor = Color(0xFFFF8C00)`; `const String targetLineColorHex = '#FF8C00'`.

- [ ] **Step 1: Write the failing test**

```dart
import 'package:app/map/map_overlays.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

void main() {
  testWidgets('zoom buttons: round, shadowed, + above −, each calls back', (tester) async {
    final calls = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: MapZoomButtons(onZoomIn: () => calls.add('in'), onZoomOut: () => calls.add('out')),
          ),
        ),
      ),
    );

    final zoomIn = find.byKey(const Key('zoom_in_button'));
    final zoomOut = find.byKey(const Key('zoom_out_button'));
    expect(tester.getTopLeft(zoomIn).dy, lessThan(tester.getTopLeft(zoomOut).dy));
    for (final button in [zoomIn, zoomOut]) {
      final material = tester.widget<Material>(find.descendant(of: button, matching: find.byType(Material)).first);
      expect(material.shape, isA<CircleBorder>());
      expect(material.elevation, greaterThan(0));
      expect(material.color, Colors.white);
    }

    await tester.tap(zoomIn);
    await tester.tap(zoomOut);
    expect(calls, ['in', 'out']);
  });

  testWidgets('distance label shows the formatted distance in orange', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(child: TargetDistanceLabel(from: LatLng(48, 37.8), to: LatLng(48, 37.8))),
        ),
      ),
    );

    final text = tester.widget<Text>(find.text('0 м'));
    expect(text.style!.color, targetColor);
  });
}
```

- [ ] **Step 2: Run** `flutter test test/map/map_overlays_test.dart --timeout 60s`. Expected: compile error.

- [ ] **Step 3: Implement** `app/lib/map/map_overlays.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import 'geo_utils.dart';
import 'map_target.dart';

/// Colour of the «Задать цель» line and distance label.
const Color targetColor = Color(0xFFFF8C00);
const String targetLineColorHex = '#FF8C00';

/// Round «+» / «−» buttons stacked vertically, bottom-right over the map.
class MapZoomButtons extends StatelessWidget {
  const MapZoomButtons({super.key, required this.onZoomIn, required this.onZoomOut});

  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _RoundButton(key: const Key('zoom_in_button'), icon: Icons.add, onTap: onZoomIn),
        const SizedBox(height: 12),
        _RoundButton(key: const Key('zoom_out_button'), icon: Icons.remove, onTap: onZoomOut),
      ],
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({super.key, required this.icon, required this.onTap});

  static const double _size = 48;

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      shape: const CircleBorder(),
      elevation: 4,
      shadowColor: Colors.black54,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: _size,
          height: _size,
          child: Icon(icon, color: const Color(0xFF16181A)),
        ),
      ),
    );
  }
}

/// Orange distance from the crosshair to the target, shown above the crosshair.
class TargetDistanceLabel extends StatelessWidget {
  const TargetDistanceLabel({super.key, required this.from, required this.to});

  final LatLng from;
  final LatLng to;

  @override
  Widget build(BuildContext context) {
    final meters = distanceMeters(from.latitude, from.longitude, to.latitude, to.longitude);
    return Text(
      formatDistance(meters),
      style: const TextStyle(
        color: targetColor,
        fontSize: 16,
        fontWeight: FontWeight.w700,
        shadows: [Shadow(color: Colors.white, blurRadius: 3)],
      ),
    );
  }
}
```

- [ ] **Step 4: Run** — same command. Expected: 2 pass.

- [ ] **Step 5: Commit** — `git add app/lib/map/map_overlays.dart app/test/map/map_overlays_test.dart && git commit -m "feat(app): map zoom buttons and target distance label"`

---

### Task 4: Wire it into MapScreen and HomeShell

**Files:**
- Modify: `app/lib/map/map_screen.dart`, `app/lib/home/home_shell.dart`, `app/lib/waypoints/waypoint_create_action.dart` (doc comment only)
- Test: `app/test/map/map_screen_test.dart` (replace the two FAB tests), `app/test/home/home_shell_test.dart` (add one test)

**Interfaces:**
- Consumes: Task 1 (`mapTargetProvider`, `crosshairMenuOpenProvider`, `MapTargetState.point`), Task 2 (`CrosshairMenu`), Task 3 (`MapZoomButtons`, `TargetDistanceLabel`, `targetLineColorHex`), existing `menuTogglesProvider`, `MenuToggle.waypointsTargetLine`, `MenuToggle.waypointsTargetStatus`, `mapCrosshairProvider`, `createWaypointAtCrosshair`.
- Produces: keys `map_crosshair` (now tappable), `crosshair_menu_barrier`, `target_distance_label`.

- [ ] **Step 1: Write the failing tests**

In `app/test/map/map_screen_test.dart`, replace the test «shows a persistent crosshair and a create-waypoint button, with no long-press wiring» and the test «tapping create-waypoint button before the map controller is ready shows a message, no crash» with the tests below. Add imports `package:app/map/map_crosshair.dart`, `package:app/map/map_target.dart`, `package:app/menu/menu_toggles.dart`; add a helper store class and `menuTogglesStoreProvider.overrideWithValue(_NoopTogglesStore())` to `_baseOverrides`.

```dart
class _NoopTogglesStore implements MenuTogglesStore {
  @override
  Future<Map<String, bool>> load() async => {};
  @override
  Future<void> save(Map<String, bool> values) async {}
}
```

```dart
  Future<ProviderContainer> pumpMap(WidgetTester tester) async {
    final container = ProviderContainer(overrides: _baseOverrides());
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const MaterialApp(home: MapScreen())),
    );
    await tester.pump();
    return container;
  }

  testWidgets('crosshair, zoom buttons, no «Метка здесь» button, no long-press wiring', (tester) async {
    await pumpMap(tester);

    expect(find.byKey(const Key('map_crosshair')), findsOneWidget);
    expect(find.byKey(const Key('zoom_in_button')), findsOneWidget);
    expect(find.byKey(const Key('zoom_out_button')), findsOneWidget);
    expect(find.text('Метка здесь'), findsNothing);
    expect(find.byType(FloatingActionButton), findsNothing);
    expect(tester.widget<MapLibreMap>(find.byType(MapLibreMap)).onMapLongClick, isNull);
  });

  testWidgets('tapping the crosshair opens the card above it; tapping again closes it', (tester) async {
    await pumpMap(tester);

    await tester.tap(find.byKey(const Key('map_crosshair')));
    await tester.pumpAndSettle();
    final card = find.byKey(const Key('crosshair_menu'));
    expect(card, findsOneWidget);
    expect(
      tester.getBottomLeft(find.byKey(const Key('crosshair_menu_triangle'))).dy,
      lessThanOrEqualTo(tester.getTopLeft(find.byKey(const Key('map_crosshair'))).dy),
    );
    expect(
      tester.getCenter(find.byKey(const Key('crosshair_menu_triangle'))).dx,
      closeTo(tester.getCenter(find.byKey(const Key('map_crosshair'))).dx, 0.5),
    );

    await tester.tap(find.byKey(const Key('map_crosshair')));
    await tester.pumpAndSettle();
    expect(card, findsNothing);
  });

  testWidgets('tapping outside the card closes it', (tester) async {
    await pumpMap(tester);
    await tester.tap(find.byKey(const Key('map_crosshair')));
    await tester.pumpAndSettle();

    await tester.tapAt(const Offset(20, 300));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('crosshair_menu')), findsNothing);
  });

  testWidgets('«Задать цель» closes the card and arms picking; with a target the item is «Убрать цель»', (tester) async {
    final container = await pumpMap(tester);
    await tester.tap(find.byKey(const Key('map_crosshair')));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Задать цель'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('crosshair_menu')), findsNothing);
    expect(container.read(mapTargetProvider), isA<MapTargetPicking>());

    container.read(mapTargetProvider.notifier).pick(const LatLng(48, 37.8));
    await tester.tap(find.byKey(const Key('map_crosshair')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Убрать цель'));
    await tester.pumpAndSettle();
    expect(container.read(mapTargetProvider), isA<MapTargetNone>());
    expect(find.byKey(const Key('crosshair_menu')), findsNothing);
  });

  testWidgets('distance label follows «Статус цели»', (tester) async {
    final container = await pumpMap(tester);
    container.read(mapCrosshairProvider.notifier).set(const LatLng(48, 37.8));
    container.read(mapTargetProvider.notifier)
      ..startPicking()
      ..pick(const LatLng(48, 37.8));
    await tester.pump();
    expect(find.byKey(const Key('target_distance_label')), findsOneWidget);
    expect(find.text('0 м'), findsOneWidget);

    container.read(menuTogglesProvider.notifier).set(MenuToggle.waypointsTargetStatus, false);
    await tester.pump();
    expect(find.byKey(const Key('target_distance_label')), findsNothing);
  });

  testWidgets('«Новая метка...» before the map settles reports the map is not ready', (tester) async {
    await pumpMap(tester);
    await tester.tap(find.byKey(const Key('map_crosshair')));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Новая метка...'));
    await tester.pumpAndSettle();
    expect(find.text('Карта ещё не готова'), findsOneWidget);
    expect(find.byKey(const Key('crosshair_menu')), findsNothing);
  });
```

In `app/test/home/home_shell_test.dart` add (it uses the existing `pumpShell` and `tapNav` helpers):

```dart
  testWidgets('opening a nav panel closes the crosshair card', (tester) async {
    await pumpShell(tester);
    await tester.tap(find.byKey(const Key('map_crosshair')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('crosshair_menu')), findsOneWidget);

    await tapNav(tester, 1);
    expect(find.byKey(const Key('crosshair_menu')), findsNothing);
  });
```

- [ ] **Step 2: Run** `flutter test test/map/map_screen_test.dart test/home/home_shell_test.dart --timeout 60s`. Expected: the new tests fail (no zoom buttons, crosshair not tappable).

- [ ] **Step 3: Implement**

`app/lib/map/map_screen.dart`:

1. Imports: add `'crosshair_menu.dart'`, `'map_overlays.dart'`, `'map_target.dart'`, `'../menu/menu_toggles.dart'`. Remove the `AppIcon`/`AppIcons` imports if they become unused (analyzer will say).
2. State fields (next to `_crosshairPosition`):

```dart
  // «Задать цель» line: one annotation, refreshed on every camera change
  // while a target is set. Serialized like _requestSync so rapid camera
  // ticks never run overlapping add/update calls.
  Line? _targetLine;
  bool _targetLineBusy = false;
  bool _targetLinePending = false;
  // Live camera centre, tracked only while a target is set so the distance
  // label follows a drag without rebuilding on every frame otherwise.
  LatLng? _liveCenter;
```

3. `_onMapCreated`: after the tap listeners add `controller.addListener(_onCameraChanged);`.
4. Add:

```dart
  void _onCameraChanged() {
    if (ref.read(mapTargetProvider).point == null) return;
    final center = _controller?.cameraPosition?.target;
    if (center != null && mounted) setState(() => _liveCenter = center);
    _syncTargetLine();
  }

  Future<void> _syncTargetLine() async {
    if (_targetLineBusy) {
      _targetLinePending = true;
      return;
    }
    _targetLineBusy = true;
    try {
      do {
        _targetLinePending = false;
        final controller = _controller;
        if (controller == null) return;
        final target = ref.read(mapTargetProvider).point;
        final showLine = ref.read(menuTogglesProvider)[MenuToggle.waypointsTargetLine]!;
        final center = controller.cameraPosition?.target;
        final existing = _targetLine;
        if (target == null || !showLine || center == null) {
          if (existing != null) {
            _targetLine = null;
            await controller.removeLine(existing);
          }
        } else {
          final options = LineOptions(geometry: [center, target], lineColor: targetLineColorHex, lineWidth: 3);
          if (existing == null) {
            _targetLine = await controller.addLine(options);
          } else {
            await controller.updateLine(existing, options);
          }
        }
      } while (_targetLinePending);
    } catch (_) {
      // Same soft-failure policy as _runSync: a manager not ready yet or a
      // style reload race; the next camera tick or state change retries.
    } finally {
      _targetLineBusy = false;
    }
  }
```

5. `_onStyleLoaded`: next to `_myLocationCircle = null;` add `_targetLine = null;` and after `_requestSync();` add `_syncTargetLine();`.
6. At the top of `build` (next to the other `ref.listen` calls):

```dart
    ref.listen<MapTargetState>(mapTargetProvider, (previous, next) {
      _liveCenter = _controller?.cameraPosition?.target;
      _syncTargetLine();
    });
    ref.listen<Map<MenuToggle, bool>>(menuTogglesProvider, (previous, next) => _syncTargetLine());
    final target = ref.watch(mapTargetProvider).point;
    final toggles = ref.watch(menuTogglesProvider);
    final menuOpen = ref.watch(crosshairMenuOpenProvider);
    final center = _liveCenter ?? ref.watch(mapCrosshairProvider);
```

7. `MapLibreMap(...)`: add `onMapClick: (point, coordinates) => ref.read(mapTargetProvider.notifier).pick(coordinates),`.
8. Replace the `IgnorePointer(child: Center(child: Container(key: const Key('map_crosshair'), ...)))` block and remove the `floatingActionButton:` argument. After the HUD `if`, the Stack children continue with:

```dart
          if (target != null && center != null && toggles[MenuToggle.waypointsTargetStatus]!)
            Center(
              child: Transform.translate(
                offset: const Offset(0, -34),
                child: TargetDistanceLabel(key: const Key('target_distance_label'), from: center, to: target),
              ),
            ),
          Positioned(
            right: 16,
            bottom: 16,
            child: SafeArea(
              top: false,
              left: false,
              child: MapZoomButtons(
                onZoomIn: () => _controller?.animateCamera(CameraUpdate.zoomIn()),
                onZoomOut: () => _controller?.animateCamera(CameraUpdate.zoomOut()),
              ),
            ),
          ),
          if (menuOpen) ...[
            Positioned.fill(
              child: GestureDetector(
                key: const Key('crosshair_menu_barrier'),
                behavior: HitTestBehavior.opaque,
                onTap: () => ref.read(crosshairMenuOpenProvider.notifier).close(),
              ),
            ),
            // The card's bottom (its triangle tip) sits just above the
            // crosshair: half the screen minus the crosshair's radius.
            Positioned(
              left: 16,
              right: 16,
              top: MediaQuery.paddingOf(context).top + 8,
              bottom: MediaQuery.sizeOf(context).height / 2 + 16 + 2,
              child: Align(
                alignment: Alignment.bottomCenter,
                child: CrosshairMenu(
                  hasTarget: target != null,
                  onSetTarget: () {
                    ref.read(crosshairMenuOpenProvider.notifier).close();
                    ref.read(mapTargetProvider.notifier).startPicking();
                  },
                  onRemoveTarget: () {
                    ref.read(crosshairMenuOpenProvider.notifier).close();
                    ref.read(mapTargetProvider.notifier).clear();
                  },
                  onNewWaypoint: () {
                    ref.read(crosshairMenuOpenProvider.notifier).close();
                    createWaypointAtCrosshair(context, ref, iconScanner: _iconLibraryScanner);
                  },
                ),
              ),
            ),
          ],
          Center(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => ref.read(crosshairMenuOpenProvider.notifier).toggle(),
              child: Padding(
                // Larger hit area than the 32 dp ring.
                padding: const EdgeInsets.all(8),
                child: Container(
                  key: const Key('map_crosshair'),
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Theme.of(context).colorScheme.onSurface, width: 2),
                  ),
                  child: Center(
                    child: Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
```

Note on `onNewWaypoint`: `close()` rebuilds and removes the card, but `context` and `ref` here belong to `MapScreen`, which stays mounted, so the action is safe.

`app/lib/home/home_shell.dart` — in `_onNavSelected`, before `setState`, add:

```dart
    ProviderScope.containerOf(context, listen: false).read(crosshairMenuOpenProvider.notifier).close();
```

and import `package:flutter_riverpod/flutter_riverpod.dart` and `'../map/map_target.dart'`.

`app/lib/waypoints/waypoint_create_action.dart` — doc comment: replace «Shared by the map's «Метка здесь» button and the МЕТКИ panel.» with «Shared by the crosshair menu and the МЕТКИ panel.»

- [ ] **Step 4: Run** `flutter analyze` and `flutter test --timeout 60s`. Expected: no issues; all tests pass.

- [ ] **Step 5: Commit** — `git add -A app/lib app/test && git commit -m "feat(app): crosshair menu, target line and zoom buttons on the map"`

---

### Task 5: Ship and check on the device

- [ ] **Step 1:** Final whole-branch review, fix Critical/Important, merge to `main` and push (the user asks for this each time; confirm before pushing).
- [ ] **Step 2:** User downloads the artifact; install with `adb install -r` (CI key is cached now; uninstall only on `INSTALL_FAILED_UPDATE_INCOMPATIBLE`, asking first).
- [ ] **Step 3:** On the phone (tiles may be missing because of the VPN; annotations still render): tap the crosshair → card above it with the triangle; «Инструменты...» → list → back; «Задать цель» → tap the map → orange line and distance; pan → distance updates, target moves with the map; «Убрать цель» clears; «+»/«−» zoom; nav icon closes the card; «Линия до цели»/«Статус цели» in МЕТКИ hide line/label.
