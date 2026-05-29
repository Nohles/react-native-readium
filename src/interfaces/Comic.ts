import type { Locator } from './Locator';
import type { Preferences } from './Preferences';

export type ComicCanvasMode = 'webtoon' | 'singlePage' | 'doublePage';
export type ComicReadingDirection = 'ltr' | 'rtl';
export type ComicFit = 'width' | 'height' | 'screen' | 'actualSize';

export interface ComicReaderSettings {
  canvasMode?: ComicCanvasMode;
  readingDirection?: ComicReadingDirection;
  fit?: ComicFit;
}

export interface ComicProgress {
  href: string;
  chapterProgression: number;
  totalProgression?: number;
  position?: number;
}

export interface ComicProgressStorage {
  key: string;
  progress: ComicProgress;
}

export function comicProgressFromLocator(
  locator: Locator
): ComicProgress | undefined {
  const progression = locator.locations?.progression;

  if (progression == null) {
    return undefined;
  }

  return {
    href: locator.href,
    chapterProgression: clampProgression(progression),
    totalProgression:
      locator.locations?.totalProgression == null
        ? undefined
        : clampProgression(locator.locations.totalProgression),
    position: locator.locations?.position,
  };
}

export function comicProgressStorageKey(
  publicationId: string,
  href: string
): string {
  return `readium:comic-progress:${publicationId}:${href}`;
}

export function comicLocatorFromProgress(
  progress: ComicProgress,
  type = 'image/jpeg'
): Locator {
  return {
    href: progress.href,
    type,
    locations: {
      progression: clampProgression(progress.chapterProgression),
      totalProgression: progress.totalProgression,
      position: progress.position,
    },
  };
}

export function createComicPreferences(
  settings: ComicReaderSettings = {},
  base: Preferences = {}
): Preferences {
  const canvasMode = settings.canvasMode ?? 'singlePage';
  const fit = settings.fit ?? (canvasMode === 'webtoon' ? 'width' : 'screen');

  return {
    ...base,
    scroll: canvasMode === 'webtoon',
    spread:
      canvasMode === 'doublePage'
        ? 'always'
        : canvasMode === 'singlePage'
        ? 'never'
        : 'never',
    fit: toReadiumFit(fit),
    readingProgression: settings.readingDirection ?? 'ltr',
    publisherStyles: true,
  };
}

function toReadiumFit(fit: ComicFit): Preferences['fit'] {
  switch (fit) {
    case 'width':
      return 'width';
    case 'height':
    case 'screen':
      return 'page';
    case 'actualSize':
      return 'auto';
  }
}

function clampProgression(value: number): number {
  if (Number.isNaN(value)) {
    return 0;
  }
  return Math.max(0, Math.min(1, value));
}
