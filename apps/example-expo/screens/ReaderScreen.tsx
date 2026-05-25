import React, { useEffect, useRef, useState } from 'react';
import {
  ActivityIndicator,
  Pressable,
  StyleSheet,
  Text,
  View,
} from 'react-native';
import * as FileSystem from 'expo-file-system/legacy';
import {
  ReadiumView,
  type DecorationGroup,
  type File,
  type Locator,
  type PublicationReadyEvent,
  type ReadiumViewRef,
  type SelectionAction,
  type SelectionActionEvent,
} from 'react-native-readium';
import type { Format, Sample } from '../types';

const selectionActions: SelectionAction[] = [
  { id: 'highlight', label: 'Highlight' },
];

type ReaderScreenProps = {
  sample: Sample;
  onBack: () => void;
  onAudiobookMinimize: (file: File) => void;
};

export function ReaderScreen({
  sample,
  onBack,
  onAudiobookMinimize,
}: ReaderScreenProps) {
  const readerRef = useRef<ReadiumViewRef>(null);
  const [file, setFile] = useState<File | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [publicationTitle, setPublicationTitle] = useState<string>();
  const [tocCount, setTocCount] = useState(0);
  const [location, setLocation] = useState<Locator>();
  const [decorations, setDecorations] = useState<DecorationGroup[]>([
    { name: 'highlights', decorations: [] },
  ]);

  const format: Format = sample.format;

  useEffect(() => {
    let cancelled = false;

    const prepare = async () => {
      setLoading(true);
      setError(null);
      setFile(null);

      try {
        let url = sample.url;
        if (
          sample.format !== 'audiobook' &&
          !sample.url.startsWith('file://') &&
          sample.format !== 'comic'
        ) {
          const extension = sample.format === 'epub' ? 'epub' : sample.format;
          url = `${FileSystem.documentDirectory}sample.${extension}`;
          await FileSystem.downloadAsync(sample.url, url);
        }

        if (cancelled) return;

        const nextFile = { url };

        if (cancelled) return;
        setFile(nextFile);
      } catch (err) {
        if (!cancelled) {
          setError(String(err));
        }
      } finally {
        if (!cancelled) {
          setLoading(false);
        }
      }
    };

    prepare();

    return () => {
      cancelled = true;
    };
  }, [sample.url, sample.format]);

  const onPublicationReady = (event: PublicationReadyEvent) => {
    setPublicationTitle(event.metadata.title);
    setTocCount(event.tableOfContents.length);
  };

  const onSelectionAction = (event: SelectionActionEvent) => {
    if (event.actionId !== 'highlight' || format !== 'epub') return;
    setDecorations((groups) =>
      groups.map((group) =>
        group.name === 'highlights'
          ? {
              ...group,
              decorations: [
                ...group.decorations,
                {
                  id: `highlight-${Date.now()}`,
                  locator: event.locator,
                  style: { type: 'highlight', tint: '#f8df73' },
                },
              ],
            }
          : group
      )
    );
  };

  const handleMinimize = () => {
    if (file) {
      onAudiobookMinimize(file);
    }
  };

  if (loading) {
    return (
      <View style={styles.centered}>
        <ActivityIndicator size="large" />
        <Text style={styles.loadingText}>Opening {sample.title}…</Text>
        <Pressable style={styles.backButton} onPress={onBack}>
          <Text>Cancel</Text>
        </Pressable>
      </View>
    );
  }

  if (error || !file) {
    return (
      <View style={styles.centered}>
        <Text style={styles.errorText}>
          {error ?? 'Unable to open publication'}
        </Text>
        <Pressable style={styles.backButton} onPress={onBack}>
          <Text>Back to library</Text>
        </Pressable>
      </View>
    );
  }

  const readerKey = `${format}-${file.url}`;

  return (
    <View style={styles.container}>
      <View style={styles.header}>
        <Pressable onPress={onBack} style={styles.backButton}>
          <Text style={styles.backLabel}>← Library</Text>
        </Pressable>
        {format === 'audiobook' ? (
          <Pressable onPress={handleMinimize}>
            <Text>Minimize</Text>
          </Pressable>
        ) : null}
      </View>
      <View style={styles.reader}>
        <ReadiumView
          key={readerKey}
          ref={readerRef}
          file={file}
          preferences={{ theme: format === 'comic' ? 'dark' : 'light' }}
          decorations={format === 'epub' ? decorations : undefined}
          selectionActions={format === 'epub' ? selectionActions : undefined}
          onLocationChange={setLocation}
          onPublicationReady={onPublicationReady}
          onSelectionAction={onSelectionAction}
        />
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1 },
  header: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    marginBottom: 8,
  },
  backButton: { paddingVertical: 4, paddingRight: 8 },
  backLabel: { fontSize: 16, fontWeight: '600' },
  readerTools: {
    backgroundColor: '#fff',
    borderRadius: 8,
    marginBottom: 8,
    padding: 10,
  },
  readerStatus: { color: '#555', fontSize: 12, marginTop: 4 },
  reader: { flex: 1, overflow: 'hidden', borderRadius: 8 },
  controls: { flexDirection: 'row', gap: 20, marginTop: 10 },
  centered: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
    gap: 12,
  },
  loadingText: { color: '#555' },
  errorText: { color: '#a00', textAlign: 'center', paddingHorizontal: 16 },
});
