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
  ReadiumAudio,
  ReadiumView,
  resolveStreamedComicChapterManifestUrl,
  type DecorationGroup,
  type File,
  type Locator,
  type PublicationReadyEvent,
  type ReadiumViewRef,
  type SelectionAction,
  type SelectionActionEvent,
  type AudiobookBookmark,
  type AudiobookBookmarkChangeEvent,
} from 'react-native-readium';
import { audiobookDebug } from '../lib/audiobook-debug';
import {
  publicationDebug,
  publicationNetworkHints,
} from '../lib/publication-debug';
import { prepareProxiedAudiobook } from '../lib/proxied-audiobook';
import { isWebPubManifestUrl } from '../lib/webpub-manifest';
import { probeWebPubManifest } from '../lib/webpub-probe';
import type { Format, Sample } from '../types';

const selectionActions: SelectionAction[] = [
  { id: 'highlight', label: 'Highlight' },
];

type ReaderScreenProps = {
  sample: Sample;
  onBack: () => void;
  onAudiobookMinimize: (file: File) => void;
  onAudiobookReady: (file: File) => void;
  audiobookBookmarks: AudiobookBookmark[];
  onAudiobookBookmarkChange: (event: AudiobookBookmarkChangeEvent) => void;
  /** When true, navigation chrome is omitted (parent bottom sheet provides close). */
  embeddedInSheet?: boolean;
};

export function ReaderScreen({
  sample,
  onBack,
  onAudiobookMinimize,
  onAudiobookReady,
  audiobookBookmarks,
  onAudiobookBookmarkChange,
  embeddedInSheet = false,
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
  const isProxiedAudiobook = sample.format === 'audiobook' && sample.proxied;
  const isStreamedWebPub = isWebPubManifestUrl(sample.url);
  const [manifestProbeStatus, setManifestProbeStatus] = useState<string>();
  const [nativeReady, setNativeReady] = useState(false);

  useEffect(() => {
    if (!file || nativeReady || !isStreamedWebPub) return;
    const timer = setTimeout(() => {
      publicationDebug(
        'watchdog: onPublicationReady not received within 12s — look for an iOS alert, Metro [ReadiumNative], or Xcode "Failed to open publication"'
      );
    }, 12_000);
    return () => clearTimeout(timer);
  }, [file, nativeReady, isStreamedWebPub]);

  useEffect(() => {
    if (!isProxiedAudiobook) return;
    audiobookDebug('ReaderScreen: mount proxied audiobook', {
      title: sample.title,
      url: sample.url,
    });
    ReadiumAudio.setVolume(1);
  }, [isProxiedAudiobook, sample.title, sample.url]);

  useEffect(() => {
    let cancelled = false;

    const prepare = async () => {
      setLoading(true);
      setError(null);
      setFile(null);
      setManifestProbeStatus(undefined);
      setNativeReady(false);

      publicationDebug('ReaderScreen: prepare', {
        title: sample.title,
        format: sample.format,
        url: sample.url,
        isStreamedWebPub,
        network: publicationNetworkHints(sample.url),
      });

      try {
        if (isProxiedAudiobook) {
          audiobookDebug('prepare: proxied audiobook');
          const result = await prepareProxiedAudiobook({
            manifestUrl: sample.url,
            initialLocation: sample.initialLocation,
          });
          if (cancelled) return;
          if (!result.ok) {
            setError(result.message);
            return;
          }
          setFile(result.file);
          return;
        }

        let url = sample.url;

        if (isStreamedWebPub) {
          const hints = publicationNetworkHints(url);
          publicationDebug(
            'prepare: streamed WebPub (no local download)',
            hints
          );

          const probe = await probeWebPubManifest(url);
          if (cancelled) return;

          if (!probe.ok) {
            const detail =
              probe.status === 0 ? probe.bodyPreview : `HTTP ${probe.status}`;
            setManifestProbeStatus(`JS probe failed: ${detail}`);
            setError(
              `Manifest probe failed (${detail}). ${hints.atsNote} Check Metro for [PublicationDebug] and Xcode for Readium native errors.`
            );
            return;
          }

          setManifestProbeStatus(
            probe.title
              ? `JS probe OK: "${probe.title}" · ${
                  probe.readingOrderCount ?? 0
                } reading-order link(s)`
              : `JS probe OK (HTTP ${probe.status})`
          );
          publicationDebug('prepare: manifest probe succeeded', {
            title: probe.title,
            readingOrderCount: probe.readingOrderCount,
            firstReadingOrderHref: probe.firstReadingOrderHref,
          });

          if (sample.format === 'comic' && probe.manifest) {
            const chapterManifestUrl = resolveStreamedComicChapterManifestUrl(
              url,
              probe.manifest
            );
            if (chapterManifestUrl) {
              publicationDebug(
                'prepare: comic series → first chapter manifest',
                {
                  seriesManifestUrl: url,
                  chapterManifestUrl,
                }
              );
              url = chapterManifestUrl;
            }
          }
        } else if (
          sample.format !== 'audiobook' &&
          !sample.url.startsWith('file://') &&
          sample.format !== 'comic'
        ) {
          const extension = sample.format === 'epub' ? 'epub' : sample.format;
          url = `${FileSystem.documentDirectory}sample.${extension}`;
          publicationDebug('prepare: downloading packaged file', {
            from: sample.url,
            to: url,
          });
          await FileSystem.downloadAsync(sample.url, url);
          publicationDebug('prepare: download finished', { localPath: url });
        }

        if (cancelled) return;

        const nextFile = { url };
        publicationDebug('prepare: opening ReadiumView', { file: nextFile });

        if (cancelled) return;
        setFile(nextFile);
      } catch (err) {
        if (!cancelled) {
          publicationDebug('prepare: threw', err);
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
  }, [
    sample.url,
    sample.format,
    sample.initialLocation,
    isProxiedAudiobook,
    isStreamedWebPub,
    sample.title,
  ]);

  const onPublicationReady = (event: PublicationReadyEvent) => {
    if (isProxiedAudiobook) {
      audiobookDebug('onPublicationReady', {
        metadata: event.metadata,
        tocLinkCount: event.tableOfContents?.length ?? 0,
        positionCount: event.positions?.length ?? 0,
      });
    } else if (isStreamedWebPub) {
      publicationDebug('onPublicationReady (native)', {
        metadata: event.metadata,
        tocLinkCount: event.tableOfContents?.length ?? 0,
        positionCount: event.positions?.length ?? 0,
      });
    }
    setNativeReady(true);
    setPublicationTitle(event.metadata.title);
    setTocCount(event.tableOfContents.length);
    if (format === 'audiobook' && file) {
      onAudiobookReady(file);
    }
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

  if (isProxiedAudiobook) {
    audiobookDebug('ReaderScreen: rendering ReadiumView', { file });
  } else if (isStreamedWebPub) {
    publicationDebug('ReaderScreen: rendering ReadiumView', { file });
  }

  const readerKey = `${format}-${file.url}`;
  const isAudiobook = format === 'audiobook';
  const showAudiobookChrome = isAudiobook && !embeddedInSheet;

  return (
    <View style={[styles.container, isAudiobook && styles.containerAudiobook]}>
      {showAudiobookChrome ? (
        <View style={styles.audiobookHeader}>
          <Pressable
            onPress={onBack}
            style={styles.audiobookHeaderButton}
            accessibilityLabel="Back to library"
          >
            <Text style={styles.audiobookHeaderButtonLabel}>← Library</Text>
          </Pressable>
          <Pressable
            onPress={handleMinimize}
            style={styles.audiobookHeaderButton}
            accessibilityLabel="Minimize player"
          >
            <Text style={styles.audiobookHeaderButtonLabel}>Minimize</Text>
          </Pressable>
        </View>
      ) : format !== 'audiobook' ? (
        <View style={styles.header}>
          <Pressable onPress={onBack} style={styles.backButton}>
            <Text style={styles.backLabel}>← Library</Text>
          </Pressable>
        </View>
      ) : null}

      <View style={[styles.reader, isAudiobook && styles.readerAudiobook]}>
        <ReadiumView
          key={readerKey}
          ref={readerRef}
          file={file}
          preferences={{ theme: format === 'comic' ? 'dark' : 'light' }}
          decorations={format === 'epub' ? decorations : undefined}
          selectionActions={format === 'epub' ? selectionActions : undefined}
          onLocationChange={(locator) => {
            if (isProxiedAudiobook) {
              audiobookDebug('onLocationChange', locator);
            } else if (isStreamedWebPub) {
              publicationDebug('onLocationChange', locator);
            }
            setLocation(locator);
          }}
          onPublicationReady={onPublicationReady}
          onSelectionAction={onSelectionAction}
          audiobookBookmarks={
            format === 'audiobook' ? audiobookBookmarks : undefined
          }
          onAudiobookBookmarkChange={
            format === 'audiobook' ? onAudiobookBookmarkChange : undefined
          }
        />
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1 },
  containerAudiobook: { backgroundColor: '#131418' },
  header: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    marginBottom: 8,
  },
  audiobookHeader: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    paddingHorizontal: 12,
    paddingBottom: 8,
  },
  audiobookHeaderButton: {
    paddingHorizontal: 12,
    paddingVertical: 8,
    borderRadius: 20,
    backgroundColor: 'rgba(255, 255, 255, 0.12)',
  },
  audiobookHeaderButtonLabel: {
    color: '#f5f5f7',
    fontSize: 14,
    fontWeight: '600',
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
  readerAudiobook: { borderRadius: 0 },
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
