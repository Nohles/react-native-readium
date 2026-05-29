# react-native-readium

[![NPM version](https://img.shields.io/npm/v/react-native-readium.svg?color=success&label=npm%20package&logo=npm)](https://www.npmjs.com/package/react-native-readium)
[![Commitizen friendly](https://img.shields.io/badge/commitizen-friendly-brightgreen.svg)](http://commitizen.github.io/cz-cli/)
![PRs welcome!](https://img.shields.io/badge/PRs-welcome-brightgreen.svg)
![This project is released under the MIT license](https://img.shields.io/badge/license-MIT-blue.svg)

---

## Have A Bug/Feature You Care About?

We :heart: open source. We work on the things that are important to us when
we're able to work on them. Have an issue you care about?

- [Dive Into The Code!](CONTRIBUTING.md)
- [Sponsor Your Issue](#sponsor-the-library)

---

## Overview

A react-native wrapper for https://readium.org/. At a high level this package
allows you to do things like:

- Render an ebook view.
- Open streamed [Readium Web Publications](https://readium.org/webpub-manifest/) via a remote `manifest.json` URL (web and iOS).
- Register for location changes (as the user pages through the book).
- Access publication metadata including table of contents, positions, and more via the `onPublicationReady` callback
- Control settings of the Reader. Things like:
  - Dark Mode, Light Mode, Sepia Mode
  - Font Size
  - Page Margins
  - More (see the `Settings` documentation in the [API section](#api))
- Etc. (read on for more details. :book:)

## Table of Contents

- [Installation](#installation)
- [Usage](#usage)
  - [Streamed Web Publications (manifest.json)](#streamed-web-publications-manifestjson)
- [Supported Formats & DRM](#supported-formats--drm)
- [API](#api)
- [Contributing](#contributing)
- [Release](#release)
- [License](#license)

| Dark Mode                                                                                        | Light Mode                                                                                         |
| ------------------------------------------------------------------------------------------------ | -------------------------------------------------------------------------------------------------- |
| ![Dark Mode](https://github.com/5-stones/react-native-readium/blob/main/docs/demo-dark-mode.gif) | ![Light Mode](https://github.com/5-stones/react-native-readium/blob/main/docs/demo-light-mode.gif) |

## Installation

#### Prerequisites

1. **iOS**: Requires an iOS target >= `16.4` (see the iOS section for more details).
2. **Android**: Requires `compileSdkVersion` >= `31` (see the Android section for more details).

This library uses [Nitro Modules](https://nitro.margelo.com/) and supports both the old and new React Native architectures.

#### Install Module

**NPM**

```sh
npm install react-native-readium react-native-nitro-modules
```

**Yarn**

```sh
yarn add react-native-readium react-native-nitro-modules
```

#### iOS

Requirements:

- Minimum iOS deployment target: iOS 16.4
- Swift compiler: Swift 6.0
- Xcode: Xcode 16.2 (or newer)

The Readium pods live in a custom spec repo, so you need to add the Readium
source to your `Podfile` ([see more on that here](https://github.com/readium/swift-toolkit/issues/38)).

##### Breaking change when upgrading from v4 to v5!

If you are migrating from v4 to v5, please note that you must update your iOS
Podfile to add the Readium spec repo `source` and the `readium_pods` /
`readium_post_install` helpers shown below.

```rb
# ./ios/Podfile
source 'https://github.com/Nohles/podspecs'
source 'https://cdn.cocoapods.org/'

...

platform :ios, '16.4'

...

target 'ExampleApp' do
  config = use_native_modules!
  ...
  readium_pods
  ...
  post_install do |installer|
    react_native_post_install(installer, ...)
    readium_post_install(installer)
  end
end
```

Finally, install the pods:

`pod install`

#### Android

##### Breaking change when upgrading from v4 to v5!

This release upgrades the Android native implementation to a newer Readium Kotlin Toolkit.
Most apps won’t need code changes, but your **Android build configuration** might.

Requirements:

- **JDK 17** is required to build the Android app (the library targets Java/Kotlin 17).
- **compileSdkVersion** must be >= `31`.

If you're not using `compileSdkVersion` >= 31 you'll need to update that:

```groovy
// android/build.gradle
...
buildscript {
    ...
    ext {
        ...
        compileSdkVersion = 31
...
```

##### Core library desugaring (may be required)

If you see build errors related to missing Java 8+ APIs (commonly `java.time.*`), enable
core library desugaring in your app:

```groovy
// android/app/build.gradle
android {
  ...
  compileOptions {
    coreLibraryDesugaringEnabled true
  }
}

dependencies {
  coreLibraryDesugaring "com.android.tools:desugar_jdk_libs:2.1.2"
}
```

##### Expo managed workflow

If your app uses Expo managed workflow (native `android/` is generated via `prebuild` / EAS),
apply the desugaring settings through an Expo config plugin (or `expo-build-properties`) so
they persist across builds.

#### Expo SDK 56 / development builds

This package contains native Readium and Nitro code and therefore does **not** run in Expo Go.
Use an Expo development build or an EAS build. Expo SDK 56 apps must target iOS 16.4 or newer.

The package exports a config plugin that installs the Readium CocoaPods source/helpers and
Android EPUB desugaring setup during `expo prebuild`:

```json
{
  "expo": {
    "plugins": [
      [
        "expo-build-properties",
        { "ios": { "deploymentTarget": "16.4" } }
      ],
      "react-native-readium"
    ]
  }
}
```

See `apps/example-expo` for an Expo SDK 56 development-build consumer.

## Usage

### Basic Example

```tsx
import React, { useState } from 'react';
import { ReadiumView } from 'react-native-readium';
import type { File } from 'react-native-readium';

const MyComponent: React.FC = () => {
  const [file] = useState<File>({
    url: SOME_LOCAL_FILE_URL,
  });

  return <ReadiumView file={file} />;
};
```

### Using Publication Metadata

Access the table of contents, positions, and metadata when the publication is ready:

```tsx
import React, { useState } from 'react';
import { ReadiumView } from 'react-native-readium';
import type { File, PublicationReadyEvent } from 'react-native-readium';

const MyComponent: React.FC = () => {
  const [file] = useState<File>({
    url: SOME_LOCAL_FILE_URL,
  });

  const [toc, setToc] = useState([]);

  const handlePublicationReady = (event: PublicationReadyEvent) => {
    console.log('Title:', event.metadata.title);
    console.log('Author:', event.metadata.author);
    console.log('Table of Contents:', event.tableOfContents);
    console.log('Positions:', event.positions);

    setToc(event.tableOfContents);
  };

  return (
    <ReadiumView file={file} onPublicationReady={handlePublicationReady} />
  );
};
```

### Streamed Web Publications (manifest.json)

A [Readium Web Publication](https://readium.org/webpub-manifest/) is an unpacked EPUB or audiobook served over HTTP. Pass the full URL to `manifest.json` as `File.url` — not the `.epub` file itself.

```tsx
import { ReadiumView } from 'react-native-readium';
import type { File } from 'react-native-readium';

const file: File = {
  url: 'https://readium.org/webpub-manifest/examples/MobyDick/manifest.json',
};

export function WebPubReader() {
  return <ReadiumView file={file} />;
}
```

**Platform behavior**

- **Web** — `File.url` must be an HTTPS `manifest.json` URL. The reader fetches the manifest and resources from its base URL. The server must allow your origin via CORS.
- **iOS** — `File.url` can be a remote `manifest.json` URL (streamed WebPub) or a local path to a packaged EPUB, CBZ, PDF, or audiobook file.
- **Android** — `File.url` must be a local path to a packaged EPUB on disk. Streamed manifest URLs are not supported yet; download the EPUB first if needed.

**Self-hosting**

Many samples below come from the [Readium publication server](https://publication-server.readium.org/). To host your own unpacked publications, see the [dita-streamer server example](https://github.com/d-i-t-a/R2D2BC/blob/production/examples/server.ts) (built on the Readium [r2-\*-js](https://github.com/readium?q=js) libraries).

#### Sample manifest URLs

Copy any of these into `File.url` for quick testing:

| Category | Title | Manifest URL |
| -------- | ----- | ------------ |
| Streamed EPUB | Moby Dick | `https://publication-server.readium.org/webpub/Z3M6Ly9yZWFkaXVtLXBsYXlncm91bmQtZmlsZXMvZGVtby9tb2J5LWRpY2suZXB1Yg/manifest.json` |
| Official example | Moby Dick (Readium) | `https://readium.org/webpub-manifest/examples/MobyDick/manifest.json` |
| Audiobook | Flatland | `https://readium.org/webpub-manifest/examples/Flatland/manifest.json` |
| Accessibility | DAISY Basic Functionality v2.0.0 | `https://publication-server.readium.org/webpub/aHR0cHM6Ly9naXRodWIuY29tL2RhaXN5L2VwdWItYWNjZXNzaWJpbGl0eS10ZXN0cy9yZWxlYXNlcy9kb3dubG9hZC9mdW5kYW1lbnRhbC0yLjAvRnVuZGFtZW50YWwtQWNjZXNzaWJpbGl0eS1UZXN0cy1CYXNpYy1GdW5jdGlvbmFsaXR5LXYyLjAuMC5lcHVi/manifest.json` |
| RTL / CJK | Haruko | `https://publication-server.readium.org/webpub/aHR0cHM6Ly9naXRodWIuY29tL0lEUEYvZXB1YjMtc2FtcGxlcy9yZWxlYXNlcy9kb3dubG9hZC8yMDIzMDcwNC9oYXJ1a28taHRtbC1qcGVnLmVwdWI/manifest.json` |

The example apps maintain longer lists of sample URLs:

- [`apps/example-expo/types.ts`](apps/example-expo/types.ts) — Expo SDK 56 development build
- [`apps/example-native/src/App.tsx`](apps/example-native/src/App.tsx) — native example
- [`apps/example-nextjs/components/ReaderApp.tsx`](apps/example-nextjs/components/ReaderApp.tsx) — web (CDN-hosted manifests)

For a proxied audiobook sample (The Martian), see [`apps/example-expo/README.md`](apps/example-expo/README.md).

### Persistent Audiobook Playback (iOS)

Use `ReadiumAudio` for audiobook playback that continues when the full reader view is
unmounted, such as a mini-player displayed elsewhere in an Expo app:

```tsx
import { ReadiumAudio } from 'react-native-readium';

const unsubscribe = ReadiumAudio.subscribe((state) => {
  console.log(state.status, state.position);
});

await ReadiumAudio.open({ url: audiobookManifestUrl });
ReadiumAudio.play();

// Later:
ReadiumAudio.pause();
unsubscribe();
```

`ReadiumAudio`, audiobook rendering, PDF, and CBZ are iOS-only for this release.
Android continues to support EPUB reading; non-EPUB Android support is deferred.

When reopening the full reader from a mini-player, pass
`reopenActiveAudiobook` to `ReadiumView` to attach the current audiobook
session instead of creating a new one.

### Highlights & Note Taking

![Decorators](https://github.com/5-stones/react-native-readium/blob/main/docs/demo-decorators.gif)

The `selectionActions`, `decorations`, `onSelectionAction`, and `onDecorationActivated` props work together to build highlighting and note-taking features. Here's how the flow works:

1. **Define selection actions** to add custom items to the text selection context menu.
2. **Handle `onSelectionAction`** to capture what the user selected and which action they chose.
3. **Create a `Decoration`** from the selection's locator and add it to your `decorations` state.
4. **Handle `onDecorationActivated`** to let users tap existing highlights to edit or delete them.

```tsx
import React, { useState, useCallback } from 'react';
import { ReadiumView } from 'react-native-readium';
import type {
  File,
  Decoration,
  DecorationGroup,
  SelectionAction,
  SelectionActionEvent,
  DecorationActivatedEvent,
} from 'react-native-readium';

// Register a "Highlight" action in the text selection context menu
const selectionActions: SelectionAction[] = [
  { id: 'highlight', label: 'Highlight' },
];

const MyReader: React.FC<{ file: File }> = ({ file }) => {
  const [decorations, setDecorations] = useState<DecorationGroup[]>([
    { name: 'highlights', decorations: [] },
  ]);

  // User tapped "Highlight" in the selection menu
  const handleSelectionAction = useCallback((event: SelectionActionEvent) => {
    if (event.actionId === 'highlight') {
      const newHighlight: Decoration = {
        id: `highlight-${Date.now()}`,
        locator: event.locator,
        style: {
          type: 'highlight',
          tint: '#FFFF00',
        },
        extras: {
          note: '',
          selectedText: event.selectedText,
        },
      };

      setDecorations((prev) =>
        prev.map((g) =>
          g.name === 'highlights'
            ? { ...g, decorations: [...g.decorations, newHighlight] }
            : g
        )
      );
    }
  }, []);

  // User tapped on an existing highlight
  const handleDecorationActivated = useCallback(
    (event: DecorationActivatedEvent) => {
      const { decoration } = event;
      // Show an edit/delete dialog for this highlight
      console.log('Tapped highlight:', decoration.id);
      console.log('Note:', decoration.extras?.note);
    },
    []
  );

  return (
    <ReadiumView
      file={file}
      decorations={decorations}
      selectionActions={selectionActions}
      onSelectionAction={handleSelectionAction}
      onDecorationActivated={handleDecorationActivated}
    />
  );
};
```

Key concepts:

- **`DecorationGroup`**: A named group of decorations (e.g. `"highlights"`, `"underlines"`). Pass an array of groups to the `decorations` prop.
- **`Decoration`**: A single visual annotation. It references a location in the publication via a `Locator` and defines its appearance via a `DecorationStyle` (supported types: `"highlight"`, `"underline"`).
- **`extras`**: An optional `Record<string, string>` on each `Decoration` where you can store arbitrary metadata like notes, timestamps, or the original selected text.
- **`onSelectionChange`**: Fires as the user adjusts their text selection, useful for showing a live preview or tracking selection state.

[Take a look at the Example App](https://github.com/5-stones/react-native-readium/blob/main/apps/example-native/src/App.tsx) for a full implementation with color picking, note editing, and highlight management.

## Supported Formats & DRM

#### Format Support

| Format     | Platforms    | Notes                                                          |
| ---------- | ------------ | -------------------------------------------------------------- |
| EPUB 2 / 3 | iOS, Android | Rendering, navigation, preferences, highlights, and selection actions. Packaged EPUB on all platforms; streamed WebPub via `manifest.json` on web and iOS only (see [Streamed Web Publications](#streamed-web-publications-manifestjson)). |
| Audiobook  | iOS          | Playback and persistent `ReadiumAudio` session; Android is deferred. |
| PDF        | iOS          | Rendering and navigation; Android is deferred. |
| CBZ        | iOS          | Rendering, navigation, comic canvas presets, fit, spread, and reading direction through Readium's EPUB navigator; Android is deferred. |

**Missing a format you need?** Reach out and see if it can be added to the roadmap.

#### CBZ / Comic Canvas Presets

CBZ publications can be tuned with the same navigator preferences used by fixed-layout content. For convenience, `createComicPreferences` maps comic concepts onto Readium preferences:

```tsx
import {
  ReadiumView,
  comicProgressFromLocator,
  comicProgressStorageKey,
  createComicPreferences,
} from 'react-native-readium';

const preferences = createComicPreferences({
  canvasMode: 'webtoon', // 'webtoon' | 'singlePage' | 'doublePage'
  readingDirection: 'rtl', // 'ltr' western comics, 'rtl' manga
  fit: 'width', // 'width' | 'height' | 'screen' | 'actualSize'
});

<ReadiumView
  file={file}
  preferences={preferences}
  onLocationChange={(locator) => {
    const progress = comicProgressFromLocator(locator);
    if (!progress) return;

    const key = comicProgressStorageKey(file.url, progress.href);
    saveProgress(key, progress);
  }}
/>;
```

Preset mapping:

| Canvas mode | Readium preferences |
| ----------- | ------------------- |
| `webtoon` | `scroll: true`, `spread: "never"`, `fit: "width"` |
| `singlePage` | `scroll: false`, `spread: "never"` |
| `doublePage` | `scroll: false`, `spread: "always"` |

The native navigator owns pinch, double-tap, pointer/wheel, and keyboard navigation where supported by the platform. Sync remains app-owned: persist the `ComicProgress` payload locally or upload it as your encrypted/iCloud/Drive blob, then pass `comicLocatorFromProgress(progress)` as `file.initialLocation` when reopening.

#### DRM Support

DRM is not supported at this time. However, there is a clear path to [support it via LCP](https://www.edrlab.org/readium-lcp/) and the intention is to eventually implement it.

## API

#### View Props

| Name                    | Type                                                                                                                                                | Optional           | Description                                                                                                                                                                                                                                                                         |
| ----------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------ | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `file`                  | [`File`](https://github.com/5-stones/react-native-readium/blob/main/src/interfaces/File.ts)                                                         | :x:                | Publication source: local path to a packaged file on native, or an HTTPS `manifest.json` URL for streamed WebPub (web and iOS). Use `File.initialLocation` to set the reader's position on mount. See [Streamed Web Publications](#streamed-web-publications-manifestjson). |
| `preferences`           | [`Partial<Preferences>`](https://github.com/readium/swift-toolkit/blob/main/docs/Guides/Navigator%20Preferences.md#appendix-preference-constraints) | :white_check_mark: | An object that allows you to control various aspects of the reader's UI (epub only)                                                                                                                                                                                                 |
| `decorations`           | [`DecorationGroup[]`](https://github.com/5-stones/react-native-readium/blob/main/src/interfaces/Decoration.ts)                                      | :white_check_mark: | An array of decoration groups to render in the publication (e.g. highlights, underlines).                                                                                                                                                                                           |
| `selectionActions`      | [`SelectionAction[]`](https://github.com/5-stones/react-native-readium/blob/main/src/interfaces/SelectionAction.ts)                                 | :white_check_mark: | Custom actions to show in the context menu when the user selects text.                                                                                                                                                                                                              |
| `style`                 | `ViewStyle`                                                                                                                                         | :white_check_mark: | A traditional style object.                                                                                                                                                                                                                                                         |
| `onLocationChange`      | `(locator: Locator) => void`                                                                                                                        | :white_check_mark: | A callback that fires whenever the location is changed (e.g. the user transitions to a new page).                                                                                                                                                                                   |
| `onPublicationReady`    | `(event: PublicationReadyEvent) => void`                                                                                                            | :white_check_mark: | A callback that fires once the publication is loaded and provides access to the table of contents, positions, and metadata. See the [`PublicationReadyEvent`](https://github.com/5-stones/react-native-readium/blob/main/src/interfaces/PublicationReady.ts) interface for details. |
| `onDecorationActivated` | `(event: DecorationActivatedEvent) => void`                                                                                                         | :white_check_mark: | A callback that fires when a user taps on a decoration (e.g. a highlight).                                                                                                                                                                                                          |
| `onSelectionChange`     | `(event: SelectionEvent) => void`                                                                                                                   | :white_check_mark: | A callback that fires when the user's text selection changes.                                                                                                                                                                                                                       |
| `onSelectionAction`     | `(event: SelectionActionEvent) => void`                                                                                                             | :white_check_mark: | A callback that fires when the user taps a custom selection action from the context menu.                                                                                                                                                                                           |

#### Ref Methods

The `ReadiumView` component accepts a ref that exposes imperative navigation methods:

```tsx
import React, { useRef } from 'react';
import { ReadiumView } from 'react-native-readium';
import type { ReadiumViewRef, Locator } from 'react-native-readium';

const MyComponent: React.FC = () => {
  const ref = useRef<ReadiumViewRef>(null);

  const goToChapter = (locator: Locator) => {
    ref.current?.goTo(locator);
  };

  return (
    <>
      <ReadiumView ref={ref} file={file} />
      <Button title="Next" onPress={() => ref.current?.goForward()} />
      <Button title="Previous" onPress={() => ref.current?.goBackward()} />
    </>
  );
};
```

| Method          | Description                                                                      |
| --------------- | -------------------------------------------------------------------------------- |
| `goTo(locator)` | Navigate to a specific location in the publication (e.g. a chapter or bookmark). |
| `goForward()`   | Navigate forward in the publication (e.g. next page).                            |
| `goBackward()`  | Navigate backward in the publication (e.g. previous page).                       |

#### File URL by platform

See [Streamed Web Publications (manifest.json)](#streamed-web-publications-manifestjson) for platform rules, sample manifest URLs, and self-hosting guidance.

## Contributing

See the [contributing guide](CONTRIBUTING.md) to learn how to contribute to the
repository and the development workflow.

## Release

The standard release command for this project is:

```
yarn version
```

This command will:

1. Generate/update the Changelog
1. Bump the package version
1. Tag & pushing the commit

e.g.

```
yarn version --new-version 1.2.17
yarn version --patch // 1.2.17 -> 1.2.18
```

## Sponsor The Library

If you'd like to sponsor a specific feature, fix, or the library in general, please reach out on an issue and we'll have a conversation!

## License

MIT
