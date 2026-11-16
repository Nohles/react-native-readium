import type { Preferences as SpecPreferences } from '../specs/ReadiumView.nitro';
import type { ComicScaleType } from './Comic';

/**
 * Preferences with refined string union types for better IDE autocompletion.
 */
export interface Preferences
  extends Omit<
    SpecPreferences,
    | 'columnCount'
    | 'fit'
    | 'fontFamily'
    | 'imageFilter'
    | 'readingProgression'
    | 'spread'
    | 'textAlign'
    | 'theme'
  > {
  columnCount?: 'auto' | '1' | '2';
  fit?: 'auto' | 'page' | 'width';
  fontFamily?: string;
  imageFilter?: 'darken' | 'invert';
  readingProgression?: 'ltr' | 'rtl';
  spread?: 'auto' | 'never' | 'always';
  textAlign?: 'center' | 'justify' | 'start' | 'end' | 'left' | 'right';
  theme?: 'light' | 'dark' | 'sepia';
  comicReadingMode?:
    | 'singlePage'
    | 'doublePage'
    | 'continuousVertical'
    | 'continuousHorizontal'
    | 'webtoon';
  comicScaleType?: ComicScaleType;
  comicStretchSmallPages?: boolean;
  comicWidthLimitEnabled?: boolean;
  comicWidthLimitPercent?: number;
  comicScrollAmountPercent?: number;
  /** Double page: show the first page alone (default true). */
  comicSpreadCoverAlone?: boolean;
  /** Double page: flip the first-page choice when pairs come out wrong (default false). */
  comicSpreadShift?: boolean;
  /** @deprecated Ignored by the native comic readers. */
  comicImagePreloadAmount?: number;
}
