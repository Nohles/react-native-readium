import { Platform } from 'react-native';
import { NitroModules } from 'react-native-nitro-modules';

import type { File } from './interfaces';
import type {
  AudiobookSessionState,
  ReadiumAudio as NativeReadiumAudio,
} from './specs/ReadiumAudio.nitro';

type Listener = (state: AudiobookSessionState) => void;

let nativeAudio: NativeReadiumAudio | undefined;
const listeners = new Set<Listener>();
const idleState: AudiobookSessionState = {
  status: 'idle',
  position: 0,
  duration: 0,
  rate: 1,
  volume: 1,
};
let currentState: AudiobookSessionState = idleState;

const unsupportedError = () =>
  new Error('Readium audiobook sessions are currently supported on iOS only.');

function getNativeAudio(): NativeReadiumAudio {
  if (Platform.OS !== 'ios') {
    throw unsupportedError();
  }

  if (!nativeAudio) {
    nativeAudio =
      NitroModules.createHybridObject<NativeReadiumAudio>('ReadiumAudio');
    nativeAudio.onStateChange = (state) => {
      emitState(state);
    };
  }

  return nativeAudio;
}

function emitState(state: AudiobookSessionState): void {
  currentState = state;
  listeners.forEach((listener) => listener(state));
}

function waitForSession(
  predicate: (state: AudiobookSessionState) => boolean,
  timeoutMs = 120_000
): Promise<AudiobookSessionState> {
  return new Promise((resolve, reject) => {
    if (predicate(currentState)) {
      resolve(currentState);
      return;
    }

    let unsubscribe: () => void = () => {};
    const timeout = setTimeout(() => {
      unsubscribe();
      reject(new Error('Timed out waiting for audiobook session.'));
    }, timeoutMs);

    const listener: Listener = (state) => {
      if (predicate(state)) {
        clearTimeout(timeout);
        unsubscribe();
        resolve(state);
      }
    };

    listeners.add(listener);
    listener(currentState);
    unsubscribe = () => listeners.delete(listener);
  });
}

export const ReadiumAudio = {
  getState(): AudiobookSessionState {
    return currentState;
  },

  async open(file: File): Promise<void> {
    getNativeAudio().open(file);
    const state = await waitForSession(
      (session) => session.status === 'ready' || session.status === 'error'
    );
    if (state.status === 'error') {
      throw new Error(state.error ?? 'Failed to open audiobook.');
    }
  },

  play(): void {
    getNativeAudio().play();
  },

  pause(): void {
    getNativeAudio().pause();
  },

  seekTo(position: number): void {
    getNativeAudio().seekTo(position);
  },

  goForward(): void {
    getNativeAudio().goForward();
  },

  goBackward(): void {
    getNativeAudio().goBackward();
  },

  setPlaybackRate(rate: number): void {
    getNativeAudio().setPlaybackRate(rate);
  },

  setVolume(volume: number): void {
    getNativeAudio().setVolume(volume);
  },

  setNowPlayingInfoEnabled(enabled: boolean): void {
    getNativeAudio().setNowPlayingInfoEnabled(enabled);
  },

  setNowPlayingMetadataEnabled(enabled: boolean): void {
    getNativeAudio().setNowPlayingMetadataEnabled(enabled);
  },

  setSleepTimer(seconds?: number): void {
    getNativeAudio().setSleepTimer(seconds);
  },

  close(): void {
    if (Platform.OS === 'ios') {
      getNativeAudio().close();
    }
    emitState(idleState);
  },

  subscribe(listener: Listener): () => void {
    listeners.add(listener);
    listener(currentState);
    return () => listeners.delete(listener);
  },
};
