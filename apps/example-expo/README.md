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

The example exercises EPUB, PDF, CBZ, audiobook, and streamed WebPub reading on
iOS and Android, including metadata, location updates, navigation, preferences,
and highlighting where supported by the publication format. The audiobook
screen can be minimized and reopened while the mini-player remains active.

## Proxied audiobook (Reader handoff repro)

**The Martian (Proxied manifest)** mirrors the Reader Expo app:

1. Start the Reader web app + Readium CLI proxy on port 3000.
2. Copy `apps/example-expo/.env.example` to `apps/example-expo/.env` and set:
   - `EXPO_PUBLIC_PROXIED_AUDIOBOOK_MANIFEST_URL` — full manifest URL from a live
     `/readium/open/audiobooks/...` session (the default UUID expires when the proxy restarts).
   - Optional: `EXPO_PUBLIC_READER_WEB_URL` + `EXPO_PUBLIC_AUDIOBOOK_FILE_ID` to open by file id instead.
3. Rebuild the dev client if you change native code: `yarn workspace example-expo ios`
   or `yarn workspace example-expo android`.
4. Open the proxied sample and filter Metro for `[AudiobookDebug]`.

Expect `onPublicationReady` after the native embed fix in `HybridReadiumView.swift`.
If manifest/audio probes pass but `onPublicationReady` never fires, check Xcode for
`Failed to open publication:`.
