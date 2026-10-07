package com.alpinequest.app

import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteException
import java.io.ByteArrayOutputStream
import java.io.File
import java.util.zip.DataFormatException
import java.util.zip.Inflater

/// Read-only look into MapLibre's tile cache (files/mbgl-offline.db): how
/// much each tile set takes, and the cached copy of a style or TileJSON.
/// MapLibre keeps writing to the file, so every call opens it read-only
/// for a moment and lets a busy database surface as SQLiteException.
class TileCacheDb(private val file: File) {
    /// Bytes per tile URL template, e.g.
    /// "https://host/tiles/satellite/{z}/{x}/{y}" -> 25376636.
    fun bytesByTemplate(): Map<String, Long> = query(emptyMap()) { db ->
        val out = HashMap<String, Long>()
        db.rawQuery("SELECT url_template, SUM(LENGTH(data)) FROM tiles GROUP BY url_template", null).use { c ->
            while (c.moveToNext()) out[c.getString(0)] = c.getLong(1)
        }
        out
    }

    /// The cached body of [url] (a style or TileJSON) as text; null when
    /// it isn't in the cache.
    fun resource(url: String): String? = query(null) { db ->
        db.rawQuery("SELECT data, compressed FROM resources WHERE url = ?", arrayOf(url)).use { c ->
            if (!c.moveToFirst() || c.isNull(0)) return@use null
            val data = c.getBlob(0)
            String(if (c.getInt(1) != 0) inflate(data) else data, Charsets.UTF_8)
        }
    }

    private fun <T> query(missing: T, block: (SQLiteDatabase) -> T): T {
        if (!file.exists()) return missing
        val db = SQLiteDatabase.openDatabase(file.path, null, SQLiteDatabase.OPEN_READONLY)
        try {
            return block(db)
        } finally {
            db.close()
        }
    }

    /// MapLibre compresses with zlib (deflate with the zlib header).
    private fun inflate(data: ByteArray): ByteArray {
        val inflater = Inflater()
        try {
            inflater.setInput(data)
            val out = ByteArrayOutputStream(data.size * 4)
            val buffer = ByteArray(8192)
            while (!inflater.finished()) {
                val n = inflater.inflate(buffer)
                if (n == 0 && (inflater.needsInput() || inflater.needsDictionary())) {
                    throw DataFormatException("truncated resource")
                }
                out.write(buffer, 0, n)
            }
            return out.toByteArray()
        } finally {
            inflater.end()
        }
    }

    companion object {
        fun isFailure(e: Exception) = e is SQLiteException || e is DataFormatException
    }
}
