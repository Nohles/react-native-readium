package com.reactnativereadium.utils

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertNotEquals
import org.junit.Test

class LocationNormalizerTest {

  @Test
  fun normalizesRootRelativeHrefWithoutFragment() {
    val result = normalizeHref("/OEBPS/chapter1.xhtml")

    assertEquals("OEBPS/chapter1.xhtml", result.resourcePath)
    assertNull(result.fragment)
  }

  @Test
  fun normalizesRelativeHrefWithoutFragment() {
    val result = normalizeHref("OEBPS/chapter1.xhtml")

    assertEquals("OEBPS/chapter1.xhtml", result.resourcePath)
    assertNull(result.fragment)
  }

  @Test
  fun stripsLeadingSlashAndExtractsFragment() {
    val result = normalizeHref("/OEBPS/chapter1.xhtml#pgepubid00005")

    assertEquals("OEBPS/chapter1.xhtml", result.resourcePath)
    assertEquals("pgepubid00005", result.fragment)
  }

  @Test
  fun keepsRelativeHrefAndExtractsFragment() {
    val result = normalizeHref("OEBPS/chapter1.xhtml#pgepubid00005")

    assertEquals("OEBPS/chapter1.xhtml", result.resourcePath)
    assertEquals("pgepubid00005", result.fragment)
  }

  @Test
  fun handlesEmptyHref() {
    val result = normalizeHref("")

    assertEquals("", result.resourcePath)
    assertNull(result.fragment)
  }

  @Test
  fun handlesRootOnlyHref() {
    val result = normalizeHref("/")

    assertEquals("", result.resourcePath)
    assertNull(result.fragment)
  }

  @Test
  fun handlesHrefThatIsOnlyFragment() {
    val result = normalizeHref("#chapter1")

    assertEquals("", result.resourcePath)
    assertEquals("chapter1", result.fragment)
  }

  @Test
  fun handlesRootRelativeHrefThatIsOnlyFragment() {
    val result = normalizeHref("/#chapter1")

    assertEquals("", result.resourcePath)
    assertEquals("chapter1", result.fragment)
  }

  @Test
  fun handlesHrefWithEmptyFragment() {
    val result = normalizeHref("OEBPS/chapter1.xhtml#")

    assertEquals("OEBPS/chapter1.xhtml", result.resourcePath)
    assertEquals("", result.fragment)
  }

  @Test
  fun splitsAtFirstFragmentDelimiterOnly() {
    val result = normalizeHref("OEBPS/chapter1.xhtml#frag#ment")

    assertEquals("OEBPS/chapter1.xhtml", result.resourcePath)
    assertEquals("frag#ment", result.fragment)
  }

  @Test
  fun keepsEncodedCharactersIntact() {
    val result = normalizeHref("/OEBPS/chapter%201.xhtml#p%20one")

    assertEquals("OEBPS/chapter%201.xhtml", result.resourcePath)
    assertEquals("p%20one", result.fragment)
  }

  @Test
  fun returnsEqualValuesForEquivalentInputs() {
    assertEquals(normalizeHref("/OEBPS/chapter1.xhtml#f"), normalizeHref("OEBPS/chapter1.xhtml#f"))
  }

  @Test
  fun returnsDifferentValuesForDifferentInputs() {
    assertNotEquals(normalizeHref("/OEBPS/chapter1.xhtml"), normalizeHref("/OEBPS/chapter2.xhtml"))
  }

  @Test
  fun fragmentOnlyResultDiffersFromNoFragmentResult() {
    assertNotEquals(normalizeHref("#f"), normalizeHref(""))
  }
}
