package com.alpinequest.app

import android.os.StatFs
import android.view.View
import android.view.ViewGroup
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.Executors
import org.maplibre.android.maps.MapView

class MainActivity : FlutterActivity() {
    private val tileCacheThread = Executors.newSingleThreadExecutor()

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

    private fun collectMapViews(view: View, into: MutableList<MapView>) {
        if (view is MapView) into.add(view)
        if (view is ViewGroup) {
            for (i in 0 until view.childCount) collectMapViews(view.getChildAt(i), into)
        }
    }
}
