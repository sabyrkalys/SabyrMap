# Crosshair context menu, target measurement, zoom buttons — design

Date: 2026-09-25. Part 1 of the crosshair context-menu work. Source: the user's description of the context menu and map controls, plus answers given in the same session.

## Decomposition (agreed)

1. **This spec:** the menu shell, «Задать цель» / «Убрать цель», «Новая метка...», the «Инструменты...» submenu (placeholder tools), the pin / camera / «i» icons as placeholders, zoom buttons, removal of the «Метка здесь» button.
2. Later, each separately: «Информация (i)» point details; «Поделиться / Открыть в»; camera + photo attached to a waypoint; route waypoints (pin); every tool in «Инструменты...».

## Opening and closing

- Tapping the centre crosshair opens a card **above** the crosshair, with a down-pointing triangle aimed at it. Same look as the menu panels: white at 85 % with a 10 px blur, rounded corners.
- Tapping outside the card, or the crosshair again, closes it. Opening a bottom-nav panel also closes it (while a nav panel is open, its barrier already covers the crosshair).

## Card content

Main list, top to bottom:

1. A row of three icon buttons, right-aligned, separated from the items below by a thin grey divider: pin (`pinPlus`), camera (`camera`), info (`info`). They are a separate function from the items, so they must not look attached to any item. All three are placeholders in this part (disabled style, no action).
2. «Задать цель» (`arrowRight`). When a target is set, this item reads «Убрать цель» with the close icon (`close`).
3. «Новая метка...» (`flagPlus`): the existing new-waypoint form; the waypoint goes to the point under the crosshair.
4. «Инструменты...» (`wrench`): replaces the card content with the tools list. The tools list has a back row with the title «Инструменты» that returns to the main list. Tools, all placeholders in this part: Поиск на карте (по имени), Спроектировать местоположение, Автомаршрутизация, Измерение, Уклон, Оповещение о сближении, Поделиться.

## Target («Задать цель»)

- It is a measuring tool, not an object: it is kept only in memory and is gone after an app restart.
- «Задать цель» closes the card and makes the point currently under the crosshair the target start (changed 2026-09-25 at the user's request; no map tap is needed). The user first moves the map so the crosshair is over the wanted point.
- A dot the size of the crosshair's centre dot marks the start; the crosshair marks the other end.
- The crosshair always stays at the screen centre. The target is a geographic point, so it moves with the map when the map is panned or zoomed.
- A line is drawn from the crosshair (current camera centre) to the target. It is redrawn as the camera moves.
- Above the crosshair, in orange, the distance from the crosshair to the target is shown, in the same format as the coordinate HUD («350 м», «1.2 км»).
- «Убрать цель» removes the target, the line and the distance.
- The МЕТКИ panel checkboxes now take effect: «Линия до цели» shows/hides the line, «Статус цели» shows/hides the orange distance. Both default to on.

## Zoom buttons

- Bottom-right overlay: a vertical stack of two round buttons, «+» on top and «−» below. Light background, dark icons, a shadow under each button.
- «+» / «−» zoom the map in / out by one level with animation.
- The «Метка здесь» button is removed; the zoom buttons take its place. Waypoints are created through «Новая метка...» in this menu or in the МЕТКИ panel.

## Structure

- `lib/map/map_target.dart`: `MapTargetController` (Riverpod `Notifier`) with states none / picking / set(`LatLng`); not persisted.
- `lib/map/crosshair_menu.dart`: the card (main list, tools list, icon row, triangle), built from the existing `menu_widgets.dart` rows and the same background/blur.
- `lib/map/map_zoom_buttons.dart`: the zoom stack.
- `lib/map/map_screen.dart`: crosshair tap target, card overlay with its outside-tap barrier, `onMapClick` for target picking, target line annotation updated from camera changes, orange distance label, zoom buttons instead of the FAB.
- A `crosshairMenuOpenProvider` lets `HomeShell` close the card when a nav panel opens.

## Testing

- Crosshair tap opens the card above the crosshair; outside tap / second crosshair tap closes it; opening a nav panel closes it.
- Main list content and order; icon row present and disabled; «Инструменты...» switches to the tools list and back.
- Target controller: pick → set → remove; «Задать цель» ⇄ «Убрать цель» label and icon.
- Distance label: shown in orange with the right text when a target is set and «Статус цели» is on; hidden otherwise. Line visibility follows «Линия до цели».
- Zoom buttons: present, round, «+» above «−», each calls the zoom action; «Метка здесь» button is gone.
- Device check (tiles currently do not load on the test phone because of the VPN, but the crosshair, card, line and label render without tiles).

## Out of scope

Behaviour behind the pin, camera and «i» icons, every tool in «Инструменты...», «Поделиться / Открыть в».
