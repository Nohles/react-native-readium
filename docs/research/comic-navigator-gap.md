# Research: Comic navigator gap — kotlin-toolkit image/DIVINA support vs iOS comic behavior

Resolves [Nohles/react-native-readium#6](https://github.com/Nohles/react-native-readium/issues/6) (part of #4).
Date: 2026-08-24. Research only; no feature implementation.

## One-line answer

**Exact parity is achievable, but not from the toolkit's navigator code as-is**: upstream `ImageNavigatorFragment` is an experimental bare-bones horizontal `ViewPager` with zero preference support, while the iOS "spec" (`ComicImageViewController.swift`) is a bespoke, preference-driven reader. The realistic path mirrors what iOS already did — a bespoke Android comic navigator built on toolkit primitives (shared/streamer/common) — which requires **no fork changes at all** for most gaps; fork changes are only needed if we insist the toolkit's own `navigator-image` module deliver the features.

## The iOS spec (parity bar)

The iOS comic reader does **not** use a Readium-provided navigator. `CBZModule.swift` (`ios/Reader/CBZ/CBZModule.swift:12-18`) routes any DIVINA-conforming or all-bitmap publication to a hand-written `ComicImageViewController` built directly on `ReadiumShared` + UIKit scroll/stack views. Landed in 2c0e7e6 ("feat: bring native comic reader to Thorium parity (#3)") plus 470fc47 and 3cd6740.

Concrete behaviors/preferences in `ios/Reader/CBZ/ComicImageViewController.swift`:

| Behavior | Where |
|---|---|
| Reading modes: paginated / continuous vertical / continuous horizontal / webtoon (driven by `Preferences.scroll` + `comicReadingMode`) | `isPaginatedMode` :358, `isHorizontalScrollMode` :366, `isWebtoonMode` :370, layout switch :224-261 |
| Double-page spread (`spread == "always"`), incl. RTL cover handling and step-2 paging | `isDoublePageMode` :362, `visiblePageIndices` :378-387, `goForward/goBackward` step :88-99 |
| Scale types `fitWidth` / `fitHeight` / `fitScreen` / `originalSize` with per-mode capping rules (height-capped when paginated or horizontal) | `displayedImageSize(for:viewport:)` :409-451 |
| `originalSize` never upscales (`min(scale, 1)`) unless width-driven | :435-446 |
| `comicStretchSmallPages` (allow upscale when enabled and scaleType ≠ originalSize) | :442-446 |
| `comicWidthLimitEnabled` / `comicWidthLimitPercent` applied only for fitWidth/fitScreen | :416-421 |
| Page gap px between pages/spread halves (`pageMargins * 16` stack spacing) | `gap` :389-391, used :229, :412-413 |
| Reading direction rtl/ltr from `readingProgression` | `isRTL` :374-376 |
| Theme/background color hex propagated to view, scroll view, stack, and each image view | `applyTheme` :401-407 |
| Image preload window ±N around current index (`comicImagePreloadAmount`, clamped 0–10), dedup via `loadingIndices` | `loadImages(around:)` :162-189 |
| Webtoon programmatic page-turn = % of viewport height (`comicScrollAmountPercent`, clamped 10–100) | `scrollWebtoon(forward:)` :453-460 |
| Scroll physics: no bounce when paginated; directional bounce + indicators in continuous modes | `applyScrollAxisPolicy` :462-484 |
| Content-offset clamping per mode | `clampContentOffsetForCurrentMode` :486-506 |
| Locator model: `position = index+1`, `totalProgression = index/(count-1)`, `progression = 0`; restore by `position` then href | `locator(for:)` :342-356, `index(for:)` :330-340 |
| Continuous-mode current-index tracking by nearest image center → live progression events | `updateCurrentIndexFromScrollPosition` :303-328 |

Platform-agnostic comic logic already lives in TypeScript and needs no native support: tap-zone shapes & action mapping (`resolveComicTapAction`), progress-bar type/position resolution, progress persistence keys — all in `src/interfaces/Comic.ts`. Note: the `linkColor` preference added in 2c0e7e6 is EPUB-side only and unused by the comic reader.

## Toolkit side (external/kotlin-toolkit @ f8e6f93d, develop tip)

- **No dedicated module.** `settings.gradle.kts` registers no image/DIVINA navigator; there is only a legacy package `readium/navigator/src/main/java/org/readium/r2/navigator/image/ImageNavigatorFragment.kt` inside the monolithic `:readium:navigator` module.
- **Experimental status confirmed.** Toolkit `README.md` marks Readium Divina 🚧 and CBZ 🚧; `ImageNavigatorFragment` opts into `@ExperimentalReadiumApi`/`@DelicateReadiumApi` (:57). This verifies the prior map finding ("SDK 3.3.0 natively covers audiobook + PDF, comic experimental").
- **What it has:** horizontal-only `R2ViewPager` pager of `R2CbzPageFragment`s; each page is a `PhotoView` (pinch-zoom, fit-center bitmap); RTL follows the *activity* layout direction, not a preference (`ImageNavigatorFragment.kt:122,190,204`); locator emission only on `onPageSelected`; positions come from `publication.positions()` (DIVINA profile maps to `PerResourcePositionsService` — `ReadiumWebPubParser.kt:111-112`). Parsing/sniffing for CBZ and DIVINA exists (`streamer/.../parser/image/ImageParser.kt`, shared sniffers) and works.
- **What it lacks:** everything else — no `EpubNavigatorFactory`-style factory, no `Preferences`/`Settings` types, no settings resolver/editor, no scroll/continuous modes, no spreads, no scale-type handling, no theme, no preload control.

## Gap table

Legend — toolkit support: ✅ native · 🟡 partial · ❌ none. "Fork change?" answers: would `Nohles/kotlin-toolkit` need changes if we build a bespoke app-layer navigator (A) vs if we upgrade the toolkit's `navigator-image` instead (B).

| # | Behavior | iOS reference | Toolkit support | Fork change A (bespoke nav) | Fork change B (toolkit nav) | Notes |
|---|---|---|---|---|---|---|
| 1 | CBZ/DIVINA parsing, sniffs, positions service | `CBZModule.swift:12-18` | ✅ | No | No | `ImageParser.kt`, `ReadiumWebPubParser.kt:111` (DIVINA → `PerResourcePositionsService`) work today |
| 2 | Paginated single-page mode | `ComicImageViewController.swift:358` | 🟡 | No | Partial | `ImageNavigatorFragment` pages horizontally but with fixed widget behavior; paginated-as-default is fine, everything else around it is missing |
| 3 | Double-page spread + RTL cover rule + step-2 paging | :88-99, :362, :378-387 | ❌ | No (build it) | **Yes** | B: replace `ViewPager` (or use ViewPager2/Compose) to render 1–2 items per screen; respect cover parity |
| 4 | Continuous vertical mode w/ nearest-index tracking | :230, :303-328, :478-483 | ❌ | No | **Yes** | B: abandon `ViewPager`; RecyclerView/ScrollView-based content |
| 5 | Continuous horizontal mode | :366-367, :287, :473-477 | ❌ | No | **Yes** | Same rewrite as #4 |
| 6 | Webtoon mode + %-of-viewport paged scrolling (`scrollAmountPercent`) | :453-460 | ❌ | No | **Yes** | Needs `OverflowController.moveForward/Backward` wired to fractional scrolls |
| 7 | Scale types fitWidth/fitHeight/fitScreen/originalSize + capping rules | :409-451 | 🟡 | No | **Yes** | PhotoView gives fit-center + zoom only; B needs a `ComicSettings.scaleType` computed in a resolver and applied per-page |
| 8 | Never-upscale default; `stretchSmallPages` override | :435-446 | ❌ | No | **Yes** | Pure sizing math; trivial once #7 exists |
| 9 | Width-limit % (fitWidth/fitScreen only) | :416-421 | ❌ | No | **Yes** | Same |
| 10 | Page gap px between pages/spread halves | :229, :389-391 | ❌ | No | **Yes** | `R2ViewPager` exposes no gap pref; B: inter-item decoration/spacing |
| 11 | Reading direction ltr/rtl as a *preference* | :374-376 | 🟡 | No | **Yes** | Toolkit uses activity layout direction (`ImageNavigatorFragment.kt:122`); must read publication/preference instead |
| 12 | Theme/background color across reader surfaces | :401-407 | ❌ | No | **Yes** | Could be styled app-side even under option B, but B should accept a background pref |
| 13 | Configurable preload amount (±N, dedup) | :162-189 | 🟡 | No | Optional | ViewPager preloads adjacent fragments implicitly; bespoke nav replicates iOS windowing exactly; B: expose offscreen-limit pref |
| 14 | Locator contract (position=index+1, totalProgression formula, restore-by-position) | :330-356 | 🟡 | No | Partial | `publication.positions()` ordering matches reading order; verify totalProgression edge cases (single-resource books) match iOS formula |
| 15 | Live progression events during continuous scroll | :303-328 | ❌ | No | **Yes** | Pager only emits on discrete page selection |
| 16 | Scroll physics (bounce/paging/clamping policy) | :462-506 | 🟡 | No | Yes | Falls out of widget choice in #3–5 |
| 17 | Tap zones, progress bar type/position/resolution, auto-scroll prefs, chapter boundaries, progress persistence | `src/interfaces/Comic.ts` | n/a | No | No | Handled in the shared TS layer on both platforms; not toolkit concerns |

## Recommendation framing for follow-up tickets

Two viable strategies (the choice belongs to @Nohles):

1. **Bespoke app-layer navigator (recommended):** port `ComicImageViewController`'s model to a Kotlin class in `android/src/main/java/com/reactnativereadium/reader/` alongside `EpubReaderFragment.kt`, consuming only `readium-shared`, `readium-streamer`, and `readium-navigators-common` primitives (`PreferencesController`, `NavigationController`, `OverflowController` — all reusable as-is). **Zero fork changes.** This is also the closest architectural mirror of iOS, where the comic reader was deliberately built without a Readium navigator.
2. **Fork-change route:** if the toolkit's `navigator-image` package must become a real navigator, every ❌ row above becomes a fork proposal: new `ImagePreferences`/`ImageSettings` + resolver/editor mirroring `epub/EpubPreferences*`, replacement of `ViewPager` with a layout supporting spreads + continuous axes, scale-type math in the page fragment, and preference-driven direction/theme/gap/preload. That is effectively re-implementing option 1 inside the fork.

Either way, rows 1, 14 (mostly), and 17 cost nothing extra; the entire behavioral surface of rows 3–13, 15–16 is absent from the toolkit and must be written once, somewhere.

## Sources

- `ios/Reader/CBZ/CBZModule.swift`, `ios/Reader/CBZ/ComicImageViewController.swift` (this repo)
- `src/interfaces/Comic.ts`, `src/utils/comicPreferences.ts`, `src/__tests__/comicPreferences.test.ts` (this repo)
- Commits 2c0e7e6, 470fc47, 3cd6740, 25f472b (fork consumed as Gradle source dependency)
- `external/kotlin-toolkit`: `settings.gradle.kts`, `README.md` (format table), `CHANGELOG.md`, `readium/navigator/src/main/java/org/readium/r2/navigator/image/ImageNavigatorFragment.kt`, `.../pager/R2CbzPageFragment.kt`, `.../pager/R2ViewPager.kt`, `readium/streamer/src/main/java/org/readium/r2/streamer/parser/image/ImageParser.kt`, `.../parser/readium/ReadiumWebPubParser.kt:111`, `readium/navigators/common/src/main/java/org/readium/navigator/common/{PreferencesController,OverflowController,NavigationController}.kt`
