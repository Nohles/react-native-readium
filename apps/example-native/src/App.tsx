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
import type {
  AudiobookBookmark,
  AudiobookBookmarkChangeEvent,
  AudiobookPlaybackState,
} from 'react-native-readium';

const books: BookOption[] = [
  {
    id: 'the-martian-audiobook',
    title: 'The Martian',
    author: 'Andy Weir',
    manifestUrl:
      'http://192.168.1.199:3000/readium/29cfb352-3587-40f6-bdab-553ff5def9cb/webpub/QW5keSBXZWlyL1RoZSBNYXJ0aWFuL1RoZSBNYXJ0aWFuLm1wMw/manifest.json',
    type: 'audiobook',
  },
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

  {
    id: 'sense-and-sensibility',
    title: 'Sense and Sensibility',
    author: 'Jane Austen',
    type: 'pdf',
    format: 'pdf',
    bundledAsset: 'sense-and-sensibility.pdf',
    epubPath: `${RNFS.DocumentDirectoryPath}/sense-and-sensibility.pdf`,
  },
  {
    id: 'readium-sample-comic',
    title: 'Readium Sample Comic',
    author: 'Readium',
    type: 'comic',
    format: 'comic',
    bundledAsset: 'readium-sample.cbz',
    epubPath: `${RNFS.DocumentDirectoryPath}/readium-sample.cbz`,
  },
  {
    id: 'readium-sample-audiobook',
    title: 'Readium Audio Sample',
    author: 'Readium',
    type: 'audiobook',
    format: 'audiobook',
    bundledAsset: 'readium-sample.m4b',
    epubPath: `${RNFS.DocumentDirectoryPath}/readium-sample.m4b`,
  },
  // Ebook publications (WebPub)
  {
    id: 'moby-dick-streamed',
    title: 'Moby Dick (Streamed WebPub)',
    author: 'Herman Melville',
    manifestUrl:
      'https://publication-server.readium.org/webpub/Z3M6Ly9yZWFkaXVtLXBsYXlncm91bmQtZmlsZXMvZGVtby9tb2J5LWRpY2suZXB1Yg/manifest.json',
  },
  {
    id: 'the-house-of-seven-gables',
    title: 'The House of Seven Gables (WebPub)',
    author: 'Nathaniel Hawthorne',
    manifestUrl:
      'https://publication-server.readium.org/webpub/Z3M6Ly9yZWFkaXVtLXBsYXlncm91bmQtZmlsZXMvZGVtby9uYXRoYW5pZWwtaGF3dGhvcm5lX3RoZS1ob3VzZS1vZi10aGUtc2V2ZW4tZ2FibGVzX2FkdmFuY2VkLmVwdWI/manifest.json',
  },
  {
    id: 'les-diaboliques',
    title: 'Les Diaboliques (WebPub)',
    author: "Barbey d'Aurevilly",
    manifestUrl:
      'https://publication-server.readium.org/webpub/Z3M6Ly9yZWFkaXVtLXBsYXlncm91bmQtZmlsZXMvZGVtby9sZXNfZGlhYm9saXF1ZXMuZXB1Yg/manifest.json',
  },
  {
    id: 'bella-the-dragon',
    title: 'Bella the Dragon (WebPub)',
    author: 'Readium',
    manifestUrl:
      'https://publication-server.readium.org/webpub/Z3M6Ly9yZWFkaXVtLXBsYXlncm91bmQtZmlsZXMvZGVtby9CZWxsYU9yaWdpbmFsMy5lcHVi/manifest.json',
  },
  {
    id: 'thorium-reader-user-guide-english',
    title: 'Thorium Reader User Guide (English)',
    author: 'EDRLab',
    manifestUrl:
      'https://publication-server.readium.org/webpub/Z3M6Ly9yZWFkaXVtLXBsYXlncm91bmQtZmlsZXMvdGhvcml1bS1kZXNrdG9wLXVzZXItZ3VpZGUvdGhvcml1bS1yZWFkZXItdXNlci1ndWlkZS1lbmdsaXNoLmVwdWI/manifest.json',
  },
  {
    id: 'thorium-reader-user-guide-french',
    title: 'Thorium Reader User Guide (French)',
    author: 'EDRLab',
    manifestUrl:
      'https://publication-server.readium.org/webpub/Z3M6Ly9yZWFkaXVtLXBsYXlncm91bmQtZmlsZXMvdGhvcml1bS1kZXNrdG9wLXVzZXItZ3VpZGUvZ3VpZGUtdXRpbGlzYXRldXItdGhvcml1bS1yZWFkZXItZnJhbmNhaXMuZXB1Yg/manifest.json',
  },
  {
    id: 'thorium-reader-user-guide-spanish',
    title: 'Thorium Reader User Guide (Spanish)',
    author: 'EDRLab',
    manifestUrl:
      'https://publication-server.readium.org/webpub/Z3M6Ly9yZWFkaXVtLXBsYXlncm91bmQtZmlsZXMvdGhvcml1bS1kZXNrdG9wLXVzZXItZ3VpZGUvZ3VpYS11c3VhcmlvLXRob3JpdW0tcmVhZGVyLWVzcGFub2wuZXB1Yg/manifest.json',
  },
  {
    id: 'fundamental-accessibility-basic-v2',
    title: 'Fundamental Accessibility Tests: Basic Functionality v2.0.0',
    author: 'DAISY',
    manifestUrl:
      'https://publication-server.readium.org/webpub/aHR0cHM6Ly9naXRodWIuY29tL2RhaXN5L2VwdWItYWNjZXNzaWJpbGl0eS10ZXN0cy9yZWxlYXNlcy9kb3dubG9hZC9mdW5kYW1lbnRhbC0yLjAvRnVuZGFtZW50YWwtQWNjZXNzaWJpbGl0eS1UZXN0cy1CYXNpYy1GdW5jdGlvbmFsaXR5LXYyLjAuMC5lcHVi/manifest.json',
  },
  {
    id: 'fundamental-accessibility-non-visual-v2',
    title: 'Fundamental Accessibility Tests: Non-Visual Reading v2.0.1',
    author: 'DAISY',
    manifestUrl:
      'https://publication-server.readium.org/webpub/aHR0cHM6Ly9naXRodWIuY29tL2RhaXN5L2VwdWItYWNjZXNzaWJpbGl0eS10ZXN0cy9yZWxlYXNlcy9kb3dubG9hZC9ub24tdmlzdWFsLXJlYWRpbmctMi4wLjEvRnVuZGFtZW50YWwtQWNjZXNzaWJpbGl0eS1UZXN0cy1Ob24tVmlzdWFsLVJlYWRpbmctdjIuMC4xLmVwdWI/manifest.json',
  },
  {
    id: 'fundamental-accessibility-visual-adjustments-v2',
    title: 'Fundamental Accessibility Tests: Visual Adjustments v2.0.0',
    author: 'DAISY',
    manifestUrl:
      'https://publication-server.readium.org/webpub/aHR0cHM6Ly9naXRodWIuY29tL2RhaXN5L2VwdWItYWNjZXNzaWJpbGl0eS10ZXN0cy9yZWxlYXNlcy9kb3dubG9hZC9mdW5kYW1lbnRhbC0yLjAvRnVuZGFtZW50YWwtQWNjZXNzaWJpbGl0eS1UZXN0cy1WaXN1YWwtQWRqdXN0bWVudHMtdjIuMC4wLmVwdWI/manifest.json',
  },
  {
    id: 'advanced-accessibility-media-overlays-v1',
    title: 'Advanced Accessibility Tests: Media Overlays v1.0.0',
    author: 'DAISY',
    manifestUrl:
      'https://publication-server.readium.org/webpub/aHR0cHM6Ly9naXRodWIuY29tL2RhaXN5L2VwdWItYWNjZXNzaWJpbGl0eS10ZXN0cy9yZWxlYXNlcy9kb3dubG9hZC9tZWRpYS1vdmVybGF5cy0xLjAvQWR2YW5jZWQtQWNjZXNzaWJpbGl0eS1UZXN0cy1NZWRpYS1PdmVybGF5cy12MS4wLjAuZXB1Yg/manifest.json',
  },
  {
    id: 'accessibility-extended-descriptions-v1',
    title: 'Accessibility Tests: Extended Descriptions v1.1.1',
    author: 'DAISY',
    manifestUrl:
      'https://publication-server.readium.org/webpub/aHR0cHM6Ly9naXRodWIuY29tL2RhaXN5L2VwdWItYWNjZXNzaWJpbGl0eS10ZXN0cy9yZWxlYXNlcy9kb3dubG9hZC9tYXRoLWV4dGRlc2MtMS4xLjEvQWNjZXNzaWJpbGl0eS1UZXN0cy1FeHRlbmRlZC1EZXNjcmlwdGlvbnMtdjEuMS4xLmVwdWI/manifest.json',
  },

  // Additional experimental web publications
  {
    id: 'readium-css',
    title: 'Readium CSS Docs (WebPub)',
    author: 'Readium',
    manifestUrl: 'https://readium.org/css/docs/manifest.json',
  },
  {
    id: 'moby-dick-webpub',
    title: 'Moby Dick (Readium Example WebPub)',
    author: 'Herman Melville',
    manifestUrl:
      'https://readium.org/webpub-manifest/examples/MobyDick/manifest.json',
  },
  {
    id: 'molly-hopper',
    title: 'Molly Hopper (CSS Docs Sample)',
    author: 'Readium',
    manifestUrl: 'https://readium.org/css/docs/manifest.json',
  },

  // RTL + CJK
  {
    id: 'haruko',
    title: 'Haruko (RTL + CJK Sample)',
    author: 'Readium',
    manifestUrl:
      'https://publication-server.readium.org/webpub/aHR0cHM6Ly9naXRodWIuY29tL0lEUEYvZXB1YjMtc2FtcGxlcy9yZWxlYXNlcy9kb3dubG9hZC8yMDIzMDcwNC9oYXJ1a28taHRtbC1qcGVnLmVwdWI/manifest.json',
  },
  {
    id: 'israel-sailing',
    title: 'Israel Sailing (RTL + CJK Sample)',
    author: 'Readium',
    manifestUrl:
      'https://publication-server.readium.org/webpub/aHR0cHM6Ly9naXRodWIuY29tL0lEUEYvZXB1YjMtc2FtcGxlcy9yZWxlYXNlcy9kb3dubG9hZC8yMDIzMDcwNC9pc3JhZWxzYWlsaW5nLmVwdWI/manifest.json',
  },
  {
    id: 'jlreq',
    title: 'JLReq (RTL + CJK Sample)',
    author: 'Readium',
    manifestUrl:
      'https://publication-server.readium.org/webpub/aHR0cHM6Ly9naXRodWIuY29tL0lEUEYvZXB1YjMtc2FtcGxlcy9yZWxlYXNlcy9kb3dubG9hZC8yMDIzMDcwNC9qbHJlcS1pbi1qYXBhbmVzZS5lcHVi/manifest.json',
  },
  {
    id: 'kusamakura',
    title: 'Kusamakura (RTL + CJK Sample)',
    author: 'Natsume Sōseki',
    manifestUrl:
      'https://publication-server.readium.org/webpub/aHR0cHM6Ly9naXRodWIuY29tL0lEUEYvZXB1YjMtc2FtcGxlcy9yZWxlYXNlcy9kb3dubG9hZC8yMDIzMDcwNC9rdXNhbWFrdXJhLWphcGFuZXNlLXZlcnRpY2FsLXdyaXRpbmcuZXB1Yg/manifest.json',
  },
  {
    id: 'regime-anticancer-arabic',
    title: 'Regime Anticancer Arabic (RTL + CJK Sample)',
    author: 'David Servan-Schreiber',
    manifestUrl:
      'https://publication-server.readium.org/webpub/aHR0cHM6Ly9naXRodWIuY29tL0lEUEYvZXB1YjMtc2FtcGxlcy9yZWxlYXNlcy9kb3dubG9hZC8yMDIzMDcwNC9yZWdpbWUtYW50aWNhbmNlci1hcmFiaWMuZXB1Yg/manifest.json',
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
  const [audiobookBookmarks, setAudiobookBookmarks] = useState<
    Record<string, AudiobookBookmark[]>
  >({});

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

  const handleAudiobookBookmarkChange = useCallback(
    (event: AudiobookBookmarkChangeEvent) => {
      const key = selectedBook?.id;
      if (!key) return;
      setAudiobookBookmarks((stored) => {
        const current = stored[key] ?? [];
        const next =
          event.type === 'remove'
            ? current.filter((bookmark) => bookmark.id !== event.bookmark.id)
            : [
                ...current.filter(
                  (bookmark) => bookmark.id !== event.bookmark.id
                ),
                event.bookmark,
              ];
        return { ...stored, [key]: next };
      });
    },
    [selectedBook?.id]
  );

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
            audiobookBookmarks={
              selectedBook ? audiobookBookmarks[selectedBook.id] ?? [] : []
            }
            onAudiobookBookmarkChange={handleAudiobookBookmarkChange}
            reopenActiveAudiobook={selectedBook?.id === activeAudiobook?.id}
          />
        )}
      </GestureHandlerRootView>
    </SafeAreaProvider>
  );
}
