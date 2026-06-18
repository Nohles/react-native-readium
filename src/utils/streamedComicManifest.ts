const COMIC_BOOK_TYPES = new Set([
  'application/vnd.comicbook+zip',
  'application/x-cbz',
]);

function base64UrlDecode(value: string): string {
  const normalized = value.replace(/-/g, '+').replace(/_/g, '/');
  const padded = normalized.padEnd(
    normalized.length + ((4 - (normalized.length % 4)) % 4),
    '='
  );

  return decodeURIComponent(
    Array.prototype.map
      .call(atob(padded), (char: string) => {
        return `%${`00${char.charCodeAt(0).toString(16)}`.slice(-2)}`;
      })
      .join('')
  );
}

function base64UrlEncode(value: string): string {
  const binary = encodeURIComponent(value).replace(
    /%([0-9A-F]{2})/g,
    (_match, hex) => String.fromCharCode(Number.parseInt(hex, 16))
  );

  return btoa(binary)
    .replace(/\+/g, '-')
    .replace(/\//g, '_')
    .replace(/=+$/, '');
}

export function isComicBookLink(link: {
  type?: string;
}): boolean {
  return typeof link?.type === 'string' && COMIC_BOOK_TYPES.has(link.type);
}

export function isComicSeriesManifest(manifest: {
  readingOrder?: Array<{ href?: string; type?: string }>;
}): boolean {
  const readingOrder = manifest.readingOrder ?? [];
  return readingOrder.some((link) => isComicBookLink(link));
}

export function firstComicChapterHref(manifest: {
  readingOrder?: Array<{ href?: string; type?: string }>;
}): string | null {
  const chapter = manifest.readingOrder?.find((link) => isComicBookLink(link));
  return typeof chapter?.href === 'string' ? chapter.href : null;
}

/** go-toolkit / publication-server style `/webpub/<hash>/manifest.json` URLs. */
export function chapterManifestUrlFromSeries(
  seriesManifestUrl: string,
  chapterHref: string
): string | null {
  const match = seriesManifestUrl.match(
    /^(https?:\/\/[^/]+)(.*\/webpub\/)([^/]+)\/manifest\.json$/
  );
  if (!match) return null;

  const seriesPath = base64UrlDecode(match[3]!);
  const chapterPath = `${seriesPath.replace(/\/$/, '')}/${decodeURIComponent(
    chapterHref
  )}`;

  return `${match[1]}${match[2]}${base64UrlEncode(chapterPath)}/manifest.json`;
}

/**
 * Streamed Divina series manifests list CBZ chapters in `readingOrder`.
 * Native Readium opens a single manifest; resolve to the first chapter manifest
 * (same as `web/utils/manifestFetcher.ts`).
 */
export function resolveStreamedComicChapterManifestUrl(
  seriesManifestUrl: string,
  manifest: {
    readingOrder?: Array<{ href?: string; type?: string }>;
  }
): string | null {
  if (!isComicSeriesManifest(manifest)) {
    return null;
  }

  const firstChapterHref = firstComicChapterHref(manifest);
  if (!firstChapterHref) {
    return null;
  }

  return chapterManifestUrlFromSeries(seriesManifestUrl, firstChapterHref);
}
