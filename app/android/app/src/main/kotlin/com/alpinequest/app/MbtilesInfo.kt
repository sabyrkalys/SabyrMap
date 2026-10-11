package com.alpinequest.app

import android.database.sqlite.SQLiteDatabase
import java.io.File
import kotlin.math.PI
import kotlin.math.atan
import kotlin.math.sinh

/// Where an .mbtiles file has tiles and at which zooms, read from the tiles
/// themselves (not the metadata table, which is often wrong): the tile range
/// at the deepest zoom, through the (zoom, column, row) index.
object MbtilesInfo {
    fun read(path: String): Map<String, Any>? {
        if (!File(path).exists()) return null
        val db = SQLiteDatabase.openDatabase(path, null, SQLiteDatabase.OPEN_READONLY)
        try {
            var minZoom = -1
            var maxZoom = -1
            db.rawQuery("SELECT MIN(zoom_level), MAX(zoom_level) FROM tiles", null).use { c ->
                if (c.moveToFirst() && !c.isNull(0)) {
                    minZoom = c.getInt(0)
                    maxZoom = c.getInt(1)
                }
            }
            if (maxZoom < 0) return null
            db.rawQuery(
                "SELECT MIN(tile_column), MAX(tile_column), MIN(tile_row), MAX(tile_row) FROM tiles WHERE zoom_level = ?",
                arrayOf(maxZoom.toString()),
            ).use { c ->
                if (!c.moveToFirst() || c.isNull(0)) return null
                val n = 1L shl maxZoom
                // MBTiles rows are TMS: row 0 is the southernmost.
                val west = lon(c.getLong(0), n)
                val east = lon(c.getLong(1) + 1, n)
                val south = lat(n - c.getLong(2), n)
                val north = lat(n - 1 - c.getLong(3), n)
                return mapOf(
                    "minZoom" to minZoom,
                    "maxZoom" to maxZoom,
                    "west" to west,
                    "south" to south,
                    "east" to east,
                    "north" to north,
                )
            }
        } finally {
            db.close()
        }
    }

    private fun lon(x: Long, n: Long) = x.toDouble() / n * 360.0 - 180.0

    private fun lat(y: Long, n: Long) = Math.toDegrees(atan(sinh(PI * (1 - 2.0 * y / n))))
}
