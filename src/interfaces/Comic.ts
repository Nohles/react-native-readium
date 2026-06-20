import type { Locator } from './Locator';
import type { Preferences } from './Preferences';

export type ComicCanvasMode = 'webtoon' | 'singlePage' | 'doublePage';
export type ComicReadingDirection = 'ltr' | 'rtl';
export type ComicFit = 'width' | 'height' | 'screen' | 'actualSize';
export type ComicReadingMode =
  | 'default'
  | 'singlePage'
  | 'doublePage'
  | 'continuousVertical'
  | 'continuousHorizontal'
  | 'webtoon';
export type ComicTapZones =
  | 'default'
  | 'edge'
  | 'kindle'
  | 'lShape'
  | 'rightAndLeft'
  | 'disabled';
export type ComicScaleType =
  | 'fitWidth'
  | 'fitHeight'
  | 'fitScreen'
  | 'originalSize';
export type ComicProgressBarType = 'hidden' | 'standard';
export type ComicProgressBarPosition = 'auto' | 'bottom' | 'left' | 'right';
export type ComicTapAction = 'prev' | 'next' | 'toggle';

export interface ComicReaderSettings {
  readingMode?: ComicReadingMode;
  pageGapPx?: number;
  direction?: ComicReadingDirection;
  tapZones?: ComicTapZones;
  scaleType?: ComicScaleType;
  progressBarType?: ComicProgressBarType;
  progressBarPosition?: ComicProgressBarPosition;
  /** @deprecated Use readingMode. Kept for existing callers. */
  canvasMode?: ComicCanvasMode;
  /** @deprecated Use direction. Kept for existing callers. */
  readingDirection?: ComicReadingDirection;
  /** @deprecated Use scaleType. Kept for existing callers. */
  fit?: ComicFit;
}

export const DEFAULT_COMIC_READER_SETTINGS = {
  readingMode: 'default',
  pageGapPx: 5,
  direction: 'ltr',
  tapZones: 'default',
  scaleType: 'originalSize',
  progressBarType: 'standard',
  progressBarPosition: 'auto',
} as const satisfies Required<
  Pick<
    ComicReaderSettings,
    | 'readingMode'
    | 'pageGapPx'
    | 'direction'
    | 'tapZones'
    | 'scaleType'
    | 'progressBarType'
    | 'progressBarPosition'
  >
>;

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
  const readingMode = effectiveComicReadingMode(settings);
  const scaleType = effectiveComicScaleType(settings);
  const scrollMode = isComicScrollMode(readingMode);

  return {
    ...base,
    scroll: scrollMode,
    spread: readingMode === 'doublePage' ? 'always' : 'never',
    fit: toReadiumFit(scaleType),
    comicReadingMode: readingMode,
    pageMargins: scrollMode
      ? Math.max(
          0,
          settings.pageGapPx ?? DEFAULT_COMIC_READER_SETTINGS.pageGapPx
        ) / 16
      : base.pageMargins,
    readingProgression:
      settings.direction ??
      settings.readingDirection ??
      DEFAULT_COMIC_READER_SETTINGS.direction,
    publisherStyles: true,
  };
}

export function effectiveComicReadingMode(
  settings: Pick<ComicReaderSettings, 'readingMode' | 'canvasMode'>
): Exclude<ComicReadingMode, 'default'> {
  const mode = settings.readingMode ?? settings.canvasMode ?? 'default';
  return mode === 'default' ? 'singlePage' : mode;
}

export function isComicScrollMode(
  mode: ComicReadingMode | Exclude<ComicReadingMode, 'default'>
): boolean {
  const effectiveMode = mode === 'default' ? 'singlePage' : mode;
  return (
    effectiveMode === 'continuousVertical' ||
    effectiveMode === 'continuousHorizontal' ||
    effectiveMode === 'webtoon'
  );
}

export function effectiveComicScaleType(
  settings: Pick<ComicReaderSettings, 'scaleType' | 'fit' | 'readingMode'>
): ComicScaleType {
  if (settings.scaleType) return settings.scaleType;
  switch (settings.fit) {
    case 'width':
      return 'fitWidth';
    case 'height':
      return 'fitHeight';
    case 'screen':
      return 'fitScreen';
    case 'actualSize':
      return 'originalSize';
    default:
      return settings.readingMode === 'webtoon' ? 'fitWidth' : 'fitScreen';
  }
}

export function resolveComicTapAction(params: {
  x: number;
  y: number;
  zones: ComicTapZones;
  direction: ComicReadingDirection;
}): ComicTapAction {
  const { x, y, direction } = params;
  const zones = params.zones === 'default' ? 'rightAndLeft' : params.zones;

  if (zones === 'disabled') return 'toggle';

  const sideToAction = (side: 'left' | 'right'): ComicTapAction => {
    if (direction === 'rtl') {
      return side === 'left' ? 'next' : 'prev';
    }
    return side === 'left' ? 'prev' : 'next';
  };

  switch (zones) {
    case 'edge':
      if (x < 0.2) return sideToAction('left');
      if (x > 0.8) return sideToAction('right');
      return 'toggle';
    case 'kindle':
    case 'rightAndLeft':
      if (x < 1 / 3) return sideToAction('left');
      if (x > 2 / 3) return sideToAction('right');
      return 'toggle';
    case 'lShape': {
      const bottom = y > 0.75;
      if (x < 0.2 || (bottom && x < 0.5)) return sideToAction('left');
      if (x > 0.8 || (bottom && x >= 0.5)) return sideToAction('right');
      return 'toggle';
    }
  }
}

export function shouldShowComicProgressBar(params: {
  width: number;
  progressBarType?: ComicProgressBarType;
  compactWidth?: number;
}): boolean {
  const compactWidth = params.compactWidth ?? 600;
  return params.progressBarType !== 'hidden' && params.width >= compactWidth;
}

export function comicProgressBarPosition(
  mode: ComicReadingMode | Exclude<ComicReadingMode, 'default'>,
  position: ComicProgressBarPosition = DEFAULT_COMIC_READER_SETTINGS.progressBarPosition
): Exclude<ComicProgressBarPosition, 'auto'> {
  if (position !== 'auto') return position;
  const effectiveMode = mode === 'default' ? 'singlePage' : mode;
  return effectiveMode === 'continuousVertical' || effectiveMode === 'webtoon'
    ? 'right'
    : 'bottom';
}

function toReadiumFit(scaleType: ComicScaleType): Preferences['fit'] {
  switch (scaleType) {
    case 'fitWidth':
      return 'width';
    case 'fitHeight':
    case 'fitScreen':
      return 'page';
    case 'originalSize':
      return 'auto';
  }
}

function clampProgression(value: number): number {
  if (Number.isNaN(value)) {
    return 0;
  }
  return Math.max(0, Math.min(1, value));
}
