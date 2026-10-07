package com.alpinequest.app

import android.graphics.Bitmap
import android.os.Handler
import android.os.Looper
import android.os.StatFs
import android.view.View
import android.view.ViewGroup
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.File
import java.util.concurrent.Executors
import org.maplibre.android.MapLibre
import org.maplibre.android.camera.CameraPosition
import org.maplibre.android.geometry.LatLng
import org.maplibre.android.maps.MapView
import org.maplibre.android.snapshotter.MapSnapshotter

class MainActivity : FlutterActivity() {
    private val tileCacheThread = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())

    // Snapshots in flight: held so they aren't collected before they answer,
    // and so a timeout and a late result don't both reply.
    private val snapshotters = mutableSetOf<MapSnapshotter>()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Free and total space of a volume (ServerRegionService, «Онлайн-карты»; PlatformStorageInfo).
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "sabyrmap/storage").setMethodCallHandler { call, result ->
            when (call.method) {
                "freeBytes", "totalBytes" -> {
                    val path = call.argument<String>("path")
                    if (path == null) {
                        result.error("bad_args", "path is required", null)
                    } else {
                        try {
                            val stat = StatFs(path)
                            result.success(if (call.method == "freeBytes") stat.availableBytes else stat.totalBytes)
                        } catch (e: IllegalArgumentException) {
                            result.error("stat_failed", e.message, null)
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }
        // Per-map size of MapLibre's tile cache (TileCacheStats in Dart),
        // read off the main thread.
        val tileCache = TileCacheDb(File(filesDir, "mbgl-offline.db"))
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "sabyrmap/tile_cache").setMethodCallHandler { call, result ->
            val work: (() -> Any?)? = when (call.method) {
                "bytesByTemplate" -> { { tileCache.bytesByTemplate() } }
                "resource" -> call.argument<String>("url")?.let { url -> { tileCache.resource(url) } }
                else -> null
            }
            if (work == null) {
                if (call.method == "resource") result.error("bad_args", "url is required", null) else result.notImplemented()
                return@setMethodCallHandler
            }
            tileCacheThread.execute {
                val outcome = try {
                    Result.success(work())
                } catch (e: Exception) {
                    if (TileCacheDb.isFailure(e)) Result.failure(e) else throw e
                }
                runOnUiThread {
                    outcome.fold({ result.success(it) }, { result.error("tile_cache_failed", it.message, null) })
                }
            }
        }
        // A map's style drawn off screen into a JPEG (map previews in
        // «Доступные карты», MapPreviews in Dart). Tiles come through
        // MapLibre's own cache, so a cached area renders offline too.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "sabyrmap/map_preview").setMethodCallHandler { call, result ->
            if (call.method != "snapshot") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            val style = call.argument<String>("style")
            val lat = call.argument<Double>("lat")
            val lng = call.argument<Double>("lng")
            val zoom = call.argument<Double>("zoom")
            val width = call.argument<Int>("width")
            val height = call.argument<Int>("height")
            if (style == null || lat == null || lng == null || zoom == null || width == null || height == null) {
                result.error("bad_args", "style, lat, lng, zoom, width and height are required", null)
                return@setMethodCallHandler
            }
            MapLibre.getInstance(applicationContext)
            val options = MapSnapshotter.Options(width, height)
                .withPixelRatio(minOf(resources.displayMetrics.density, 2f))
                .withCameraPosition(CameraPosition.Builder().target(LatLng(lat, lng)).zoom(zoom).build())
                .withLogo(false)
                .withAttribution(false)
            if (style.trimStart().startsWith("{")) options.withStyleJson(style) else options.withStyle(style)
            val snapshotter = MapSnapshotter(applicationContext, options)
            snapshotters.add(snapshotter)
            mainHandler.postDelayed({
                if (snapshotters.remove(snapshotter)) {
                    snapshotter.cancel()
                    result.error("timeout", "the map did not load in time", null)
                }
            }, SNAPSHOT_TIMEOUT_MS)
            snapshotter.start({ snapshot ->
                if (!snapshotters.remove(snapshotter)) return@start
                val bitmap = snapshot.bitmap
                tileCacheThread.execute {
                    val out = ByteArrayOutputStream()
                    bitmap.compress(Bitmap.CompressFormat.JPEG, 85, out)
                    runOnUiThread { result.success(out.toByteArray()) }
                }
            }, { error ->
                if (snapshotters.remove(snapshotter)) result.error("snapshot_failed", error, null)
            })
        }
        // maplibre_gl has no Dart API for the prefetch zoom delta: find the
        // MapViews it created in the window and set it on each map.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "sabyrmap/map").setMethodCallHandler { call, result ->
            when (call.method) {
                "setPrefetchZoomDelta" -> {
                    val delta = call.argument<Int>("delta") ?: 4
                    val maps = mutableListOf<MapView>()
                    collectMapViews(window.decorView, maps)
                    maps.forEach { view -> view.getMapAsync { map -> map.prefetchZoomDelta = delta } }
                    result.success(maps.size)
                }
                else -> result.notImplemented()
            }
        }
    }

    companion object {
        private const val SNAPSHOT_TIMEOUT_MS = 30_000L
    }

    private fun collectMapViews(view: View, into: MutableList<MapView>) {
        if (view is MapView) into.add(view)
        if (view is ViewGroup) {
            for (i in 0 until view.childCount) collectMapViews(view.getChildAt(i), into)
        }
    }
}
