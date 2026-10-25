package com.reactnativereadium.reader

import java.io.File
import java.nio.file.Files
import org.junit.After
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class ComicPageDiskCacheTest {

  private val directory: File = Files.createTempDirectory("comic-pages").toFile()

  @After
  fun cleanUp() {
    directory.deleteRecursively()
  }

  @Test
  fun roundTripsPagesByUrl() {
    val cache = ComicPageDiskCache(directory)
    val url = "https://example.test/readium/session/pages/001.jpg"
    assertNull(cache.read(url))

    cache.write(url, byteArrayOf(1, 2, 3))

    assertArrayEquals(byteArrayOf(1, 2, 3), cache.read(url))
    assertNull(cache.read("https://example.test/readium/session/pages/002.jpg"))
    assertEquals(0, directory.listFiles()!!.count { it.name.endsWith(".tmp") })
  }

  @Test
  fun evictsLeastRecentlyUsedPagesPastTheLimit() {
    val cache = ComicPageDiskCache(directory, maxBytes = 100)
    val page = ByteArray(40)
    // Give each page a distinct age: "a" oldest, then "b", then "c".
    cache.write("a", page)
    directory.listFiles()!!.forEach { it.setLastModified(1_000_000) }
    cache.write("b", page)
    directory.listFiles()!!.filter { it.lastModified() != 1_000_000L }
      .forEach { it.setLastModified(2_000_000) }
    cache.write("c", page)

    cache.trim()

    assertNull(cache.read("a"))
    assertArrayEquals(page, cache.read("b"))
    assertArrayEquals(page, cache.read("c"))
  }
}
