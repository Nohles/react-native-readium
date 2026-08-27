import React, {
  useCallback,
  useEffect,
  useState,
  forwardRef,
  useRef,
  useImperativeHandle,
} from 'react';
import { View, StyleSheet, type LayoutChangeEvent } from 'react-native';
import { callback } from 'react-native-nitro-modules';

import type { Dimensions } from '../interfaces';
import type {
  PublicationReadyEvent as SpecPublicationReadyEvent,
  PublicationSearchPage,
  ReadiumViewMethods,
} from '../specs/ReadiumView.nitro';
import { buildLinkTree } from '../utils/buildLinkTree';
import {
  expandSearchHref,
  fetchRemoteSearchPage,
} from '../utils/remotePublicationSearch';
import { NitroReadiumView } from './NitroReadiumView';
export type { ReadiumViewRef, ReadiumProps } from './ReadiumView.types';
import type { ReadiumViewRef, ReadiumProps } from './ReadiumView.types';

const noop = () => {};

export const ReadiumView = forwardRef<ReadiumViewRef, ReadiumProps>(
  (
    {
      onLocationChange,
      onTap,
      onPublicationReady,
      onDecorationActivated,
      onSelectionChange,
      onSelectionAction,
      onAudiobookPlaybackStateChange,
      onAudiobookBookmarkChange,
      preferences,
      decorations,
      selectionActions,
      audiobookBookmarks,
      reopenActiveAudiobook,
      file,
      ...props
    },
    forwardedRef
  ) => {
    const hybridRef = useRef<ReadiumViewMethods | null>(null);
    const remoteSearchAbort = useRef<AbortController | null>(null);
    const remoteSearchHref = useRef<string | undefined>(undefined);
    const remoteSearchNextHref = useRef<string | undefined>(undefined);
    const remoteSearchQuery = useRef('');
    const [{ height, width }, setDimensions] = useState<Dimensions>({
      width: 0,
      height: 0,
    });

    const onLayout = useCallback(
      ({
        nativeEvent: {
          layout: { width: layoutWidth, height: layoutHeight },
        },
      }: LayoutChangeEvent) => {
        setDimensions({
          width: layoutWidth,
          height: layoutHeight,
        });
      },
      []
    );

    const handlePublicationReady = useCallback(
      (event: SpecPublicationReadyEvent) => {
        remoteSearchHref.current = event.capabilities.searchHref;
        remoteSearchNextHref.current = undefined;
        remoteSearchQuery.current = '';
        if (!onPublicationReady) return;
        onPublicationReady({
          ...event,
          tableOfContents: buildLinkTree(event.tableOfContents),
        });
      },
      [onPublicationReady]
    );

    const cancelRemoteSearch = useCallback(() => {
      remoteSearchAbort.current?.abort();
      remoteSearchAbort.current = null;
      remoteSearchNextHref.current = undefined;
    }, []);

    useEffect(() => {
      cancelRemoteSearch();
      remoteSearchHref.current = undefined;
      remoteSearchQuery.current = '';
    }, [cancelRemoteSearch, file.url]);

    const remoteSearch = useCallback(
      async (
        query: string,
        nextHref?: string
      ): Promise<PublicationSearchPage> => {
        const searchHref = remoteSearchHref.current;
        if (!searchHref) {
          throw new Error('Remote publication search is unavailable.');
        }
        const normalizedQuery = query.trim();
        if (!normalizedQuery) {
          throw new Error('Search query must not be empty.');
        }
        cancelRemoteSearch();
        const controller = new AbortController();
        remoteSearchAbort.current = controller;
        const href =
          nextHref ?? expandSearchHref(searchHref, file.url, normalizedQuery);
        try {
          const page = await fetchRemoteSearchPage({
            href,
            query: normalizedQuery,
            signal: controller.signal,
          });
          remoteSearchQuery.current = normalizedQuery;
          remoteSearchNextHref.current = page.nextHref;
          return page;
        } finally {
          if (remoteSearchAbort.current === controller) {
            remoteSearchAbort.current = null;
          }
        }
      },
      [cancelRemoteSearch, file.url]
    );

    useImperativeHandle(
      forwardedRef,
      () => ({
        goTo: (locator) => hybridRef.current?.goTo(locator),
        goForward: () => hybridRef.current?.goForward(),
        goBackward: () => hybridRef.current?.goBackward(),
        search: (query) =>
          remoteSearchHref.current
            ? remoteSearch(query)
            : hybridRef.current?.search(query) ??
              Promise.reject(new Error('Publication search is unavailable.')),
        searchNext: () => {
          if (remoteSearchHref.current) {
            const nextHref = remoteSearchNextHref.current;
            if (!nextHref) {
              return Promise.resolve({
                query: remoteSearchQuery.current,
                locators: [],
                hasNext: false,
              });
            }
            return remoteSearch(remoteSearchQuery.current, nextHref);
          }
          return (
            hybridRef.current?.searchNext() ??
            Promise.reject(new Error('Publication search is unavailable.'))
          );
        },
        cancelSearch: () => {
          cancelRemoteSearch();
          hybridRef.current?.cancelSearch();
        },
        play: () => hybridRef.current?.play(),
        pause: () => hybridRef.current?.pause(),
        seekTo: (position) => hybridRef.current?.seekTo(position),
        setPlaybackRate: (rate) => hybridRef.current?.setPlaybackRate(rate),
        setVolume: (volume) => hybridRef.current?.setVolume(volume),
        setSleepTimer: (seconds) => hybridRef.current?.setSleepTimer(seconds),
      }),
      [cancelRemoteSearch, remoteSearch]
    );

    useEffect(() => {
      return () => {
        cancelRemoteSearch();
        hybridRef.current?.cancelSearch();
        hybridRef.current?.destroy();
      };
    }, [cancelRemoteSearch]);

    const isReady = width > 0 && height > 0;

    return (
      <View style={styles.container} onLayout={onLayout}>
        {isReady && (
          <NitroReadiumView
            style={{ width, height }}
            {...props}
            file={file}
            reopenActiveAudiobook={reopenActiveAudiobook}
            preferences={preferences}
            decorations={decorations}
            selectionActions={selectionActions ?? []}
            audiobookBookmarks={audiobookBookmarks}
            onLocationChange={callback(onLocationChange ?? noop)}
            onTap={callback(onTap ?? noop)}
            onPublicationReady={callback(handlePublicationReady)}
            onDecorationActivated={callback(onDecorationActivated ?? noop)}
            onSelectionChange={callback(onSelectionChange ?? noop)}
            onSelectionAction={callback(onSelectionAction ?? noop)}
            onAudiobookPlaybackStateChange={callback(
              onAudiobookPlaybackStateChange ?? noop
            )}
            onAudiobookBookmarkChange={callback(
              onAudiobookBookmarkChange ?? noop
            )}
            hybridRef={callback((ref: ReadiumViewMethods) => {
              hybridRef.current = ref;
            })}
          />
        )}
      </View>
    );
  }
);

const styles = StyleSheet.create({
  container: { width: '100%', height: '100%' },
});
