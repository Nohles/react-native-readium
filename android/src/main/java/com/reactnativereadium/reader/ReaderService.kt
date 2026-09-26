package com.reactnativereadium.reader

import com.facebook.react.bridge.ReactApplicationContext
import com.facebook.react.util.RNLog
import com.reactnativereadium.audio.AudiobookSession
import com.reactnativereadium.utils.LinkOrLocator
import com.reactnativereadium.utils.PublicationUrlResolver
import java.io.File
import java.util.Locale
import org.readium.r2.shared.publication.Locator
import org.readium.r2.shared.publication.Publication
import org.readium.r2.shared.publication.services.isRestricted
import org.readium.r2.shared.publication.services.protectionError
import org.readium.r2.shared.util.AbsoluteUrl
import org.readium.r2.shared.util.FileExtension
import org.readium.r2.shared.util.Url
import org.readium.r2.shared.util.asset.AssetRetriever
import org.readium.r2.shared.util.format.FormatHints
import org.readium.r2.shared.util.http.DefaultHttpClient
import org.readium.r2.shared.util.mediatype.MediaType
import org.readium.r2.shared.util.toUrl
import org.readium.adapter.pdfium.document.PdfiumDocumentFactory
import org.readium.r2.streamer.PublicationOpener
import kotlin.time.Duration.Companion.seconds
import org.readium.r2.streamer.parser.DefaultPublicationParser


class ReaderService(
  private val reactContext: ReactApplicationContext
) {
  /**
   * Bounded network timeouts.
   *
   * `DefaultHttpClient` leaves both `connectTimeout` and `readTimeout` null by
   * default, and null means "use HttpURLConnection's default" — for
   * `readTimeout` that default is **0, i.e. infinite**. A connection that
   * stalls mid-read therefore never returns and never errors: the suspend
   * function hangs forever, the session stays `loading`, and the host's own
   * deadline expires with nothing to report. That is what an audiobook open over
   * a flaky link looks like from the outside.
   *
   * `readTimeout` is the socket timeout between reads, not a cap on total
   * transfer time, so a generous value is safe for a multi-gigabyte publication:
   * it only fires when no bytes arrive at all for that long. 30s of connect and
   * 60s of read is far longer than any healthy request needs and far shorter
   * than a user will wait.
   */
  private val httpClient = DefaultHttpClient(
    connectTimeout = 30.seconds,
    readTimeout = 60.seconds,
  )
  private val assetRetriever = AssetRetriever(
    reactContext.contentResolver,
    httpClient
  )
  private val publicationOpener = PublicationOpener(
    publicationParser = DefaultPublicationParser(
      context = reactContext,
      assetRetriever = assetRetriever,
      httpClient = httpClient,
      pdfFactory = PdfiumDocumentFactory(reactContext),
    )
  )

  fun locatorFromLinkOrLocator(
    location: LinkOrLocator?,
    publication: Publication,
  ): Locator? {

    if (location == null) return null

    when (location) {
      is LinkOrLocator.Link -> {
        return publication.locatorFromLink(location.link)
      }
      is LinkOrLocator.Locator -> {
        return location.locator
      }
    }

    return null
  }

  sealed class OpenResult {
    class Visual(val fragment: BaseReaderFragment) : OpenResult()
    object Audiobook : OpenResult()
  }

  suspend fun openPublication(
    fileName: String,
    initialLocation: LinkOrLocator?,
    callback: suspend (result: OpenResult) -> Unit,
    onFailure: (message: String) -> Unit = {}
  ) {
    val publication = retrievePublication(fileName)
    if (publication == null) {
      onFailure(
        PublicationUrlResolver.unsupportedScheme(fileName)
          ?.let { "Unsupported publication URL scheme: $it." }
          ?: "Unable to retrieve or parse publication: $fileName"
      )
      return
    }

    // Port of iOS checkIsReadable (ios/Reader/ReaderService.swift:183-192):
    // refuse DRM-restricted publications instead of opening a broken reader.
    if (publication.isRestricted) {
      val message = publication.protectionError?.message
        ?: "Publication is protected by DRM and cannot be opened."
      RNLog.w(reactContext, "Failed to open publication: $message")
      onFailure(message)
      return
    }

    val locator = locatorFromLinkOrLocator(initialLocation, publication)

    // Audiobooks don't get a native reader fragment: playback is owned by the
    // persistent [AudiobookSession] (mirroring iOS AudiobookSession), which
    // survives view teardown/re-entry. The host view merely observes.
    if (publication.conformsTo(Publication.Profile.AUDIOBOOK)) {
      AudiobookSession.adopt(publication, fileName, locator)
      callback.invoke(OpenResult.Audiobook)
      return
    }

    val readerFragment: BaseReaderFragment = when {
      // Mirror of iOS CBZModule.supports: DIVINA conformance or an
      // all-bitmap reading order routes to the bespoke comic reader.
      isComic(publication) -> {
        val frag = ComicReaderFragment.newInstance()
        frag.initFactory(publication, locator)
        frag
      }

      publication.conformsTo(Publication.Profile.PDF) -> {
        val frag = PdfReaderFragment.newInstance()
        frag.initFactory(publication, locator)
        frag
      }

      // Mirror of iOS EPUBModule.supports (ios/Reader/EPUB/EPUBModule.swift:11-14).
      // Previously this was a catch-all `else`, so a format the EPUB navigator
      // cannot render produced an empty reader instead of an error.
      isEpub(publication) -> {
        val frag = EpubReaderFragment.newInstance()
        frag.initFactory(publication, locator)
        frag
      }

      else -> {
        val message =
          "Publication is not a supported format: ${publication.metadata.title}."
        RNLog.w(reactContext, "Failed to open publication: $message")
        onFailure(message)
        return
      }
    }
    callback.invoke(OpenResult.Visual(readerFragment))
  }

  /**
   * Retrieves and parses a publication without deciding how it will be
   * presented. Shared by the visual reader fragments and the audiobook
   * session. Returns null (after logging) on retrieval or parse failure.
   */
  suspend fun retrievePublication(fileName: String): Publication? {
    val source = publicationSource(fileName) ?: return null

    val asset = assetRetriever
      .retrieve(
        source.url,
        source.formatHints
      )
      .onFailure {
        RNLog.w(reactContext, "Unable to retrieve publication asset: ${it.message}")
      }
      .getOrNull()
      ?: return null

    return publicationOpener
      .open(
        asset = asset,
        allowUserInteraction = false
      )
      .onFailure {
        RNLog.w(
          reactContext,
          "Error executing ReaderService.openPublication: ${it.message}"
        )
        // TODO: implement failure event
      }
      .getOrNull()
  }

  /**
   * Port of `CBZModule.supports` (ios/Reader/CBZ/CBZModule.swift:12-18):
   * DIVINA conformance, or every reading-order item is a bitmap/CBZ.
   */
  private fun isComic(publication: Publication): Boolean {
    val cbz = MediaType.CBZ
    return publication.conformsTo(Publication.Profile.DIVINA) ||
      publication.metadata.conformsTo.contains(Publication.Profile.DIVINA) ||
      publication.readingOrder.all { link ->
        link.mediaType?.isBitmap == true || link.mediaType?.matches(cbz) == true
      }
  }

  /**
   * Port of `EPUBModule.supports` (ios/Reader/EPUB/EPUBModule.swift:11-14): an
   * EPUB profile, or a reading order that is entirely HTML for the reflowable
   * navigator. Anything else has no reader and is reported rather than opened
   * into a blank view.
   */
  internal fun isEpub(publication: Publication): Boolean {
    val html = MediaType.HTML
    return publication.conformsTo(Publication.Profile.EPUB) ||
      publication.readingOrder.all { link ->
        link.mediaType?.matches(html) == true
      }
  }

  private fun publicationSource(fileName: String): PublicationSource? {
    if (PublicationUrlResolver.isRemoteUrl(fileName)) {
      val remoteUrl = AbsoluteUrl(fileName)
      if (remoteUrl == null) {
        RNLog.e(reactContext, "Invalid publication URL: $fileName")
        return null
      }
      return PublicationSource(
        url = remoteUrl,
        formatHints = PublicationUrlResolver.formatHintsForUrl(fileName)
      )
    }

    // iOS hands any absolute URL straight to Readium
    // (ios/Reader/ReaderService.swift:95-99). Android's asset retriever only
    // opens http(s), file, content and asset, so anything else is rejected here
    // with a readable reason rather than falling through to `File(fileName)`,
    // which reports "File does not exist" for what is really a bad scheme.
    PublicationUrlResolver.unsupportedScheme(fileName)?.let { scheme ->
      RNLog.e(reactContext, "Unsupported publication URL scheme: $scheme ($fileName)")
      return null
    }

    val publicationFile = File(fileName).absoluteFile
    if (!publicationFile.exists()) {
      RNLog.e(reactContext, "Failed to open publication: File does not exist: $fileName")
      return null
    }

    val publicationUrl = runCatching {
      publicationFile.toUrl(isDirectory = false)
    }
      .onFailure {
        RNLog.e(
          reactContext,
          "Invalid publication path: $fileName - ${it.message}"
        )
      }
      .getOrNull()
      ?: return null

    val fileExtension = publicationFile.extension
      .takeIf { it.isNotEmpty() }?.lowercase(Locale.ROOT)

    return PublicationSource(
      url = publicationUrl,
      formatHints = FormatHints(fileExtension = fileExtension?.let { FileExtension(it) })
    )
  }

  private data class PublicationSource(
    val url: AbsoluteUrl,
    val formatHints: FormatHints
  )
}
