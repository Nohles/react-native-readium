# Native example

This app uses React Native 0.88 and links the library source from the pnpm workspace.
Changes to `src/` are picked up by Metro; changes to Swift, Kotlin, C++, or Nitro
bindings require rebuilding the app.

Run these commands from the repository root:

```sh
pnpm install
pnpm run pods
pnpm example ios --no-packager
# or:
pnpm example android --no-packager
```

Start Metro separately when needed:

```sh
pnpm example start
```

Metro uses port **8191** so the example does not connect to another app on 8081.
For a standalone simulator build that needs no Metro server, use the Release
configuration.

Install Android SDK 37, NDK 27.1.12297006, and CMake 4.1.2 through the
Android SDK Manager. The examples use CMake 4.1.2 for Windows long-path support.

Android builds use the pinned Kotlin toolkit fork. Initialize and publish it
locally before building:

```sh
git submodule update --init --depth 1 external/kotlin-toolkit
SKIP_SIGNING=1 ./scripts/publish-kotlin-toolkit-maven-local.sh
```

The publishing script reports the JDK and Android SDK prerequisites if either
is missing. See `android/build.gradle` for the toolkit artifacts used by the
library.
