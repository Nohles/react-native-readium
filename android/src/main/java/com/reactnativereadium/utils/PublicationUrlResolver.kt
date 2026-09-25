package com.reactnativereadium.utils

import java.net.URI
import org.readium.r2.shared.util.format.FormatHints
import org.readium.r2.shared.util.mediatype.MediaType

/**
 * Pure helpers deciding how a publication URL is retrieved, shared by the
 * reader fragments and the audiobook session.
 */
object PublicationUrlResolver {

  /**
   * True when [fileName] is a remote manifest the Readium asset retriever should
   * fetch over the network.
   *
   * iOS classifies any absolute URL with a scheme as remote
   * (`ReaderService.url(path:)` ios/Reader/ReaderService.swift:95-99). Android
   * previously matched only `http`/`https`, so any other absolute URL fell
   * through to `File(fileName)`, which reports "File does not exist" for what is
   * really an unsupported scheme.
   */
  fun isRemoteUrl(fileName: String): Boolean =
    runCatching {
      val scheme = URI(fileName).scheme?.lowercase() ?: return false
      scheme == "http" || scheme == "https"
    }.getOrDefault(false)

  /**
   * The scheme of an absolute URL, or null when [fileName] is a plain path. Used
   * to reject a URL the asset retriever cannot open with an accurate message
   * instead of a misleading filesystem error.
   */
  fun unsupportedScheme(fileName: String): String? =
    runCatching {
      val uri = URI(fileName)
      val scheme = uri.scheme?.lowercase() ?: return null
      if (scheme == "file" || scheme == "content" || scheme == "asset") return null
      if (scheme == "http" || scheme == "https") return null
      // A bare Windows-style or relative path parses without a scheme, so this
      // only fires for a genuine absolute URL.
      if (!uri.isAbsolute) return null
      scheme
    }.getOrNull()

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
