import type { Locator } from 'react-native-readium';

export type PublicationFormat = 'epub' | 'audiobook' | 'comic' | 'pdf';

export interface BookOption {
  id: string;
  title: string;
  author: string;
  type?: PublicationFormat;
  epubUrl?: string;
  epubPath?: string;
  /** Filename of an epub bundled in the app assets (e.g. 'book.epub') */
  bundledAsset?: string;
  /** Readium Web Publication manifest URL (e.g. audiobook JSON). */
  manifestUrl?: string;
  format?: PublicationFormat;
}

export interface ReaderProps {
  /** URL to the EPUB file (used for web or downloading on native) */
  epubUrl?: string;
  /** Local file path for the EPUB (used on native platforms after download) */
  epubPath?: string;
  /** Filename of an epub bundled in the app assets (e.g. 'book.epub') */
  bundledAsset?: string;
  /** Readium Web Publication manifest URL (e.g. audiobook JSON). */
  manifestUrl?: string;
  format?: PublicationFormat;
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
