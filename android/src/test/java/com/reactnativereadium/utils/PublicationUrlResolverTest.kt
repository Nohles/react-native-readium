package com.reactnativereadium.utils

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class PublicationUrlResolverTest {

  @Test
  fun `https manifest url is remote`() {
    assertTrue(
      PublicationUrlResolver.isRemoteUrl(
        "https://publication-server.readium.org/webpub/moby-dick/manifest.json"
      )
    )
  }

  @Test
  fun `http url is remote`() {
    assertTrue(
      PublicationUrlResolver.isRemoteUrl("http://localhost:3000/webpub/manifest.json")
    )
  }

  @Test
  fun `local path is not remote`() {
    assertFalse(PublicationUrlResolver.isRemoteUrl("/storage/emulated/0/book.epub"))
  }

  @Test
  fun `file scheme is not remote`() {
    assertFalse(PublicationUrlResolver.isRemoteUrl("file:///storage/emulated/0/book.epub"))
  }

  @Test
  fun `content scheme is not remote`() {
    assertFalse(PublicationUrlResolver.isRemoteUrl("content://downloads/book.epub"))
  }

  @Test
  fun `malformed uri falls back to local path`() {
    assertFalse(PublicationUrlResolver.isRemoteUrl("http://example.com/a b/manifest.json"))
  }

  @Test
  fun `manifest json url gets webpub media type hint`() {
    val hints = PublicationUrlResolver.formatHintsForUrl(
      "https://readium.org/webpub-manifest/examples/MobyDick/manifest.json"
    )
    assertEquals(listOf("application/readium-webpub+json"), hints.mediaTypes.map { it.toString() })
  }

  @Test
  fun `manifest json url with query and fragment gets hint`() {
    val hints = PublicationUrlResolver.formatHintsForUrl(
      "https://example.com/books/moby/manifest.json?token=abc#page=1"
    )
    assertEquals(listOf("application/readium-webpub+json"), hints.mediaTypes.map { it.toString() })
  }

  @Test
  fun `non manifest remote url gets empty hints`() {
    val hints = PublicationUrlResolver.formatHintsForUrl("https://example.com/book.epub")
    assertTrue(hints.mediaTypes.isEmpty())
  }

  @Test
  fun `manifest-like name that is not exactly manifest json gets empty hints`() {
    val hints = PublicationUrlResolver.formatHintsForUrl("https://example.com/manifest.json.bak")
    assertTrue(hints.mediaTypes.isEmpty())
  }
}
