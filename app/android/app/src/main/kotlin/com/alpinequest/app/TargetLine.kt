package com.alpinequest.app

import java.util.Collections
import java.util.IdentityHashMap
import org.maplibre.android.geometry.LatLng
import org.maplibre.android.maps.MapLibreMap
import org.maplibre.android.maps.MapView
import org.maplibre.android.maps.Style
import org.maplibre.android.style.layers.CircleLayer
import org.maplibre.android.style.layers.LineLayer
import org.maplibre.android.style.layers.Property
import org.maplibre.android.style.layers.PropertyFactory
import org.maplibre.android.style.sources.GeoJsonSource
import org.maplibre.geojson.LineString
import org.maplibre.geojson.Point

/**
 * The «Задать цель» line from the map's centre (the crosshair) to the target,
 * and the target dot, drawn by MapLibre itself. The crosshair end is moved
 * from the map's own camera listener, in the same frame as the map, so the
 * line neither lags behind the crosshair nor comes apart from the dot.
 */
class TargetLine {
    private var target: LatLng? = null
    private val hooked: MutableSet<MapLibreMap> = Collections.newSetFromMap(IdentityHashMap())

    /** Shows the target at [target] on the map of [view], or removes it (null). */
    fun set(view: MapView, target: LatLng?) {
        this.target = target
        view.getMapAsync { map ->
            if (hooked.add(map)) {
                map.addOnCameraMoveListener { apply(map) }
                // A new style comes without our layers.
                view.addOnDidFinishLoadingStyleListener { apply(map) }
            }
            apply(map)
        }
    }

    private fun apply(map: MapLibreMap) {
        val style = map.style ?: return
        if (!style.isFullyLoaded) return
        val target = target
        if (target == null) {
            remove(style)
            return
        }
        val center = map.cameraPosition.target ?: return
        val line = LineString.fromLngLats(
            listOf(Point.fromLngLat(center.longitude, center.latitude), Point.fromLngLat(target.longitude, target.latitude)),
        )
        val dot = Point.fromLngLat(target.longitude, target.latitude)
        val lineSource = style.getSourceAs<GeoJsonSource>(LINE_SOURCE)
        val dotSource = style.getSourceAs<GeoJsonSource>(DOT_SOURCE)
        if (lineSource != null && dotSource != null) {
            lineSource.setGeoJson(line)
            dotSource.setGeoJson(dot)
            return
        }
        remove(style)
        style.addSource(GeoJsonSource(LINE_SOURCE, line))
        style.addSource(GeoJsonSource(DOT_SOURCE, dot))
        style.addLayer(
            LineLayer(CASING_LAYER, LINE_SOURCE).withProperties(
                PropertyFactory.lineColor("#FFFFFF"),
                PropertyFactory.lineOpacity(0.6f),
                PropertyFactory.lineWidth(LINE_WIDTH + 2),
                PropertyFactory.lineCap(Property.LINE_CAP_ROUND),
            ),
        )
        style.addLayer(
            LineLayer(LINE_LAYER, LINE_SOURCE).withProperties(
                PropertyFactory.lineColor(COLOR),
                PropertyFactory.lineWidth(LINE_WIDTH),
                PropertyFactory.lineCap(Property.LINE_CAP_ROUND),
            ),
        )
        style.addLayer(
            CircleLayer(DOT_LAYER, DOT_SOURCE).withProperties(
                PropertyFactory.circleColor(COLOR),
                PropertyFactory.circleRadius(DOT_RADIUS),
            ),
        )
    }

    private fun remove(style: Style) {
        for (layer in listOf(DOT_LAYER, LINE_LAYER, CASING_LAYER)) style.removeLayer(layer)
        for (source in listOf(LINE_SOURCE, DOT_SOURCE)) style.removeSource(source)
    }

    companion object {
        // Same as targetColor in map_overlays.dart.
        private const val COLOR = "#E0218A"
        private const val LINE_WIDTH = 3.5f

        // 14 dp, a bit larger than the crosshair.
        private const val DOT_RADIUS = 7f
        private const val LINE_SOURCE = "sabyrmap-target-line"
        private const val DOT_SOURCE = "sabyrmap-target-dot"
        private const val CASING_LAYER = "sabyrmap-target-line-casing"
        private const val LINE_LAYER = "sabyrmap-target-line"
        private const val DOT_LAYER = "sabyrmap-target-dot"
    }
}
