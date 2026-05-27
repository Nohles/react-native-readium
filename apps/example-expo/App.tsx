import React, { useEffect, useState } from 'react';
import { Alert, Platform, StyleSheet } from 'react-native';
import * as DocumentPicker from 'expo-document-picker';
import {
  ReadiumAudio,
  type AudiobookBookmark,
  type AudiobookBookmarkChangeEvent,
  type AudiobookSessionState,
  type File,
} from 'react-native-readium';
import {
  SafeAreaProvider,
  SafeAreaView,
} from 'react-native-safe-area-context';
import { HomeScreen } from './screens/HomeScreen';
import { ReaderScreen } from './screens/ReaderScreen';
import { samples, type Sample } from './types';

const initialAudioState: AudiobookSessionState = {
  status: 'idle',
  position: 0,
  duration: 0,
  rate: 1,
  volume: 1,
};

type Route = { screen: 'home' } | { screen: 'reader'; sample: Sample };

export default function App() {
  const [route, setRoute] = useState<Route>({ screen: 'home' });
  const [audio, setAudio] = useState(initialAudioState);
  const [audioFile, setAudioFile] = useState<File | null>(null);
  const [audiobookBookmarks, setAudiobookBookmarks] = useState<
    Record<string, AudiobookBookmark[]>
  >({});

  useEffect(() => ReadiumAudio.subscribe(setAudio), []);

  const guardPlatform = (sample: Sample): boolean => {
    if (Platform.OS === 'android' && sample.format !== 'epub') {
      Alert.alert(
        'iOS only in this release',
        'Android audiobook, comic, and PDF support is planned for a later PR.'
      );
      return false;
    }
    return true;
  };

  const openSample = (sample: Sample) => {
    if (!guardPlatform(sample)) return;
    setRoute({ screen: 'reader', sample });
  };

  const openComic = async () => {
    if (Platform.OS !== 'ios') {
      Alert.alert(
        'iOS only in this release',
        'Android comic support is deferred.'
      );
      return;
    }
    const result = await DocumentPicker.getDocumentAsync({
      type: ['application/vnd.comicbook+zip', 'application/zip'],
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

  const openAudiobookPlayer = () => {
    if (!audioFile) return;
    openSample({
      title: audio.publication?.title ?? 'Audiobook',
      format: 'audiobook',
      url: audioFile.url,
    });
  };

  const closeAudio = () => {
    ReadiumAudio.close();
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
        edges={isAudiobookReader ? ['top', 'left', 'right'] : ['top', 'left', 'right', 'bottom']}
      >
        {route.screen === 'home' ? (
          <HomeScreen
            samples={samples}
            audio={audio}
            audioFile={audioFile}
            onOpenSample={openSample}
            onOpenComic={openComic}
            onOpenAudiobookPlayer={openAudiobookPlayer}
            onCloseAudio={closeAudio}
          />
        ) : (
          <ReaderScreen
            key={`${route.sample.format}-${route.sample.url}`}
            sample={route.sample}
            onBack={goHome}
            onAudiobookMinimize={handleAudiobookMinimize}
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
