import { useCallback, useEffect, useMemo, useRef, useState } from 'react';

import type {
  AudiobookBookmark,
  AudiobookBookmarkChangeEvent,
  AudiobookPlaybackState,
  File,
} from '../interfaces';
import { ReadiumAudio } from '../ReadiumAudio';
import type { ReadiumProps } from '../components/ReadiumView.types';
import {
  normalizeAudiobookPlayerState,
  type AudiobookPlayerState,
} from './audiobookPlayerState';

export type AudiobookPlayerReadiumViewProps = Pick<
  ReadiumProps,
  | 'onAudiobookPlaybackStateChange'
  | 'audiobookBookmarks'
  | 'onAudiobookBookmarkChange'
  | 'reopenActiveAudiobook'
>;

export interface UseAudiobookPlayerOptions {
  file?: File;
  autoOpen?: boolean;
  reopenActiveAudiobook?: boolean;
  audiobookBookmarks?: AudiobookBookmark[];
  onAudiobookBookmarkChange?: (event: AudiobookBookmarkChangeEvent) => void;
  onAudiobookPlaybackStateChange?: (state: AudiobookPlaybackState) => void;
  onStateChange?: (state: AudiobookPlayerState) => void;
  onError?: (error: Error) => void;
}

export interface UseAudiobookPlayerResult {
  state: AudiobookPlayerState;
  isIdle: boolean;
  isLoading: boolean;
  isReady: boolean;
  isPlaying: boolean;
  error?: string;
  open: (file?: File) => Promise<void>;
  play: () => void;
  pause: () => void;
  togglePlayback: () => void;
  seekTo: (position: number) => void;
  goForward: () => void;
  goBackward: () => void;
  setPlaybackRate: (rate: number) => void;
  setVolume: (volume: number) => void;
  setSleepTimer: (seconds?: number) => void;
  close: () => void;
  readiumViewProps: AudiobookPlayerReadiumViewProps;
}

const toError = (error: unknown): Error => {
  return error instanceof Error ? error : new Error(String(error));
};

export function useAudiobookPlayer(
  options: UseAudiobookPlayerOptions = {}
): UseAudiobookPlayerResult {
  const {
    file,
    autoOpen = false,
    reopenActiveAudiobook,
    audiobookBookmarks,
    onAudiobookBookmarkChange,
    onAudiobookPlaybackStateChange,
    onStateChange,
    onError,
  } = options;

  const sessionStateRef = useRef(ReadiumAudio.getState());
  const fileRef = useRef<File | undefined>(file);
  const onStateChangeRef = useRef(onStateChange);
  const onErrorRef = useRef(onError);
  const onAudiobookPlaybackStateChangeRef = useRef(
    onAudiobookPlaybackStateChange
  );

  const [state, setState] = useState(() =>
    normalizeAudiobookPlayerState({ sessionState: sessionStateRef.current })
  );

  fileRef.current = file;
  onStateChangeRef.current = onStateChange;
  onErrorRef.current = onError;
  onAudiobookPlaybackStateChangeRef.current = onAudiobookPlaybackStateChange;

  const updateState = useCallback(
    (nextSessionState = sessionStateRef.current) => {
      setState((previousState) =>
        normalizeAudiobookPlayerState({
          sessionState: nextSessionState,
          previousState,
        })
      );
    },
    []
  );

  const reportError = useCallback((error: unknown) => {
    const normalizedError = toError(error);
    onErrorRef.current?.(normalizedError);
    setState((previousState) => ({
      ...previousState,
      status: 'error',
      isPlaying: false,
      error: normalizedError.message,
      source: 'session',
    }));
  }, []);

  useEffect(() => {
    return ReadiumAudio.subscribe((nextSessionState) => {
      sessionStateRef.current = nextSessionState;
      updateState(nextSessionState);
    });
  }, [updateState]);

  useEffect(() => {
    onStateChangeRef.current?.(state);
  }, [state]);

  const open = useCallback(
    async (nextFile?: File) => {
      const fileToOpen = nextFile ?? fileRef.current;
      if (!fileToOpen) {
        throw new Error('A file is required to open an audiobook.');
      }

      try {
        await ReadiumAudio.open(fileToOpen);
      } catch (error) {
        reportError(error);
        throw error;
      }
    },
    [reportError]
  );

  useEffect(() => {
    if (!autoOpen || !file) {
      return;
    }

    open(file).catch(() => {
      // The hook state and optional onError callback are updated in open().
    });
  }, [autoOpen, file, open]);

  const play = useCallback(() => {
    ReadiumAudio.play();
  }, []);

  const pause = useCallback(() => {
    ReadiumAudio.pause();
  }, []);

  const togglePlayback = useCallback(() => {
    if (state.isPlaying) {
      ReadiumAudio.pause();
    } else {
      ReadiumAudio.play();
    }
  }, [state.isPlaying]);

  const seekTo = useCallback((position: number) => {
    ReadiumAudio.seekTo(position);
  }, []);

  const goForward = useCallback(() => {
    ReadiumAudio.goForward();
  }, []);

  const goBackward = useCallback(() => {
    ReadiumAudio.goBackward();
  }, []);

  const setPlaybackRate = useCallback((rate: number) => {
    ReadiumAudio.setPlaybackRate(rate);
  }, []);

  const setVolume = useCallback((volume: number) => {
    ReadiumAudio.setVolume(volume);
  }, []);

  const setSleepTimer = useCallback((seconds?: number) => {
    ReadiumAudio.setSleepTimer(seconds);
  }, []);

  const close = useCallback(() => {
    ReadiumAudio.close();
    updateState();
  }, [updateState]);

  const handleAudiobookPlaybackStateChange = useCallback(
    (nextPlaybackState: AudiobookPlaybackState) => {
      onAudiobookPlaybackStateChangeRef.current?.(nextPlaybackState);
    },
    []
  );

  const readiumViewProps = useMemo<AudiobookPlayerReadiumViewProps>(
    () => ({
      onAudiobookPlaybackStateChange: handleAudiobookPlaybackStateChange,
      audiobookBookmarks,
      onAudiobookBookmarkChange,
      reopenActiveAudiobook,
    }),
    [
      audiobookBookmarks,
      handleAudiobookPlaybackStateChange,
      onAudiobookBookmarkChange,
      reopenActiveAudiobook,
    ]
  );

  return {
    state,
    isIdle: state.status === 'idle',
    isLoading: state.status === 'loading',
    isReady:
      state.status === 'ready' ||
      state.status === 'playing' ||
      state.status === 'paused',
    isPlaying: state.isPlaying,
    error: state.error,
    open,
    play,
    pause,
    togglePlayback,
    seekTo,
    goForward,
    goBackward,
    setPlaybackRate,
    setVolume,
    setSleepTimer,
    close,
    readiumViewProps,
  };
}

export type { AudiobookPlayerState };
