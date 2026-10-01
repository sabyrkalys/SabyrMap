#!/usr/bin/env python3
"""Собирает стили MapLibre для сервера карт.

Четыре стиля — hybrid-day, hybrid-night, vector-day, vector-night — строятся из
одного описания слоёв и двух палитр, чтобы дневной и ночной вид не расходились.
Адрес тайлов подставляется при сборке (план, фаза 2.4: плейсхолдер TILES_BASE):

    python3 build_styles.py --tiles-base https://maps.example/tiles --out DIR

Источники и адреса совпадают с infra/martin/martin.yaml:
  overview   — обзор мира Natural Earth, растр WebP 256px, z0–5 (overview.sh)
  satellite  — растр WebP 256px, z0–16
  osm        — вектор OpenMapTiles (Planetiler), z0–14, дальше overzoom
  font/...   — Noto Sans (кириллица + латиница), глифы PBF генерирует Martin
  sprite/sabyr — иконки из tools/build/sprites/sabyr/*.svg
"""

import argparse
import json
from pathlib import Path

FONT = ["Noto Sans Regular"]
FONT_BOLD = ["Noto Sans Bold"]
FONT_ITALIC = ["Noto Sans Italic"]

# Подписи: сначала русское имя (интерфейс приложения на русском), потом местное.
NAME = ["coalesce", ["get", "name:ru"], ["get", "name"]]

PALETTES = {
    "day": {
        "background": "#f2efe9",
        "water": "#a8cfee",
        "water_line": "#7fb4de",
        "wood": "#cfe2bf",
        "grass": "#e1eecf",
        "rock": "#e3ddd5",
        "ice": "#f5fbff",
        "residential": "#e9e4dc",
        "park": "#d2e7c2",
        "building": "#dcd4c9",
        "building_line": "#c8beb1",
        "casing": "#c9c0b3",
        "motorway": "#f2a65a",
        "motorway_casing": "#c27a34",
        "primary": "#ffd57e",
        "secondary": "#fff0a6",
        "minor": "#ffffff",
        "track": "#9a7b4f",
        "path": "#a0522d",
        "rail": "#9a9a9a",
        "boundary": "#8b5a9c",
        "text": "#2f3337",
        "text_water": "#3d6f99",
        "halo": "#ffffff",
        "peak": "#6b4a2b",
    },
    "night": {
        "background": "#1c2126",
        "water": "#1e3a50",
        "water_line": "#2b5574",
        "wood": "#21302a",
        "grass": "#252f29",
        "rock": "#2b2c2e",
        "ice": "#2e3740",
        "residential": "#262b31",
        "park": "#22312a",
        "building": "#323941",
        "building_line": "#3c444d",
        "casing": "#14181c",
        "motorway": "#a8692f",
        "motorway_casing": "#5c3a1b",
        "primary": "#86743f",
        "secondary": "#5f5a3c",
        "minor": "#454d56",
        "track": "#9c8460",
        "path": "#c08a5c",
        "rail": "#5a5f66",
        "boundary": "#a98bb7",
        "text": "#dbe2e8",
        "text_water": "#7fb0d6",
        "halo": "#111417",
        "peak": "#d8b98f",
    },
}


def zoom(*stops):
    """Линейная интерполяция по зуму: zoom(5, 0.5, 14, 4)."""
    return ["interpolate", ["linear"], ["zoom"], *stops]


def cls(*names):
    return ["match", ["get", "class"], list(names), True, False]


def line(id_, src_layer, filt, color, width, *, minzoom=0, opacity=1.0,
         dash=None, cap="round"):
    paint = {"line-color": color, "line-width": width, "line-opacity": opacity}
    if dash:
        paint["line-dasharray"] = dash
    return {
        "id": id_, "type": "line", "source": "osm", "source-layer": src_layer,
        "minzoom": minzoom, "filter": filt,
        "layout": {"line-cap": cap, "line-join": "round"},
        "paint": paint,
    }


def fill(id_, src_layer, filt, color, *, minzoom=0, opacity=1.0, outline=None):
    layer = {
        "id": id_, "type": "fill", "source": "osm", "source-layer": src_layer,
        "minzoom": minzoom,
        "paint": {"fill-color": color, "fill-opacity": opacity},
    }
    if filt is not None:
        layer["filter"] = filt
    if outline:
        layer["paint"]["fill-outline-color"] = outline
    return layer


def ground_layers(p):
    """Подложка векторного стиля: суша, вода, растительность, застройка."""
    return [
        fill("landcover-wood", "landcover", cls("wood", "forest"), p["wood"]),
        fill("landcover-grass", "landcover", cls("grass", "farmland", "wetland"),
             p["grass"], opacity=0.7),
        fill("landcover-rock", "landcover", cls("rock", "sand"), p["rock"]),
        fill("landcover-ice", "landcover", cls("ice", "glacier"), p["ice"]),
        fill("landuse-residential", "landuse", cls("residential", "suburb",
             "neighbourhood"), p["residential"], opacity=zoom(8, 0.4, 13, 1)),
        fill("park", "park", None, p["park"], opacity=0.6),
        fill("water", "water", None, p["water"]),
        line("waterway", "waterway", ["!=", ["get", "brunnel"], "tunnel"],
             p["water_line"], zoom(8, 0.5, 14, 2, 18, 6), minzoom=8),
        fill("building", "building", None, p["building"], minzoom=13,
             outline=p["building_line"]),
    ]


def road_layers(p, hybrid):
    """Дороги и тропы. В гибриде — тонкие полупрозрачные поверх спутника,
    чтобы не закрывать снимок; тропы и грунтовки остаются яркими."""
    t = "transportation"
    major = cls("motorway", "trunk", "primary")
    middle = cls("secondary", "tertiary")
    minor = cls("minor", "service")
    k = 0.4 if hybrid else 1.0          # множитель ширины дорог
    op = 0.55 if hybrid else 1.0        # прозрачность дорог (не троп)

    def w(z1, w1, z2, w2):
        return zoom(z1, w1 * k, z2, w2 * k)

    casing = "rgba(0,0,0,0.35)" if hybrid else p["casing"]
    minor_color = "#ffffff" if hybrid else p["minor"]
    path_color = "#ffd27f" if hybrid else p["path"]
    track_color = "#f0dcb4" if hybrid else p["track"]
    casings = [
        line("road-middle-casing", t, middle, casing, w(8, 1.2, 18, 22),
             minzoom=8, opacity=op),
        line("road-major-casing", t, major, casing if hybrid
             else p["motorway_casing"], w(5, 1, 18, 28), minzoom=5, opacity=op),
    ]
    if not hybrid:
        casings.insert(0, line("road-minor-casing", t, minor, casing,
                               w(12, 1, 18, 14), minzoom=12))
    return casings + [
        line("road-minor", t, minor, minor_color, w(12, 0.6, 18, 11),
             minzoom=12, opacity=op),
        line("road-middle", t, middle, p["secondary"], w(8, 0.6, 18, 18),
             minzoom=8, opacity=op),
        line("road-major", t, major, ["match", ["get", "class"],
             ["motorway", "trunk"], p["motorway"], p["primary"]],
             w(5, 0.6, 18, 24), minzoom=5, opacity=op),
        line("rail", t, cls("rail"), p["rail"], zoom(9, 0.6, 18, 3), minzoom=9,
             dash=[4, 2], cap="butt"),
        # Тропы поверх дорог: для походного приложения они главное.
        line("road-track", t, cls("track"), track_color, zoom(11, 0.8, 18, 3),
             minzoom=11, dash=[3, 1.5]),
        line("road-path", t, cls("path"), path_color, zoom(12, 0.8, 18, 2.5),
             minzoom=12, dash=[2, 1.5]),
    ]


def boundary_layers(p, hybrid):
    color = "#e7c3f2" if hybrid else p["boundary"]
    return [
        line("boundary-region", "boundary",
             ["all", ["==", ["get", "admin_level"], 4],
              ["!=", ["get", "maritime"], 1]],
             color, zoom(4, 0.5, 12, 1.5), minzoom=4, opacity=0.6, dash=[3, 2]),
        line("boundary-country", "boundary",
             ["all", ["==", ["get", "admin_level"], 2],
              ["!=", ["get", "maritime"], 1]],
             color, zoom(2, 1, 12, 3.5), opacity=0.9),
    ]


def label_layers(p, hybrid):
    text = "#ffffff" if hybrid else p["text"]
    halo = "rgba(0,0,0,0.75)" if hybrid else p["halo"]
    halo_paint = {"text-color": text, "text-halo-color": halo,
                  "text-halo-width": 1.4, "text-halo-blur": 0.3}

    def symbol(id_, src_layer, filt, layout, paint=None, minzoom=0, maxzoom=24):
        layer = {"id": id_, "type": "symbol", "source": "osm",
                 "source-layer": src_layer, "minzoom": minzoom,
                 "maxzoom": maxzoom,
                 "layout": layout, "paint": paint or halo_paint}
        if filt is not None:
            layer["filter"] = filt
        return layer

    water_paint = dict(halo_paint, **{"text-color": "#bfe3ff" if hybrid
                                      else p["text_water"]})
    return [
        symbol("waterway-name", "waterway", None, {
            "symbol-placement": "line", "text-field": NAME,
            "text-font": FONT_ITALIC, "text-size": 12,
        }, water_paint, minzoom=12),
        symbol("road-name", "transportation_name", None, {
            "symbol-placement": "line", "text-field": NAME, "text-font": FONT,
            "text-size": zoom(13, 10, 18, 14),
        }, minzoom=13),
        symbol("peak", "mountain_peak", cls("peak", "volcano"), {
            "icon-image": "peak", "icon-size": 0.9,
            "text-field": ["format", NAME, {}, "\n", {},
                           ["coalesce", ["to-string", ["get", "ele"]], ""],
                           {"font-scale": 0.85}],
            "text-font": FONT, "text-size": 11, "text-offset": [0, 0.7],
            "text-anchor": "top", "text-optional": True,
        }, dict(halo_paint, **{"text-color": "#ffe9c7" if hybrid else p["peak"]}),
           minzoom=10),
        symbol("place-village", "place", cls("village", "hamlet", "suburb"), {
            "text-field": NAME, "text-font": FONT,
            "text-size": zoom(10, 10, 15, 14),
        }, minzoom=10),
        symbol("place-town", "place", cls("town"), {
            "text-field": NAME, "text-font": FONT, "text-size": zoom(8, 11, 14, 16),
        }, minzoom=7),
        symbol("place-city", "place", cls("city"), {
            "text-field": NAME, "text-font": FONT_BOLD,
            "text-size": zoom(4, 11, 12, 20),
        }, minzoom=4),
        symbol("place-country", "place", cls("country"), {
            "text-field": NAME, "text-font": FONT_BOLD,
            "text-size": zoom(2, 11, 6, 16), "text-transform": "uppercase",
            "text-letter-spacing": 0.1,
        }, maxzoom=7),
    ]


def style(name, theme, hybrid, tiles_base):
    p = PALETTES[theme]
    night = theme == "night"
    sources = {
        "osm": {
            "type": "vector",
            "tiles": [f"{tiles_base}/osm/{{z}}/{{x}}/{{y}}"],
            "minzoom": 0, "maxzoom": 14,
            "attribution": "© OpenMapTiles © OpenStreetMap contributors",
        },
    }
    sources["overview"] = {
        "type": "raster",
        "tiles": [f"{tiles_base}/overview/{{z}}/{{x}}/{{y}}"],
        "tileSize": 256, "minzoom": 0, "maxzoom": 5,
        "attribution": "Natural Earth",
    }
    # Ночью растры приглушаем одинаково — и обзор, и спутник.
    dim = ({"raster-brightness-max": 0.55, "raster-saturation": -0.4}
           if night else {})
    layers = [
        {"id": "background", "type": "background",
         "paint": {"background-color": "#2b3530" if hybrid
                   else p["background"]}},
        # Обзор мира: на мелких зумах вместо пустоты, к z6.5 уходит под спутник
        # (в векторном стиле — под векторную подложку).
        {"id": "overview", "type": "raster", "source": "overview", "maxzoom": 7,
         "paint": {"raster-opacity": zoom(5.5, 1, 6.5, 0),
                   "raster-fade-duration": 250, **dim}},
    ]
    if hybrid:
        sources["satellite"] = {
            "type": "raster",
            "tiles": [f"{tiles_base}/satellite/{{z}}/{{x}}/{{y}}"],
            "tileSize": 256, "minzoom": 0, "maxzoom": 16,
            "attribution": "Esri, Maxar, Earthstar Geographics, and the GIS Community",
        }
        layers.append({"id": "satellite", "type": "raster",
                       "source": "satellite", "minzoom": 5.5,
                       "paint": {"raster-opacity": zoom(5.5, 0, 6.5, 1),
                                 "raster-fade-duration": 250, **dim}})
        layers.append(fill("building", "building", None, "rgba(255,255,255,0.12)",
                           minzoom=14, outline="rgba(255,255,255,0.45)"))
    else:
        layers += ground_layers(p)
    layers += road_layers(p, hybrid)
    layers += boundary_layers(p, hybrid)
    layers += label_layers(p, hybrid)
    return {
        "version": 8,
        "name": f"SabyrMap {name}",
        "metadata": {"sabyrmap:theme": theme, "sabyrmap:hybrid": hybrid},
        "glyphs": f"{tiles_base}/font/{{fontstack}}/{{range}}",
        "sprite": f"{tiles_base}/sprite/sabyr",
        "sources": sources,
        "layers": layers,
    }


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--tiles-base", required=True,
                    help="адрес Martin снаружи, напр. https://maps.example/tiles")
    ap.add_argument("--out", required=True, type=Path)
    args = ap.parse_args()
    base = args.tiles_base.rstrip("/")
    args.out.mkdir(parents=True, exist_ok=True)
    for kind in ("hybrid", "vector"):
        for theme in ("day", "night"):
            name = f"{kind}-{theme}"
            data = style(name, theme, kind == "hybrid", base)
            path = args.out / f"{name}.json"
            path.write_text(json.dumps(data, ensure_ascii=False, indent=1) + "\n",
                            encoding="utf-8")
            print(f"{path}  ({len(data['layers'])} слоёв)")


if __name__ == "__main__":
    main()
