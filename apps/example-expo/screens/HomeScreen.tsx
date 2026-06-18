import React from 'react';
import {
  ActivityIndicator,
  Pressable,
  StyleSheet,
  Text,
  View,
} from 'react-native';
import type { AudiobookPlayerState, File } from 'react-native-readium';
import type { Sample } from '../types';

type HomeScreenProps = {
  samples: Sample[];
  audio: AudiobookPlayerState;
  audioFile: File | null;
  onOpenSample: (sample: Sample) => void;
  onOpenComic: () => void;
  onOpenAudiobookPlayer: () => void;
  onCloseAudio: () => void;
  onPlayPause: () => void;
  onGoBackward: () => void;
  onGoForward: () => void;
};

export function HomeScreen({
  samples,
  audio,
  audioFile,
  onOpenSample,
  onOpenComic,
  onOpenAudiobookPlayer,
  onCloseAudio,
  onPlayPause,
  onGoBackward,
  onGoForward,
}: HomeScreenProps) {
  const audioLoading = audio.status === 'loading';

  return (
    <View style={styles.container}>
      <Text style={styles.title}>Readium Expo SDK 56</Text>
      <Text style={styles.subtitle}>Choose a publication to open</Text>
      <View style={styles.library}>
        {samples.map((sample) => (
          <Pressable
            key={sample.title}
            style={styles.button}
            onPress={() => onOpenSample(sample)}
          >
            <Text>{sample.title}</Text>
          </Pressable>
        ))}
        <Pressable style={styles.button} onPress={onOpenComic}>
          <Text>Open local CBZ (iOS)</Text>
        </Pressable>
        <Text style={styles.hint}>
          Audiobook, CBZ, and PDF readers are iOS-only in this release.{'\n'}
          Streamed WebPub samples open manifest.json URLs directly (no local
          download). Proxied Martian needs Reader web on localhost:3000 (see
          apps/example-expo/.env.example).
        </Text>
      </View>

      {audioFile != null || audio.status !== 'idle' ? (
        <View style={styles.miniPlayer}>
          <Text style={styles.miniTitle}>
            {audio.publication?.title ?? 'Audiobook'}
          </Text>
          <Text>
            {Math.floor(audio.position)}s / {Math.floor(audio.duration)}s
          </Text>
          <View style={styles.controls}>
            <Pressable onPress={onGoBackward}>
              <Text>Previous</Text>
            </Pressable>
            <Pressable disabled={audioLoading} onPress={onPlayPause}>
              {audioLoading ? (
                <ActivityIndicator size="small" />
              ) : (
                <Text>{audio.status === 'playing' ? 'Pause' : 'Play'}</Text>
              )}
            </Pressable>
            <Pressable onPress={onGoForward}>
              <Text>Next</Text>
            </Pressable>
            {audioFile ? (
              <Pressable onPress={onOpenAudiobookPlayer}>
                <Text>Open Player</Text>
              </Pressable>
            ) : null}
            <Pressable onPress={onCloseAudio}>
              <Text>Close</Text>
            </Pressable>
          </View>
        </View>
      ) : null}
    </View>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1 },
  title: { fontSize: 24, fontWeight: '700', marginBottom: 4 },
  subtitle: { color: '#555', marginBottom: 16 },
  library: { gap: 8 },
  button: { backgroundColor: '#ffffff', borderRadius: 8, padding: 12 },
  hint: { color: '#555', fontSize: 12, marginTop: 4 },
  miniPlayer: {
    backgroundColor: '#fff',
    borderRadius: 10,
    padding: 12,
    marginTop: 'auto',
  },
  miniTitle: { fontWeight: '600' },
  controls: { flexDirection: 'row', gap: 20, marginTop: 10 },
});
