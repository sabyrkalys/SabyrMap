package com.alpinequest.app

import android.content.Context
import java.io.File

/**
 * Files shipped inside the APK (assets/seed/: map symbols, orthophotos)
 * copied into the app's mediafile folder, once per install or update. A file the
 * user already has is left alone, so their edits survive an update; the
 * copy streams, so a large orthophoto never sits in memory.
 */
object SeedFiles {
    private const val ROOT = "seed"

    /** Number of files copied. */
    fun install(context: Context): Int {
        val base = context.getExternalFilesDir(null) ?: context.filesDir
        val installed = context.packageManager.getPackageInfo(context.packageName, 0).lastUpdateTime
        val marker = File(context.filesDir, "seed-$installed.done")
        if (marker.exists()) return 0
        val copied = copyDir(context, ROOT, File(base, "mediafile"))
        marker.writeText("")
        return copied
    }

    private fun copyDir(context: Context, assetDir: String, target: File): Int {
        var copied = 0
        for (name in context.assets.list(assetDir).orEmpty()) {
            val asset = "$assetDir/$name"
            val dest = File(target, name)
            if (context.assets.list(asset).orEmpty().isNotEmpty()) {
                copied += copyDir(context, asset, dest)
            } else if (!dest.exists()) {
                dest.parentFile?.mkdirs()
                val part = File(dest.path + ".part")
                context.assets.open(asset).use { input -> part.outputStream().use { input.copyTo(it, 1 shl 16) } }
                part.renameTo(dest)
                copied++
            }
        }
        return copied
    }
}
