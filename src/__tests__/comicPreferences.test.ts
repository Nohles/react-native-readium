import {
  comicProgressBarPosition,
  createComicPreferences,
  effectiveComicReadingMode,
  resolveComicTapAction,
  shouldShowComicProgressBar,
} from '../interfaces/Comic';

describe('comic preferences', () => {
  it('resolves default mode and maps Thorium settings to Readium preferences', () => {
    expect(effectiveComicReadingMode({ readingMode: 'default' })).toBe(
      'singlePage'
    );
    expect(
      createComicPreferences({
        readingMode: 'webtoon',
        direction: 'rtl',
        scaleType: 'fitWidth',
      })
    ).toMatchObject({
      scroll: true,
      spread: 'never',
      fit: 'width',
      readingProgression: 'rtl',
    });
    expect(
      createComicPreferences({
        readingMode: 'doublePage',
        scaleType: 'originalSize',
      })
    ).toMatchObject({
      scroll: false,
      spread: 'always',
      fit: 'auto',
    });
  });

  it('keeps backward-compatible canvas mode and fit settings', () => {
    expect(
      createComicPreferences({ canvasMode: 'singlePage', fit: 'screen' })
    ).toMatchObject({
      scroll: false,
      spread: 'never',
      fit: 'page',
    });
  });

  it('matches Thorium tap zone navigation including RTL reversal', () => {
    expect(
      resolveComicTapAction({
        x: 0.1,
        y: 0.5,
        zones: 'edge',
        direction: 'ltr',
      })
    ).toBe('prev');
    expect(
      resolveComicTapAction({
        x: 0.9,
        y: 0.5,
        zones: 'edge',
        direction: 'rtl',
      })
    ).toBe('prev');
    expect(
      resolveComicTapAction({
        x: 0.4,
        y: 0.8,
        zones: 'lShape',
        direction: 'ltr',
      })
    ).toBe('prev');
    expect(
      resolveComicTapAction({
        x: 0.5,
        y: 0.5,
        zones: 'disabled',
        direction: 'ltr',
      })
    ).toBe('toggle');
  });

  it('keeps progress available at compact widths and resolves position by mode', () => {
    expect(shouldShowComicProgressBar({ width: 320 })).toBe(true);
    expect(shouldShowComicProgressBar({ width: 600 })).toBe(true);
    expect(
      shouldShowComicProgressBar({ width: 900, progressBarType: 'hidden' })
    ).toBe(false);
    expect(comicProgressBarPosition('webtoon')).toBe('right');
    expect(comicProgressBarPosition('continuousVertical')).toBe('right');
    expect(comicProgressBarPosition('continuousHorizontal')).toBe('bottom');
    expect(comicProgressBarPosition('singlePage')).toBe('bottom');
  });

  it('maps the full native comic layout settings', () => {
    expect(
      createComicPreferences({
        theme: 'sepia',
        pageGapPx: 12,
        stretchSmallPages: true,
        widthLimitEnabled: true,
        widthLimitPercent: 75,
        scrollAmountPercent: 90,
        imagePreloadAmount: 3,
      })
    ).toMatchObject({
      theme: 'sepia',
      backgroundColor: '#f4ecd8',
      pageMargins: 0.75,
      comicStretchSmallPages: true,
      comicWidthLimitEnabled: true,
      comicWidthLimitPercent: 75,
      comicScrollAmountPercent: 90,
      comicImagePreloadAmount: 3,
    });
  });
});
