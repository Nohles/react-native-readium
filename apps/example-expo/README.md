# Expo SDK 56 Example

This development-build app consumes the Nitro-based `react-native-readium`
package directly from the workspace. It is intentionally not compatible with
Expo Go because Readium requires native code.

```sh
yarn install
yarn workspace example-expo expo prebuild --clean
yarn workspace example-expo ios
# or:
yarn workspace example-expo android
```

The example exercises EPUB rendering, metadata, location updates, navigation,
preferences, and highlighting on iOS and Android. On iOS it also exposes the
persistent audiobook mini-player session, PDF rendering, and local CBZ
selection. The audiobook screen can be minimized and reopened while the
mini-player remains active. Audiobook, CBZ, and PDF entries display an
unsupported-platform message on Android because those readers are intentionally
deferred there.
