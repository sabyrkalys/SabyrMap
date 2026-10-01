package com.alpinequest.app

import android.os.StatFs
import android.view.View
import android.view.ViewGroup
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import org.maplibre.android.maps.MapView

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Free space for offline regions (ServerRegionService / PlatformStorageInfo).
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "sabyrmap/storage").setMethodCallHandler { call, result ->
            when (call.method) {
                "freeBytes" -> {
                    val path = call.argument<String>("path")
                    if (path == null) {
                        result.error("bad_args", "path is required", null)
                    } else {
                        try {
                            result.success(StatFs(path).availableBytes)
                        } catch (e: IllegalArgumentException) {
                            result.error("stat_failed", e.message, null)
                        }
                    }
                }
                else -> result.notImplemented()
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
