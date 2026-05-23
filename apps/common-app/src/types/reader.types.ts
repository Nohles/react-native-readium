import type { Locator } from 'react-native-readium';

export interface BookOption {
  id: string;
  title: string;
  author: string;
  type?: 'epub' | 'audiobook';
  epubUrl?: string;
  epubPath?: string;
  manifestUrl?: string;
  /** Filename of an epub bundled in the app assets (e.g. 'book.epub') */
  bundledAsset?: string;
}

export interface ReaderProps {
  /** URL to the EPUB file (used for web or downloading on native) */
  epubUrl?: string;
  /** Local file path for the EPUB (used on native platforms after download) */
  epubPath?: string;
  /** Remote Readium Web Publication Manifest URL for audiobooks. */
  manifestUrl?: string;
  /** Filename of an epub bundled in the app assets (e.g. 'book.epub') */
  bundledAsset?: string;
  /** Initial location to open the book at */
  initialLocation?: Locator;
}

export interface CurrentSelection {
  locator: Locator;
  text: string;
}

export interface PendingHighlight {
  locator: Locator;
  selectedText: string;
}
