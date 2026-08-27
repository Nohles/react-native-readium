package com.reactnativereadium.utils

import java.net.URI
import org.readium.r2.shared.util.format.FormatHints
import org.readium.r2.shared.util.mediatype.MediaType

/**
 * Pure helpers deciding how a publication URL is retrieved, shared by the
 * reader fragments and the audiobook session.
 */
object PublicationUrlResolver {

  fun isRemoteUrl(fileName: String): Boolean =
    runCatching {
      val uri = URI(fileName)
      uri.scheme == "http" || uri.scheme == "https"
    }.getOrDefault(false)

  /**
   * Streamed Readium Web Publications are opened from a remote manifest.json
   * URL. Port of `ReaderService.formatHints(for:)`
   * (ios/Reader/ReaderService.swift:176-181).
   */
  fun formatHintsForUrl(url: String): FormatHints {
    val lastSegment = url
      .substringBefore('?')
      .substringBefore('#')
      .substringAfterLast('/')

    if (lastSegment != "manifest.json") {
      return FormatHints()
    }

    return FormatHints(mediaType = MediaType("application/readium-webpub+json")!!)
  }
}
