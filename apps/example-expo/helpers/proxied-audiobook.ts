import type { File, Locator } from 'react-native-readium';

export const DEFAULT_PROXIED_MANIFEST_URL =
  process.env.EXPO_PUBLIC_PROXIED_AUDIOBOOK_MANIFEST_URL ??
  'http://192.168.1.199:3000/readium/9b4fb794-7711-4aff-aab7-1a8c15378c68/webpub/QW5keSBXZWlyL1RoZSBNYXJ0aWFuL1RoZSBNYXJ0aWFuLm1wMw/manifest.json';

export const DEFAULT_PROXIED_INITIAL_LOCATION: Locator | undefined = undefined;

export async function prepareProxiedAudiobook({
  manifestUrl,
  initialLocation,
}: {
  manifestUrl: string;
  initialLocation?: Locator;
}): Promise<{ ok: true; file: File } | { ok: false; message: string }> {
  try {
    const response = await fetch(manifestUrl);
    if (!response.ok) {
      return {
        ok: false,
        message: `Audiobook manifest returned HTTP ${response.status}.`,
      };
    }
    await response.json();
    return { ok: true, file: { url: manifestUrl, initialLocation } };
  } catch (error) {
    return {
      ok: false,
      message: `Unable to reach audiobook manifest: ${String(error)}`,
    };
  }
}
