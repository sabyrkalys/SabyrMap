package com.alpinequest.app

import java.util.Collections
import java.util.IdentityHashMap
import kotlin.math.hypot
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
 * from the map's own camera listener. That listener hears of a move only
 * after its frame is drawn, so on fast flings the line's crosshair end
 * trails by a frame or two: while the map moves faster than [HIDE_SPEED]
 * the line is hidden (the dot stays), and it is back once the map slows
 * below [SHOW_SPEED] or stops.
 */
class TargetLine {
    private var target: LatLng? = null

    // Map centre and time the map's speed is measured from.
    private var lastCenter: LatLng? = null
    private var lastMoveNanos = 0L
    private var lineHidden = false

    // Slow measurements in a row since the line was hidden.
    private var slowCount = 0
    private val hooked: MutableSet<MapLibreMap> = Collections.newSetFromMap(IdentityHashMap())

    /** Shows the target at [target] on the map of [view], or removes it (null). */
    fun set(view: MapView, target: LatLng?) {
        this.target = target
        view.getMapAsync { map ->
            if (hooked.add(map)) {
                map.addOnCameraMoveListener {
                    hideLineWhileFast(view, map)
                    apply(map)
                }
                map.addOnCameraIdleListener {
                    lastCenter = null
                    slowCount = 0
                    setLineHidden(map, false)
                }
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
                PropertyFactory.visibility(if (lineHidden) Property.NONE else Property.VISIBLE),
                PropertyFactory.lineColor("#FFFFFF"),
                PropertyFactory.lineOpacity(0.6f),
                PropertyFactory.lineWidth(LINE_WIDTH + 2),
                PropertyFactory.lineCap(Property.LINE_CAP_ROUND),
            ),
        )
        style.addLayer(
            LineLayer(LINE_LAYER, LINE_SOURCE).withProperties(
                PropertyFactory.visibility(if (lineHidden) Property.NONE else Property.VISIBLE),
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

    /**
     * Hides the line while the map moves fast. The speed (dp/s) is measured
     * over at least [MIN_WINDOW_NANOS]: camera moves sometimes come in bursts
     * a few milliseconds apart, and over such a gap the speed jumps. The line
     * is hidden at once, and shown again only after [SHOW_AFTER] slow
     * measurements in a row, so it doesn't flash between two flings.
     */
    private fun hideLineWhileFast(view: MapView, map: MapLibreMap) {
        val center = map.cameraPosition.target ?: return
        val now = System.nanoTime()
        val previous = lastCenter
        if (previous == null || now - lastMoveNanos > MAX_WINDOW_NANOS) {
            lastCenter = center
            lastMoveNanos = now
            return
        }
        if (now - lastMoveNanos < MIN_WINDOW_NANOS) return
        val elapsed = (now - lastMoveNanos) / 1e9
        lastCenter = center
        lastMoveNanos = now
        val moved = map.projection.toScreenLocation(previous)
        val pixels = hypot(moved.x - view.width / 2f, moved.y - view.height / 2f)
        val speed = pixels / view.resources.displayMetrics.density / elapsed
        if (speed > HIDE_SPEED) {
            slowCount = 0
            setLineHidden(map, true)
        } else if (speed < SHOW_SPEED && ++slowCount >= SHOW_AFTER) {
            setLineHidden(map, false)
        }
    }

    private fun setLineHidden(map: MapLibreMap, hidden: Boolean) {
        if (hidden == lineHidden) return
        lineHidden = hidden
        val style = map.style ?: return
        val visibility = PropertyFactory.visibility(if (hidden) Property.NONE else Property.VISIBLE)
        for (layer in listOf(CASING_LAYER, LINE_LAYER)) style.getLayer(layer)?.setProperties(visibility)
    }

    private fun remove(style: Style) {
        for (layer in listOf(DOT_LAYER, LINE_LAYER, CASING_LAYER)) style.removeLayer(layer)
        for (source in listOf(LINE_SOURCE, DOT_SOURCE)) style.removeSource(source)
    }

    companion object {
        // Same as targetColor in map_overlays.dart.
        private const val COLOR = "#E0218A"
        // Thin, so a frame of lag at the crosshair end on fast flings hides
        // under the crosshair.
        private const val LINE_WIDTH = 2.5f

        // dp/s. Below SHOW_SPEED a frame of lag stays under the crosshair.
        private const val HIDE_SPEED = 200f
        private const val SHOW_SPEED = 120f
        private const val SHOW_AFTER = 3
        private const val MIN_WINDOW_NANOS = 8_000_000L
        private const val MAX_WINDOW_NANOS = 200_000_000L

        // 14 dp, a bit larger than the crosshair.
        private const val DOT_RADIUS = 7f
        private const val LINE_SOURCE = "sabyrmap-target-line"
        private const val DOT_SOURCE = "sabyrmap-target-dot"
        private const val CASING_LAYER = "sabyrmap-target-line-casing"
        private const val LINE_LAYER = "sabyrmap-target-line"
        private const val DOT_LAYER = "sabyrmap-target-dot"
    }
}
