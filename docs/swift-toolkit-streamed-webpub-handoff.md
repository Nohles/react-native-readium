# Handoff: Streamed WebPub / `formatNotSupported` on iOS

This document summarizes investigation in **react-native-readium** so work can continue in **[Nohles/swift-toolkit](https://github.com/Nohles/swift-toolkit)** (fork used by CocoaPods `3.9.1-nohles.2`, not upstream `readium/swift-toolkit`).

## Symptom (Expo example)

- **JS layer:** `[PublicationDebug]` manifest probe succeeds (HTTP 200, valid JSON, `readingOrder`, title, first resource `HEAD` OK).
- **Native iOS:** User sees an alert; watchdog logs `onPublicationReady not received within 12s`.
- **Error string:** `ReaderError.formatNotSupported` → `NSLocalizedString("reader_error_formatNotSupported", …)` (raw key if the app bundle has no `Localizable.strings` for NitroReadium).
- **Metro / Xcode:** `[ReadiumNative] Failed to open publication: …` with the same localized key as description.

Repro in this repo was tied to a **local Reader proxy** manifest, e.g.:

`http://localhost:3000/readium/<uuid>/webpub/<...>/manifest.json`

(entry `reaader-test` in `apps/example-expo/types.ts`).

## Call chain in react-native-readium (context only)

1. `ReadiumView` → `HybridReadiumView.loadBook` → `ReaderService.buildViewController`.
2. `ReaderService.openPublication` uses `AssetRetriever.retrieve(url:hints:)` then `PublicationOpener.open`.
3. For URLs whose last path segment is `manifest.json`, hints are set to `FormatHints(mediaType: .readiumWebPubManifest)` — see `ios/Reader/ReaderService.swift` (`formatHints(for:)`).

So the failure is either **asset retrieval / format sniffing** or **opening / parser** inside the toolkit, not in the JS probe.

## Fork version in use

- Podspec: `react-native-readium.podspec` pins **ReadiumShared / ReadiumStreamer / ReadiumNavigator / ReadiumInternal** to **`3.9.1-nohles.2`**.
- Tag on fork: **`3.9.1-nohles.2`** → commit `9759150` (on `develop` at time of investigation).

Always diff against **this tag** (or newer fork tags), not only upstream Readium.

## Strong hypothesis: missing `self` link breaks RWPM sniffing

In **`RWPMFormatSniffer`** (`Sources/Shared/Toolkit/Format/Sniffers/RWPMFormatSniffer.swift` on the fork), JSON blobs are only classified as the Web Publication manifest format when **all** of the following hold after parsing a `Manifest`:

- `format` refines JSON (sniff pipeline).
- Parsed JSON yields a valid `Manifest`.
- For the generic WebPub branch:  
  `manifest.linkWithRel(.self)?.mediaType?.matches(.readiumWebPubManifest) == true`

If there is **no** `rel: "self"` link, or it does not match `application/webpub+json`, sniffing returns **`nil`**. Downstream, **`AssetRetriever`** ends up with a format that **`hasSpecification` is false** and returns **`AssetRetrieveURLError.formatNotSupported`** — which surfaces as **`ReaderError.formatNotSupported`** in the app.

**Empirical check on the failing proxy manifest:** `links` contained only Readium service entries (e.g. `~readium/positions.json`) and **no** `self` link:

```text
self links: []
```

**Contrast with a known-good streamed manifest** (Readium publication server, Moby Dick): `links` includes a `self` link with `type: application/webpub+json`.

The fork’s **Migration Guide** (`docs/Migration Guide.md`, section *Streamed Readium Web Publications (EPUB profile)*) states that the manifest **must** include a **`self`** link so the toolkit can resolve the publication **base URL** for relative reading-order `href`s.

### Related toolkit behavior (for implementers)

- **`ReadiumWebPubParser`** (`Sources/Streamer/Parser/Readium/ReadiumWebPubParser.swift`): for a single-resource asset, it requires `format.conformsTo(.rwpm)` before parsing; RWPM classification depends on the sniffer path above.
- **`Manifest.baseURL`** is derived from the `self` link (`Sources/Shared/Publication/Manifest.swift`).
- **`HTTPContainer`** resolves relative URLs against `baseURL`; if `baseURL` is wrong or missing, resource loading can break even after open — but here the failure appears **before** a successful open due to sniffing.

## Secondary issue: untranslated alert strings

`AppModule.presentError` uses `NSLocalizedString("error_title", …)` etc. If the host app does not merge **NitroReadium** (or Readium) **Localizable.strings**, the UI shows raw keys. That is separate from the publication failure but confused debugging.

## What the web stack in this repo does differently

`web/utils/manifestFetcher.ts` builds a manifest link from the request URL and calls **`manifest.setSelfLink(selfLink)`** after fetch — so the **web** reader always has a synthetic `self` even when the server JSON omits it. **iOS does not** inject that; it relies on the manifest JSON (and sniffing rules) as delivered.

**Implication:** Proxies or converters that serve RWPM JSON **without** a proper `self` link are fragile on iOS with the current fork behavior.

## Suggested directions in Nohles/swift-toolkit

Pick one or combine:

1. **Contract / server-side:** Document that streamed manifests **must** include a `self` link (absolute URL, `application/webpub+json`), matching the migration guide; fix the Reader/proxy to emit it (same as publication-server behavior).

2. **Sniffer / retriever (toolkit):** When the request URL is already the manifest URL and hints include `.readiumWebPubManifest`, treat missing `self` as **non-fatal** for format classification — e.g. infer RWPM + synthetic `self` from the retrieval URL (align with web `setSelfLink` behavior). Evaluate impact on `Manifest.baseURL` and `HTTPContainer` resolution.

3. **Diagnostics:** If `retrieve` fails with `formatNotSupported`, log whether `Manifest` decoded, whether `linkWithRel(.self)` was nil, and response `Content-Type` — to distinguish sniff failure from parser/open failure.

4. **Tests:** Add a **unit or integration** test in the fork: streamed manifest **without** `self` but with EPUB profile + HTML reading order, opened via `AssetRetriever` + `PublicationOpener` with `FormatHints(mediaType: .readiumWebPubManifest)`, matching `ReadiumWebPubParserIntegrationTests` style (`Tests/StreamerTests/Parser/Readium/ReadiumWebPubParserIntegrationTests.swift`).

## Reference files (fork, tag `3.9.1-nohles.2`)

| Area | Path |
|------|------|
| RWPM sniff / `self` gate | `Sources/Shared/Toolkit/Format/Sniffers/RWPMFormatSniffer.swift` |
| Asset retrieval failure | `Sources/Shared/Toolkit/Data/Asset/AssetRetriever.swift` |
| WebPub parser | `Sources/Streamer/Parser/Readium/ReadiumWebPubParser.swift` |
| `baseURL` | `Sources/Shared/Publication/Manifest.swift` |
| Remote resources | `Sources/Shared/Toolkit/HTTP/HTTPContainer.swift` |
| Migration / `self` requirement | `docs/Migration Guide.md` (streamed Web Pub section) |
| Live smoke tests | `Tests/StreamerTests/Parser/Readium/ReadiumWebPubParserIntegrationTests.swift` |

## Quick verification commands (from any machine with the proxy running)

```bash
# Replace with your manifest URL
MANIFEST='http://localhost:3000/.../manifest.json'

# Should list a self link for parity with publication-server manifests
curl -s "$MANIFEST" | python3 -c "import json,sys; m=json.load(sys.stdin); print([l for l in m.get('links',[]) if (l.get('rel')=='self' or (isinstance(l.get('rel'),list) and 'self' in l.get('rel',[])))])"
```

Empty `[]` here is consistent with the **`RWPMFormatSniffer`** path returning no WebPub format → **`formatNotSupported`**.

---

*Prepared from investigation in react-native-readium; continue in [Nohles/swift-toolkit](https://github.com/Nohles/swift-toolkit) at tag **3.9.1-nohles.2** or later fork releases.*
