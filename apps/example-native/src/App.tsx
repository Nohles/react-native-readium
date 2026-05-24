import React, { useState, useCallback } from 'react';
import { GestureHandlerRootView } from 'react-native-gesture-handler';
import { SafeAreaProvider } from 'react-native-safe-area-context';

import {
  AudiobookMiniPlayer,
  HomeScreen,
  ReaderBottomSheet,
  RNFS,
} from 'common-app';
import type { BookOption, ReaderHandle } from 'common-app';
import type { AudiobookPlaybackState } from 'react-native-readium';

const books: BookOption[] = [
  {
    id: 'flatland-audiobook',
    title: 'Flatland',
    author: 'Edwin Abbott Abbott',
    manifestUrl:
      'https://readium.org/webpub-manifest/examples/Flatland/manifest.json',
    type: 'audiobook',
  },
  {
    id: 'moby-dick',
    title: 'Moby Dick',
    author: 'Herman Melville',
    epubUrl: 'https://www.gutenberg.org/ebooks/2701.epub3.images',
    epubPath: `${RNFS.DocumentDirectoryPath}/moby-dick.epub`,
  },
  {
    id: 'confessions',
    title: 'The Confessions of St. Augustine',
    author: 'Augustine of Hippo',
    epubUrl: 'https://www.gutenberg.org/ebooks/3296.epub3.images',
    epubPath: `${RNFS.DocumentDirectoryPath}/confessions.epub`,
  },
  {
    id: 'brothers-karamazov',
    title: 'The Brothers Karamazov',
    author: 'Fyodor Dostoevsky',
    bundledAsset: 'the-brothers-karamazov.epub',
    epubPath: `${RNFS.DocumentDirectoryPath}/the-brothers-karamazov.epub`,
  },
];

export default function App() {
  const [sheetOpen, setSheetOpen] = useState(false);
  const [selectedBook, setSelectedBook] = useState<BookOption | null>(null);
  const [activeAudiobook, setActiveAudiobook] = useState<BookOption | null>(
    null
  );
  const [readerHandle, setReaderHandle] = useState<ReaderHandle | null>(null);
  const [audiobookPlaybackState, setAudiobookPlaybackState] =
    useState<AudiobookPlaybackState | null>(null);
  const [audiobookTitle, setAudiobookTitle] = useState('Audiobook');

  const handleSelectBook = useCallback((book: BookOption) => {
    setSelectedBook(book);
    if (book.type === 'audiobook' || book.format === 'audiobook') {
      setActiveAudiobook(book);
      setAudiobookTitle(book.title);
    }
    setSheetOpen(true);
  }, []);

  const handleClearBook = useCallback(() => {
    setSelectedBook(null);
  }, []);

  const handleCloseSheet = useCallback(() => {
    setSheetOpen(false);
    setSelectedBook(null);
    setAudiobookPlaybackState((state) =>
      state ? { ...state, isPlaying: false } : state
    );
  }, []);

  const handleOpenActiveAudiobook = useCallback(() => {
    if (!activeAudiobook) {
      return;
    }

    setSelectedBook(activeAudiobook);
    setSheetOpen(true);
  }, [activeAudiobook]);

  const homeMiniPlayer =
    activeAudiobook && audiobookPlaybackState && !sheetOpen ? (
      <AudiobookMiniPlayer
        playbackState={audiobookPlaybackState}
        title={audiobookTitle}
        onPress={handleOpenActiveAudiobook}
        onPlay={() => {
          if (readerHandle) {
            readerHandle.play();
          } else {
            handleOpenActiveAudiobook();
          }
        }}
        onPause={() => readerHandle?.pause()}
        onNext={() => readerHandle?.goForward()}
      />
    ) : null;

  return (
    <SafeAreaProvider>
      <GestureHandlerRootView style={{ flex: 1 }}>
        <HomeScreen
          books={books}
          onSelectBook={handleSelectBook}
          miniPlayer={homeMiniPlayer}
        />
        {sheetOpen && (
          <ReaderBottomSheet
            key={selectedBook?.id ?? 'empty'}
            book={selectedBook}
            onClearBook={handleClearBook}
            onClose={handleCloseSheet}
            onReaderReady={setReaderHandle}
            onAudiobookPlaybackStateChange={setAudiobookPlaybackState}
            onPublicationTitleChange={setAudiobookTitle}
          />
        )}
      </GestureHandlerRootView>
    </SafeAreaProvider>
  );
}
