package com.reactnativereadium.reader

import java.io.File
import java.security.MessageDigest

/**
 * Bounded on-disk cache of streamed comic page bytes, keyed by resource URL.
 *
 * Pages of a streamed publication are downloaded ahead of display and land
 * here, so scrolling back or reopening a chapter reads from disk instead of the
 * network. It lives in the app cache directory, which the OS may clear under
 * storage pressure; it is not an offline download. Least recently used pages
 * are evicted once the cache grows past [maxBytes].
 */
internal class ComicPageDiskCache(
  private val directory: File,
  private val maxBytes: Long = DEFAULT_MAX_BYTES
) {
  fun read(key: String): ByteArray? {
    val file = fileFor(key)
    if (!file.isFile) return null
    return runCatching {
      val bytes = file.readBytes()
      file.setLastModified(System.currentTimeMillis())
      bytes
    }.getOrNull()
  }

  fun write(key: String, bytes: ByteArray) {
    runCatching {
      directory.mkdirs()
      val target = fileFor(key)
      // Write to a sibling and rename, so a reader never sees a partial page.
      val temporary = File(directory, "${target.name}.${Thread.currentThread().id}.tmp")
      temporary.writeBytes(bytes)
      if (!temporary.renameTo(target)) {
        temporary.delete()
      }
    }
  }

  /** Evicts least recently used pages until the cache is under [TRIM_TARGET] of [maxBytes]. */
  fun trim() {
    runCatching {
      val files = directory.listFiles()?.filter { it.isFile } ?: return
      var total = files.sumOf { it.length() }
      if (total <= maxBytes) return
      val target = (maxBytes * TRIM_TARGET).toLong()
      for (file in files.sortedBy { it.lastModified() }) {
        if (total <= target) break
        val length = file.length()
        if (file.delete()) total -= length
      }
    }
  }

  private fun fileFor(key: String): File = File(directory, sha256(key))

  private fun sha256(value: String): String =
    MessageDigest.getInstance("SHA-256")
      .digest(value.toByteArray())
      .joinToString("") { "%02x".format(it) }

  companion object {
    const val DIRECTORY_NAME = "readium-comic-pages"
    const val DEFAULT_MAX_BYTES = 512L * 1024 * 1024
    private const val TRIM_TARGET = 0.8
  }
}
