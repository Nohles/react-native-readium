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

import { ReaderButton } from './ReaderButton';
import { HighlightColorPicker, HighlightEditDialog } from './highlights';

import { useEpubFile } from '../hooks/useEpubFile';
import { useReaderState } from '../hooks/useReaderState';
import { useHighlights } from '../hooks/useHighlights';

import { styles } from '../styles/reader';
import type { ReaderProps as BaseReaderProps } from '../types/reader.types';
export type { BookOption, PublicationFormat } from '../types/reader.types';

const selectionActions: SelectionAction[] = [
  { id: 'highlight', label: '📑 Highlight' },
];

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
}) => {
  const ref = useRef<ReadiumViewRef>(null);

  const { file, isLoading, error } = useEpubFile({
    epubUrl,
    manifestUrl,
    epubPath,
    bundledAsset,
    initialLocation,
  });

  const {
    toc,
    location,
    preferences,
    setPreferences,
    handleLocationChange,
    handlePublicationReady: baseHandlePublicationReady,
  } = useReaderState({ initialPreferences, onPreferencesChange });

  const navigateToLocator = useCallback((locator: Locator) => {
    ref.current?.goTo(locator);
  }, []);

  const navigateToTocItem = useCallback(
    (item: Link) => {
      ref.current?.goTo({
        href: item.href,
        type:
          item.type ||
          (format === 'audiobook' ? 'audio/mpeg' : 'application/xhtml+xml'),
        title: item.title || '',
        locations: {
          progression: 0,
        },
      });
    },
    [format]
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
      baseHandlePublicationReady(event);
      onPublicationTitleChange?.(event.metadata.title || 'Audiobook');
    },
    [baseHandlePublicationReady, onPublicationTitleChange]
  );

  // Expose reader state to parent via callback
  React.useEffect(() => {
    if (onReaderReady) {
      onReaderReady({
        toc,
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
    toc,
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
