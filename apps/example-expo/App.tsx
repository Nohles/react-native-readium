import React, { useState } from 'react';
import { Alert, StyleSheet } from 'react-native';
import * as DocumentPicker from 'expo-document-picker';
import {
  useAudiobookPlayer,
  type AudiobookBookmark,
  type AudiobookBookmarkChangeEvent,
  type File,
} from 'react-native-readium';
import { SafeAreaProvider, SafeAreaView } from 'react-native-safe-area-context';
import { HomeScreen } from './screens/HomeScreen';
import { ReaderScreen } from './screens/ReaderScreen';
import { samples, type Sample } from './types';

type Route = { screen: 'home' } | { screen: 'reader'; sample: Sample };

export default function App() {
  const [route, setRoute] = useState<Route>({ screen: 'home' });
  const audiobook = useAudiobookPlayer();
  const [audioFile, setAudioFile] = useState<File | null>(null);
  const [audiobookBookmarks, setAudiobookBookmarks] = useState<
    Record<string, AudiobookBookmark[]>
  >({});

  const openSample = (sample: Sample) => {
    setRoute({ screen: 'reader', sample });
  };

  const openComic = async () => {
    const result = await DocumentPicker.getDocumentAsync({
      type: ['application/vnd.comicbook+zip', 'application/zip', '*/*'],
      copyToCacheDirectory: true,
    });
    if (!result.canceled) {
      openSample({
        title: result.assets[0].name ?? 'Local CBZ',
        format: 'comic',
        url: result.assets[0].uri,
      });
    }
  };

  const goHome = () => {
    setRoute({ screen: 'home' });
  };

  const handleAudiobookMinimize = (file: File) => {
    setAudioFile(file);
    goHome();
  };

  const handleAudiobookReady = (file: File) => {
    setAudioFile(file);
    audiobook.open(file).catch((error) => {
      Alert.alert('Unable to load audiobook', String(error));
    });
  };

  const openAudiobookPlayer = () => {
    if (!audioFile) return;
    openSample({
      title: audiobook.state.publication?.title ?? 'Audiobook',
      format: 'audiobook',
      url: audioFile.url,
    });
  };

  const closeAudio = () => {
    audiobook.close();
    setAudioFile(null);
    if (route.screen === 'reader' && route.sample.format === 'audiobook') {
      goHome();
    }
  };

  const updateAudiobookBookmarks = (
    url: string,
    event: AudiobookBookmarkChangeEvent
  ) => {
    setAudiobookBookmarks((stored) => {
      const current = stored[url] ?? [];
      const next =
        event.type === 'remove'
          ? current.filter((bookmark) => bookmark.id !== event.bookmark.id)
          : [
              ...current.filter(
                (bookmark) => bookmark.id !== event.bookmark.id
              ),
              event.bookmark,
            ];
      return { ...stored, [url]: next };
    });
  };

  const isAudiobookReader =
    route.screen === 'reader' && route.sample.format === 'audiobook';

  return (
    <SafeAreaProvider>
      <SafeAreaView
        style={[styles.screen, isAudiobookReader && styles.screenAudiobook]}
        edges={
          isAudiobookReader
            ? ['top', 'left', 'right']
            : ['top', 'left', 'right', 'bottom']
        }
      >
        {route.screen === 'home' ? (
          <HomeScreen
            samples={samples}
            audio={audiobook.state}
            audioFile={audioFile}
            onOpenSample={openSample}
            onOpenComic={openComic}
            onOpenAudiobookPlayer={openAudiobookPlayer}
            onCloseAudio={closeAudio}
            onPlayPause={audiobook.togglePlayback}
            onGoBackward={audiobook.goBackward}
            onGoForward={audiobook.goForward}
          />
        ) : (
          <ReaderScreen
            key={`${route.sample.format}-${route.sample.url}`}
            sample={route.sample}
            onBack={goHome}
            onAudiobookMinimize={handleAudiobookMinimize}
            onAudiobookReady={handleAudiobookReady}
            audiobookBookmarks={audiobookBookmarks[route.sample.url] ?? []}
            onAudiobookBookmarkChange={(event) =>
              updateAudiobookBookmarks(route.sample.url, event)
            }
          />
        )}
      </SafeAreaView>
    </SafeAreaProvider>
  );
}

const styles = StyleSheet.create({
  root: {
    flex: 1,
  },
  screen: {
    flex: 1,
    backgroundColor: '#f7f4ee',
    padding: 12,
  },
  screenAudiobook: {
    backgroundColor: '#131418',
    padding: 0,
  },
});
