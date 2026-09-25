# Information and coordinates panel (top-left overlay) — design

Date: 2026-09-25. Source: the user's description «ПАНЕЛЬ ИНФОРМАЦИИ И КООРДИНАТ» and their answers in the same session. Replaces the current `_CoordinateHud` in `lib/map/map_screen.dart`.

## Layout

A floating block in the top-left corner (same place as today): light semi-transparent background, rounded corners, a pronounced shadow. Up to three lines; a line whose toggle is off, or which has nothing to show, is omitted. If no line is shown, the block is hidden.

### Line 1 — coordinates of the screen centre (under the crosshair)

- «Координатная сетка СК-42 (Гаусса-Крюгера)» (НАСТРОЙКИ → ОПЦИИ, `MenuToggle.settingsSk42Grid`) **off**: WGS84 decimal degrees, as today: `47.99580, 37.81465` (5 decimals).
- The same toggle **on**: `X = 5021629 Y = 7522048` — Gauss–Krüger rectangular coordinates on the СК-42 (Pulkovo 1942, Krasovsky 1940 ellipsoid) datum, 6° zones, whole metres. X is northing; Y is the zone number followed by the easting with a 500 000 m false easting (e.g. zone 7 → 7 522 048).
- WGS84 → СК-42 datum shift: 7-parameter Helmert on geocentric coordinates with the ГОСТ Р 51794-2008 parameters (EPSG «Pulkovo 1942 to WGS 84» position-vector set: 23.57, −140.95, −79.8 m, 0, 0.35, 0.79″, −0.22 ppm, applied in the WGS84 → СК-42 direction). Tests compare against `pyproj` with the same parameters to within 1 m.
- Shown only while «Координаты центра экрана» (`MenuToggle.settingsCenterCoordinates`) is on.

### Line 2 — telemetry

- Track icon: shown only while a track is being recorded and «Статус записи трека» (`MenuToggle.positioningRecordingStatus`) is on.
- Numeric scale `1:14 546K`: the map scale at the current zoom and latitude on this screen. Under 10 000 the full number is shown with a space as thousands separator (`1:5 000`); from 10 000 up the number is divided by 1 000 and suffixed with `K` (`1:14 546K`).
- Zoom `6/20`: the current zoom level rounded to a whole number, and the map's maximum zoom. The map's maximum zoom is set to 20.
- The scale and zoom are shown while «Масштаб карты» (`MenuToggle.mapsMapScale`) is on.
- Scale bar: a horizontal bar whose length represents a round distance (1, 2 or 5 × 10ⁿ m) of at most about 100 dp, labelled `200 км` / `50 м`. Shown while «Масштабная линейка» (`MenuToggle.mapsScaleBar`) is on.

### Line 3 — target (only while a «Задать цель» target is set)

- Flag icon, then `→ 232,03 км 348.6°`: distance, and azimuth from the target start to the crosshair (screen centre). Under 1 km the distance has one decimal (`12,3 м`).
- Distance: from 1 km up, kilometres with a decimal comma and two decimals (`232,03 км`); under 1 km, whole metres (`350 м`). Azimuth: degrees with one decimal and a decimal point, 0–360 (`348.6°`).
- The orange distance above the crosshair stays. «Статус цели» (`MenuToggle.waypointsTargetStatus`) shows/hides both.

### Removed

The old second line «distance and bearing from my GPS position to the crosshair».

## Defaults

`settingsCenterCoordinates`, `mapsMapScale` and `mapsScaleBar` change their default from off to on. A phone that already saved these toggles keeps its saved values, so the user turns them on once by hand.

## Structure

- `lib/map/sk42.dart`: pure WGS84 → СК-42 Gauss–Krüger conversion (`Sk42Point toSk42(double lat, double lng)` with `x`, `y`, `zone`).
- `lib/map/map_scale.dart`: pure helpers — metres per logical pixel at a zoom and latitude, numeric scale text, zoom text, scale-bar distance and length.
- `lib/map/info_panel.dart`: the `InfoPanel` widget (the three lines), fed with the centre, zoom, target, recording flag and toggles.
- `lib/map/map_screen.dart`: replaces `_CoordinateHud` with `InfoPanel`, tracks the live zoom from camera moves, sets `maxZoomPreference` so the map stops at 20.

## Testing

- СК-42: several points (including near a zone edge and in another zone) against `pyproj` values, ≤ 1 m.
- Scale helpers: known zoom/latitude → metres per pixel; text formatting `1:5 000`, `1:14 546K`; scale bar picks 1/2/5 × 10ⁿ and stays ≤ 100 dp.
- Distance/azimuth formatting: `232,03 км`, `350 м`, `348.6°`.
- `InfoPanel`: each line appears/disappears with its toggle; line 1 switches format with the СК-42 toggle; line 3 only with a target; track icon only while recording; block hidden when empty; style (rounded, shadow, semi-transparent).
- Device check.

## Out of scope

The СК-42 grid drawn on the map, map-name display, loading indicators.
