# Menu panels over the map — design

Date: 2026-09-25. Source: the user's own menu mockup (МЕТКИ / ПОЗИЦИОНИРОВАНИЕ / ОРИЕНТИРОВАНИЕ) plus the КАРТЫ list and navigation answers given in the same session.

## Goal

The map is the app's base screen and is never hidden by the top-level menu. Every bottom-nav icon opens a floating panel over the map instead of switching to a full screen. All five panels are built from one shared set of components.

## Navigation (`HomeShell`)

- At launch only the map is shown; no nav icon is selected.
- Tapping an icon opens its panel and selects the icon. Tapping the same icon again closes it. Tapping another icon switches to that panel.
- While a panel is open, a transparent barrier covers the map outside the panel and the nav bar: a tap on it closes the panel and is not passed to the map. The map pans again once the panel is closed.
- The full-screen tabs are gone. `WaypointsListScreen` and `CompassScreen` are pushed as routes from panel items (below). `PositioningScreen` (an empty placeholder whose only content was the record toggle) is deleted; the record toggle moves into the ПОЗИЦИОНИРОВАНИЕ panel.
- Nav tooltip/semantics label of the compass icon changes from «Компас» to «Ориентирование».
- `MapScreen` stays mounted for the whole session, as with the current `IndexedStack`, so its state (GPS, recording, controller) is preserved.

## Components (`lib/menu/`)

| Component | Content |
|---|---|
| `MenuPanel` | Frame: title header, main items, collapsible sections, down-arrow to its nav icon. Background: white at 85 % opacity with a 10 px `BackdropFilter` blur. Max width 400 dp. Scrolls when taller than the space above the nav bar (landscape phones, small screens). |
| `MenuPanelHeader` | Upper-case title + «?» help button on the right (no action yet). |
| `MenuListItem` | Icon on the left + label; tap callback. |
| `MenuSwitchItem` | Optional left icon + label + `Switch`. |
| `MenuCheckboxItem` | Label + `Checkbox`. |
| `MenuSectionHeader` | Upper-case section title + gear icon on the right; tapping toggles the section open/closed. Sections start collapsed. |

Sections are separated by thin grey dividers. The arrow's horizontal position is computed from the owning icon's index in the nav bar.

## Panel contents

Default values are from the mockup; items marked *placeholder* only store their value or do nothing yet.

**НАСТРОЙКИ** (peak icon)
- Items (unchanged): Скрыть кнопки меню, Блокировка экрана, Снимок экрана, Настройки — *placeholders*.
- ОПЦИИ: Координатная сетка СК-42 (Гаусса-Крюгера), Ночной режим, Координаты центра экрана — checkboxes, default off, *placeholders*.

**КАРТЫ** (map icon)
- Items: Доступные карты, Карты на экране, Сохранить участок карты, Избранные карты — *placeholders*. Proposed icons, for the user to confirm: `folderMap`, `layers`, `download`, `star`.
- ОПЦИИ: Использовать только сохранённый кэш карты, Индикаторы загрузки карты, Название карты, Масштаб карты, Масштабная линейка — checkboxes, default off, *placeholders*.

**МЕТКИ** (flag icon)
- Все метки (flag) — pushes `WaypointsListScreen`.
- Метки на экране (list) — *placeholder*.
- Новая метка (flag with plus) — same flow as the map's «Метка здесь» button: form sheet, waypoint at the crosshair.
- Поиск на карте (search) — *placeholder*.
- ОПЦИИ: Названия меток [on], Линия до цели [on].
- ИНФОРМЕРЫ: Статус цели [on].

**ПОЗИЦИОНИРОВАНИЕ** (target icon)
- Путевой компьютер (gauge) — *placeholder*.
- Геолокация — switch [off], *placeholder*.
- Запись трека — switch that shows the real recording state and calls the existing `toggleTrackRecording` (start, or stop and prompt to save). Not persisted: it mirrors `trackRecordingControllerProvider`.
- ОПЦИИ: Вращать карту по движению [off], Линия расстояния [on].
- ИНФОРМЕРЫ: Статус позиционирования [on], Статус записи трека [on].

**ОРИЕНТИРОВАНИЕ** (compass icon)
- Компас (compass icon) — switch [off]. Turning it on pushes `CompassScreen`. The switch shows on while that screen is open and turns off when the user leaves it. Not persisted.
- ОПЦИИ: Вращать карту по компасу [on], Показать компас [off].
- ИНФОРМЕРЫ: Статус компаса [on].

## State (`lib/menu/menu_toggles.dart`)

- `MenuToggle` enum: one value per persisted checkbox/switch, each with its mockup default.
- `menuTogglesProvider` (Riverpod `Notifier<Map<MenuToggle, bool>>`) loads saved values on start and writes on every change.
- `MenuTogglesStore` interface + `SecureMenuTogglesStore` (flutter_secure_storage, one JSON map under one key), overridable in tests. Same style as `SecureMapCameraStore`. An unknown or corrupt saved value falls back to the defaults.
- «Новая метка» needs the crosshair position from `MapScreen`: `MapScreen` publishes it to a small `mapCrosshairProvider`, and the waypoint-creation flow moves from `MapScreen._createWaypointAtCrosshair` to a shared `createWaypointAtCrosshair(context, ref)` action that both the FAB and the panel call.

## Testing

- `HomeShell` widget tests: nothing selected at launch; open, close by tapping the same icon, close by tapping the barrier, switching panels; the arrow sits under the right icon.
- Component tests: each item type renders and reports taps/changes; a section toggles open and closed.
- Toggle state: defaults, persistence round trip, corrupt data falls back to defaults.
- Wired items: «Все метки» and «Компас» push their screens; «Запись трека» reflects and toggles recording (fake location source).
- Final check on the device.

## Out of scope

Behaviour behind placeholder items (map layers, offline cache, search, trip computer, informers, map rotation, etc.), the «?» help content.
