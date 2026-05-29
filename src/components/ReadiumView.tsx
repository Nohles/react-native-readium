import React, {
  useCallback,
  useEffect,
  useState,
  forwardRef,
  useRef,
  useImperativeHandle,
} from 'react';
import { View, StyleSheet } from 'react-native';
import { callback } from 'react-native-nitro-modules';

import type { Dimensions } from '../interfaces';
import type { PublicationReadyEvent as SpecPublicationReadyEvent } from '../specs/ReadiumView.nitro';
import { buildLinkTree } from '../utils/buildLinkTree';
import { NitroReadiumView } from './NitroReadiumView';
export type { ReadiumViewRef, ReadiumProps } from './ReadiumView.types';
import type { ReadiumViewRef, ReadiumProps } from './ReadiumView.types';

export const ReadiumView = forwardRef<ReadiumViewRef, ReadiumProps>(
  (
    {
      onLocationChange,
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
      ...props
    },
    forwardedRef
  ) => {
    const hybridRef = useRef<any>(null);
    const [{ height, width }, setDimensions] = useState<Dimensions>({
      width: 0,
      height: 0,
    });

    const onLayout = useCallback(
      ({
        nativeEvent: {
          layout: { width: layoutWidth, height: layoutHeight },
        },
      }: any) => {
        setDimensions({
          width: layoutWidth,
          height: layoutHeight,
        });
      },
      []
    );

    const noop = () => {};

    const handlePublicationReady = useCallback(
      (event: SpecPublicationReadyEvent) => {
        if (!onPublicationReady) return;
        onPublicationReady({
          ...event,
          tableOfContents: buildLinkTree(event.tableOfContents),
        });
      },
      [onPublicationReady]
    );

    useImperativeHandle(
      forwardedRef,
      () => ({
        goTo: (locator) => hybridRef.current?.goTo(locator),
        goForward: () => hybridRef.current?.goForward(),
        goBackward: () => hybridRef.current?.goBackward(),
        play: () => hybridRef.current?.play(),
        pause: () => hybridRef.current?.pause(),
        seekTo: (position) => hybridRef.current?.seekTo(position),
        setPlaybackRate: (rate) => hybridRef.current?.setPlaybackRate(rate),
        setVolume: (volume) => hybridRef.current?.setVolume(volume),
        setSleepTimer: (seconds) => hybridRef.current?.setSleepTimer(seconds),
      }),
      []
    );

    useEffect(() => {
      return () => {
        hybridRef.current?.destroy();
      };
    }, []);

    const isReady = width > 0 && height > 0;

    return (
      <View style={styles.container} onLayout={onLayout}>
        {isReady && (
          <NitroReadiumView
            style={{ width, height }}
            {...props}
            reopenActiveAudiobook={reopenActiveAudiobook}
            preferences={preferences}
            decorations={decorations}
            selectionActions={selectionActions ?? []}
            audiobookBookmarks={audiobookBookmarks}
            onLocationChange={callback(onLocationChange ?? noop)}
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
            hybridRef={callback((ref: any) => {
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
