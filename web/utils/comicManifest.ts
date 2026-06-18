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

function getManifestPathParts(manifestUrl: string): {
  origin: string;
  prefix: string;
  hash: string;
} | null {
  try {
    const url = new URL(manifestUrl);
    const match = url.pathname.match(/^(.*\/webpub\/)([^/]+)\/manifest\.json$/);
    if (!match) return null;

    return {
      origin: url.origin,
      prefix: match[1]!,
      hash: match[2]!,
    };
  } catch {
    return null;
  }
}

export function isComicBookLink(link: any): boolean {
  return typeof link?.type === 'string' && COMIC_BOOK_TYPES.has(link.type);
}

export function isComicSeriesManifest(manifest: any): boolean {
  const readingOrder = Array.isArray(manifest?.readingOrder)
    ? manifest.readingOrder
    : [];

  return readingOrder.some((link: any) => isComicBookLink(link));
}

export function firstComicChapterHref(manifest: any): string | null {
  const readingOrder = Array.isArray(manifest?.readingOrder)
    ? manifest.readingOrder
    : [];
  const chapter = readingOrder.find((link: any) => isComicBookLink(link));

  return typeof chapter?.href === 'string' ? chapter.href : null;
}

export function chapterManifestUrlFromSeries(
  seriesManifestUrl: string,
  chapterHref: string
): string | null {
  const parts = getManifestPathParts(seriesManifestUrl);
  if (!parts) return null;

  const seriesPath = base64UrlDecode(parts.hash);
  const chapterPath = `${seriesPath.replace(/\/$/, '')}/${decodeURIComponent(
    chapterHref
  )}`;
  const chapterHash = base64UrlEncode(chapterPath);

  return `${parts.origin}${parts.prefix}${chapterHash}/manifest.json`;
}
