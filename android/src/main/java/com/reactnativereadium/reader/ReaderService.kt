package com.reactnativereadium.reader

import com.facebook.react.bridge.ReactApplicationContext
import com.facebook.react.util.RNLog
import com.reactnativereadium.utils.LinkOrLocator
import java.io.File
import java.net.URI
import java.util.Locale
import org.readium.r2.shared.publication.Locator
import org.readium.r2.shared.publication.Publication
import org.readium.r2.shared.util.FileExtension
import org.readium.r2.shared.util.Url
import org.readium.r2.shared.util.asset.AssetRetriever
import org.readium.r2.shared.util.format.FormatHints
import org.readium.r2.shared.util.http.DefaultHttpClient
import org.readium.r2.shared.util.mediatype.MediaType
import org.readium.r2.shared.util.toUrl
import org.readium.r2.streamer.PublicationOpener
import org.readium.r2.streamer.parser.DefaultPublicationParser


class ReaderService(
  private val reactContext: ReactApplicationContext
) {
  private val httpClient = DefaultHttpClient()
  private val assetRetriever = AssetRetriever(
    reactContext.contentResolver,
    httpClient
  )
  private val publicationOpener = PublicationOpener(
    publicationParser = DefaultPublicationParser(
      context = reactContext,
      assetRetriever = assetRetriever,
      httpClient = httpClient,
      pdfFactory = null,
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

  suspend fun openPublication(
    fileName: String,
    initialLocation: LinkOrLocator?,
    callback: suspend (fragment: BaseReaderFragment) -> Unit
  ) {
    val source = publicationSource(fileName) ?: return

    val asset = assetRetriever
      .retrieve(
        source.url,
        source.formatHints
      )
      .onFailure {
        RNLog.w(reactContext, "Unable to retrieve publication asset: ${it.message}")
      }
      .getOrNull()
      ?: return

    publicationOpener
      .open(
        asset = asset,
        allowUserInteraction = false
      )
      .onSuccess {
        val locator = locatorFromLinkOrLocator(initialLocation, it)
        val readerFragment = EpubReaderFragment.newInstance()
        readerFragment.initFactory(it, locator)
        callback.invoke(readerFragment)
      }
      .onFailure {
        RNLog.w(
          reactContext,
          "Error executing ReaderService.openPublication: ${it.message}"
        )
        // TODO: implement failure event
      }
  }

  private fun publicationSource(fileName: String): PublicationSource? {
    if (isRemoteUrl(fileName)) {
      val remoteUrl = Url(fileName)
      if (remoteUrl == null) {
        RNLog.e(reactContext, "Invalid publication URL: $fileName")
        return null
      }
      return PublicationSource(
        url = remoteUrl,
        formatHints = formatHintsForUrl(fileName)
      )
    }

    val publicationFile = File(fileName).absoluteFile
    if (!publicationFile.exists()) {
      RNLog.e(reactContext, "Failed to open publication: File does not exist: $fileName")
      return null
    }

    val publicationUrl = runCatching {
      publicationFile.toUrl()
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

  private fun isRemoteUrl(fileName: String): Boolean =
    runCatching {
      val uri = URI(fileName)
      uri.scheme == "http" || uri.scheme == "https"
    }.getOrDefault(false)

  private fun formatHintsForUrl(url: String): FormatHints {
    val path = url.substringBefore('?').substringBefore('#')
    if (!path.endsWith("/manifest.json") && !path.endsWith("manifest.json")) {
      return FormatHints()
    }

    return FormatHints(mediaType = MediaType("application/readium-webpub+json")!!)
  }

  private data class PublicationSource(
    val url: Url,
    val formatHints: FormatHints
  )

  sealed class Event {

    class ImportPublicationFailed(val errorMessage: String?) : Event()

    object UnableToMovePublication : Event()

    object ImportPublicationSuccess : Event()

    object ImportDatabaseFailed : Event()

    class OpenBookError(val errorMessage: String?) : Event()
  }
}
