import type { Preferences as SpecPreferences } from '../specs/ReadiumView.nitro';

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
  fontFamily?:
    | 'serif'
    | 'sans-serif'
    | 'cursive'
    | 'fantasy'
    | 'monospace'
    | 'AccessibleDfA'
    | 'IA Writer Duospace'
    | 'OpenDyslexic';
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
  comicStretchSmallPages?: boolean;
  comicWidthLimitEnabled?: boolean;
  comicWidthLimitPercent?: number;
  comicImagePreloadAmount?: number;
  comicChapterStartIndex?: number;
  comicChapterEndIndex?: number;
  comicPreviousChapterTitle?: string;
  comicNextChapterTitle?: string;
  comicBoundaryTarget?: 'previous' | 'next' | 'none';
}
