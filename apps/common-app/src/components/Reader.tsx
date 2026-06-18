import React, { useRef, useCallback } from 'react';
import { View, Text, Platform } from 'react-native';
import { ReadiumView } from 'react-native-readium';
import type {
  ReadiumViewRef,
  ReadiumProps,
  Link,
  Locator,
  Decoration,
  SelectionAction,
  PublicationReadyEvent,
  AudiobookPlaybackState,
  AudiobookBookmark,
  AudiobookBookmarkChangeEvent,
} from 'react-native-readium';
import { createComicPreferences } from 'react-native-readium';

import { ReaderButton } from './ReaderButton';
import { HighlightColorPicker, HighlightEditDialog } from './highlights';

import { useEpubFile } from '../hooks/useEpubFile';
import { useReaderState } from '../hooks/useReaderState';
import { useHighlights } from '../hooks/useHighlights';

import { styles } from '../styles/reader';
import type { ReaderProps as BaseReaderProps } from '../types/reader.types';
import { ControlBar } from './ControlBar';
export type { BookOption, PublicationFormat } from '../types/reader.types';

const selectionActions: SelectionAction[] = [
  { id: 'highlight', label: '📑 Highlight' },
];

const COMIC_BOOK_TYPES = new Set([
  'application/vnd.comicbook+zip',
  'application/x-cbz',
]);

function isComicBookLink(link: any): boolean {
  return typeof link?.type === 'string' && COMIC_BOOK_TYPES.has(link.type);
}

function base64UrlDecode(value: string): string {
  const atobFn = (globalThis as any).atob as (encoded: string) => string;
  const normalized = value.replace(/-/g, '+').replace(/_/g, '/');
  const padded = normalized.padEnd(
    normalized.length + ((4 - (normalized.length % 4)) % 4),
    '='
  );

  return decodeURIComponent(
    Array.prototype.map
      .call(atobFn(padded), (char: string) => {
        return `%${`00${char.charCodeAt(0).toString(16)}`.slice(-2)}`;
      })
      .join('')
  );
}

function base64UrlEncode(value: string): string {
  const btoaFn = (globalThis as any).btoa as (decoded: string) => string;
  const binary = encodeURIComponent(value).replace(
    /%([0-9A-F]{2})/g,
    (_match, hex) => String.fromCharCode(Number.parseInt(hex, 16))
  );

  return btoaFn(binary)
    .replace(/\+/g, '-')
    .replace(/\//g, '_')
    .replace(/=+$/, '');
}

function chapterManifestUrlFromSeries(
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

export interface ReaderHandle {
  toc: Link[] | null;
  location: Locator | undefined;
  preferences: ReadiumProps['preferences'];
  setPreferences: (prefs: ReadiumProps['preferences']) => void;
  navigateToLocator: (locator: Locator) => void;
  navigateToTocItem: (item: Link) => void;
  play: () => void;
  pause: () => void;
  goForward: () => void;
  goBackward: () => void;
  highlights: Decoration[];
  deleteHighlight: (id: string) => void;
  editHighlight: (highlight: Decoration) => void;
}

interface ReaderProps extends BaseReaderProps {
  onReaderReady?: (handle: ReaderHandle) => void;
  initialPreferences?: ReadiumProps['preferences'];
  onPreferencesChange?: (preferences: ReadiumProps['preferences']) => void;
  onAudiobookPlaybackStateChange?: (state: AudiobookPlaybackState) => void;
  onPublicationTitleChange?: (title: string) => void;
  audiobookBookmarks?: AudiobookBookmark[];
  onAudiobookBookmarkChange?: (event: AudiobookBookmarkChangeEvent) => void;
  reopenActiveAudiobook?: boolean;
  /** Settings / TOC / highlights chrome (default: all formats except audiobook). */
  showControlBar?: boolean;
  onClose?: () => void;
  onClearBook?: () => void;
}

export const Reader: React.FC<ReaderProps> = ({
  epubUrl,
  manifestUrl,
  format = 'epub',
  epubPath,
  bundledAsset,
  initialLocation,
  onReaderReady,
  initialPreferences,
  onPreferencesChange,
  onAudiobookPlaybackStateChange,
  onPublicationTitleChange,
  audiobookBookmarks,
  onAudiobookBookmarkChange,
  reopenActiveAudiobook,
  showControlBar,
  onClose,
  onClearBook,
}) => {
  const ref = useRef<ReadiumViewRef>(null);
  const [chapterManifestUrl, setChapterManifestUrl] = React.useState<string>();
  const [chapterInitialLocation, setChapterInitialLocation] =
    React.useState<Locator>();
  const [seriesManifestUrl, setSeriesManifestUrl] = React.useState<string>();
  const [seriesToc, setSeriesToc] = React.useState<Link[] | null>(null);

  React.useEffect(() => {
    setChapterManifestUrl(undefined);
    setChapterInitialLocation(undefined);
    setSeriesManifestUrl(undefined);
    setSeriesToc(null);
  }, [manifestUrl]);

  const { file, isLoading, error } = useEpubFile({
    epubUrl,
    manifestUrl: chapterManifestUrl ?? manifestUrl,
    epubPath,
    bundledAsset,
    initialLocation: chapterManifestUrl
      ? chapterInitialLocation
      : initialLocation,
  });

  const {
    toc,
    location,
    preferences,
    setPreferences,
    handleLocationChange,
    handlePublicationReady: baseHandlePublicationReady,
  } = useReaderState({
    initialPreferences:
      format === 'comic'
        ? createComicPreferences(
            { canvasMode: 'singlePage', fit: 'screen' },
            initialPreferences
          )
        : initialPreferences,
    onPreferencesChange,
  });
  const visibleToc = format === 'comic' ? seriesToc ?? toc : toc;

  const navigateToLocator = useCallback((locator: Locator) => {
    ref.current?.goTo(locator);
  }, []);

  const navigateToTocItem = useCallback(
    (item: Link) => {
      if (
        Platform.OS === 'web' &&
        format === 'comic' &&
        manifestUrl &&
        isComicBookLink(item)
      ) {
        const nextManifestUrl = chapterManifestUrlFromSeries(
          seriesManifestUrl ?? manifestUrl,
          item.href
        );

        if (nextManifestUrl) {
          setChapterInitialLocation(undefined);
          setChapterManifestUrl(nextManifestUrl);
          return;
        }
      }

      ref.current?.goTo({
        href: item.href,
        type:
          (item as Link & { type?: string }).type ||
          (format === 'audiobook' ? 'audio/mpeg' : 'application/xhtml+xml'),
        title: item.title || '',
        locations: {
          progression: 0,
        },
      });
    },
    [format, manifestUrl, seriesManifestUrl]
  );

  const play = useCallback(() => {
    ref.current?.play();
  }, []);

  const pause = useCallback(() => {
    ref.current?.pause();
  }, []);

  const goForward = useCallback(() => {
    ref.current?.goForward();
  }, []);

  const goBackward = useCallback(() => {
    ref.current?.goBackward();
  }, []);

  const {
    decorations,
    highlights,
    colorPickerVisible,
    pendingHighlight,
    editDialogVisible,
    selectedHighlight,
    handleSelectionChange,
    handleSelectionAction,
    handleCreateHighlight,
    handleCancelHighlight,
    handleDeleteHighlight,
    handleUpdateHighlight,
    handleDecorationActivated,
    handleEditHighlight,
    handleDeleteFromDialog,
    handleCancelEdit,
  } = useHighlights();

  const handlePublicationReady = React.useCallback(
    (event: PublicationReadyEvent) => {
      if (
        Platform.OS === 'web' &&
        format === 'comic' &&
        manifestUrl &&
        event.tableOfContents?.some((item) => isComicBookLink(item))
      ) {
        setSeriesManifestUrl((current) => current ?? manifestUrl);
        setSeriesToc(event.tableOfContents);
      }

      baseHandlePublicationReady(event);
      onPublicationTitleChange?.(event.metadata.title || 'Audiobook');
    },
    [baseHandlePublicationReady, format, manifestUrl, onPublicationTitleChange]
  );

  // Expose reader state to parent via callback
  React.useEffect(() => {
    if (onReaderReady) {
      onReaderReady({
        toc: visibleToc,
        location,
        preferences,
        setPreferences,
        navigateToLocator,
        navigateToTocItem,
        play,
        pause,
        goForward,
        goBackward,
        highlights,
        deleteHighlight: handleDeleteHighlight,
        editHighlight: handleEditHighlight,
      });
    }
  }, [
    visibleToc,
    location,
    preferences,
    highlights,
    onReaderReady,
    setPreferences,
    navigateToLocator,
    navigateToTocItem,
    play,
    pause,
    goForward,
    goBackward,
    handleDeleteHighlight,
    handleEditHighlight,
  ]);

  const loadingLabel =
    format === 'audiobook'
      ? 'audiobook'
      : format === 'comic'
      ? 'comic'
      : format === 'pdf'
      ? 'PDF'
      : 'EPUB';

  const showChrome =
    (showControlBar ?? format !== 'audiobook') &&
    onClose != null &&
    onClearBook != null;

  if (isLoading || !file) {
    return (
      <View style={styles.loadingContainer}>
        <Text>Loading {loadingLabel}...</Text>
      </View>
    );
  }

  if (error) {
    return (
      <View style={styles.loadingContainer}>
        <Text>
          Error loading {loadingLabel}: {error.message}
        </Text>
      </View>
    );
  }

  return (
    <View style={styles.container}>
      {showChrome ? (
        <ControlBar
          preferences={preferences}
          onPreferencesChange={setPreferences}
          toc={visibleToc}
          onNavigateToTocItem={navigateToTocItem}
          highlights={highlights}
          onDeleteHighlight={handleDeleteHighlight}
          onNavigateToHighlight={navigateToLocator}
          onEditHighlight={handleEditHighlight}
          onClearBook={onClearBook}
          onClose={onClose}
        />
      ) : null}

      <View style={styles.reader}>
        {Platform.OS === 'web' ? (
          <ReaderButton
            name="chevron-left"
            style={{ width: '10%' }}
            onPress={() => ref.current?.goBackward()}
          />
        ) : null}

        <View style={styles.readiumContainer}>
          <ReadiumView
            ref={ref}
            file={file}
            preferences={preferences}
            decorations={decorations}
            selectionActions={selectionActions}
            onLocationChange={handleLocationChange}
            onPublicationReady={handlePublicationReady}
            onDecorationActivated={handleDecorationActivated}
            onSelectionChange={handleSelectionChange}
            onSelectionAction={handleSelectionAction}
            onAudiobookPlaybackStateChange={onAudiobookPlaybackStateChange}
            audiobookBookmarks={audiobookBookmarks}
            onAudiobookBookmarkChange={onAudiobookBookmarkChange}
            reopenActiveAudiobook={reopenActiveAudiobook}
          />
        </View>

        {Platform.OS === 'web' ? (
          <ReaderButton
            name="chevron-right"
            style={{ width: '10%' }}
            onPress={() => ref.current?.goForward()}
          />
        ) : null}
      </View>

      <HighlightColorPicker
        visible={colorPickerVisible}
        locator={pendingHighlight?.locator || null}
        selectedText={pendingHighlight?.selectedText || ''}
        onConfirm={handleCreateHighlight}
        onCancel={handleCancelHighlight}
      />

      <HighlightEditDialog
        visible={editDialogVisible}
        highlight={selectedHighlight}
        onUpdate={handleUpdateHighlight}
        onDelete={handleDeleteFromDialog}
        onCancel={handleCancelEdit}
      />
    </View>
  );
};
