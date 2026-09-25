# «Информация (i)» point details — design

Date: 2026-09-25. Part 2 of the crosshair context menu. Source: the user's description («Информация (i): Открывает окно с подробной справкой о точке: Координаты, Склонение (магнитное), Конвергенция меридианов, Время восхода и заката, Часовой пояс») and their answers in the same session.

## Opening

The «i» icon in the crosshair card (today a disabled placeholder) becomes active. Tapping it closes the card and opens a bottom sheet for the point under the crosshair at that moment. If the crosshair position is not known yet, it shows «Карта ещё не готова» like «Новая метка...».

## Sheet

Bottom sheet over the map, styled like the menu panels (white at 85 % with a 10 px blur, rounded top corners). Closed by swiping down or tapping outside. Title `ИНФОРМАЦИЯ` in the panel-title style. Rows, label on the left, value on the right; labels are the user's words:

| Label | Value example | Source |
|---|---|---|
| Координаты | `X = 5318741 Y = 7411649` or `47.99580, 37.81465` | same format as the info panel: СК-42 when «Координатная сетка СК-42 (Гаусса-Крюгера)» is on, otherwise WGS84 degrees |
| Склонение (магнитное) | `8.1° В` | World Magnetic Model WMM2025, computed on the phone for today's date, sea level |
| Конвергенция меридианов | `0.6° З` | angle between true north and the grid north (X axis) of the point's СК-42 Gauss–Krüger zone |
| Время восхода и заката | [sunrise icon] `05:43` [sunset icon] `18:12` | NOAA solar algorithm, today's date, the phone's time zone |
| Часовой пояс | `UTC+3` | the phone's time zone offset |

- Angles: one decimal, degree sign, then `В` (east) or `З` (west); exactly 0 shows `0.0°` without a letter.
- Time: `HH:MM`, 24-hour. When the sun does not rise or set that day (polar day/night), the time after that icon is `—`.
- Offsets with minutes show them: `UTC+5:30`, `UTC−3:30`; zero is `UTC+0`.

## Icons

Two new SVGs in `app/assets/icons/`: `sunrise.svg` and `sunset.svg`, taken from Material Design Icons (`weather-sunset-up`, `weather-sunset-down`, Pictogrammers, Apache-2.0) and normalised to the app's icon format (`width="24" height="24" viewBox="0 0 24 24" fill="currentColor"`). Registered in `AppIcons`.

## Structure

- `lib/geo/wmm.dart`: WMM2025 spherical-harmonic model (coefficients embedded) → declination in degrees.
- `lib/geo/sun_times.dart`: sunrise/sunset (NOAA) for a date and point → UTC `DateTime`s or null when the sun doesn't cross the horizon.
- `lib/map/sk42.dart`: add `double sk42Convergence(double lat, double lng)` (Gauss–Krüger grid convergence in degrees, positive east of the zone's central meridian).
- `lib/map/point_info_sheet.dart`: formatting helpers + the sheet widget.
- `lib/map/crosshair_menu.dart` / `map_screen.dart`: enable the «i» button and open the sheet.

## Testing

- WMM: NOAA's official WMM2025 test values, declination within 0.05°.
- Sun times: reference values from the Python `astral` package for several places/dates, within 1 minute; polar day and polar night return null.
- Convergence: against `pyproj` (`meridian_convergence` of the same tmerc/Krasovsky zone), within 0.01°.
- Formatting: `8.1° В`, `0.6° З`, `0.0°`, `UTC+3`, `UTC+5:30`, `—`.
- Sheet: title, five rows in order, coordinates follow the СК-42 toggle, icons present; «i» opens it, closed with no crosshair position shows the snackbar.
- Device check.

## Out of scope

«Поделиться / Открыть в», elevation, the point's real (political) time zone.
