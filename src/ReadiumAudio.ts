import { Platform } from 'react-native';
import { NitroModules } from 'react-native-nitro-modules';

import type {
  AudiobookBookmark,
  AudiobookBookmarkChangeEvent,
} from './interfaces';
import type { File } from './interfaces';
import type {
  AudiobookSessionState,
  NowPlayingMetadata,
  ReadiumAudio as NativeReadiumAudio,
} from './specs/ReadiumAudio.nitro';

type Listener = (state: AudiobookSessionState) => void;
type BookmarkListener = (event: AudiobookBookmarkChangeEvent) => void;

let nativeAudio: NativeReadiumAudio | undefined;
const listeners = new Set<Listener>();
const bookmarkListeners = new Set<BookmarkListener>();
const idleState: AudiobookSessionState = {
  status: 'idle',
  position: 0,
  duration: 0,
  rate: 1,
  volume: 1,
};
let currentState: AudiobookSessionState = idleState;

function getNativeAudio(): NativeReadiumAudio {
  if (!nativeAudio) {
    nativeAudio =
      NitroModules.createHybridObject<NativeReadiumAudio>('ReadiumAudio');
    nativeAudio.onStateChange = (state) => {
      emitState(state);
    };
    nativeAudio.onBookmarkChange = (event) => {
      bookmarkListeners.forEach((listener) => listener(event));
    };
  }

  return nativeAudio;
}

function emitState(state: AudiobookSessionState): void {
  currentState = state;
  listeners.forEach((listener) => listener(state));
}

/**
 * How long `open` waits for the session to reach `ready` or `error`.
 *
 * The dominant cost of an open is per-track duration resolution: for every
 * reading-order item whose manifest entry carries no `duration`, the Android
 * navigator opens the resource and runs `MediaMetadataRetriever` over it (see
 * `AudioNavigatorFactory.duration` in the kotlin-toolkit). That work cannot be
 * moved off the main thread — `ExoPlayer` requires its application thread, and
 * `createNavigator` reaches `setMediaItems` — so for a remote multi-track
 * audiobook the open legitimately takes minutes on a slow connection.
 *
 * A short deadline therefore converts a slow-but-successful open into a hard
 * failure that looks exactly like a broken one. Ten minutes is deliberately
 * generous: the cost of being wrong in this direction is the user staring at a
 * Retry button for a book that would have opened a minute later.
 */
const DEFAULT_OPEN_TIMEOUT_MS = 10 * 60 * 1000;

let openTimeoutMs = DEFAULT_OPEN_TIMEOUT_MS;

function waitForSession(
  predicate: (state: AudiobookSessionState) => boolean,
  timeoutMs: number
): Promise<AudiobookSessionState> {
  return new Promise((resolve, reject) => {
    if (predicate(currentState)) {
      resolve(currentState);
      return;
    }

    let unsubscribe: () => void = () => {};
    const timeout = setTimeout(() => {
      unsubscribe();
      reject(
        new Error(
          `Timed out waiting for audiobook session after ${Math.round(
            timeoutMs / 1000
          )}s.`
        )
      );
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
      (session) => session.status === 'ready' || session.status === 'error',
      openTimeoutMs
    );
    if (state.status === 'error') {
      throw new Error(state.error ?? 'Failed to open audiobook.');
    }
  },

  /**
   * Overrides how long {@link open} waits for the session, in milliseconds.
   *
   * Only worth lowering for a publication known to be local, where the open
   * should be near-instant and a long stall means something is actually wrong.
   * Pass `null` to restore the default.
   */
  setOpenTimeoutMs(timeoutMs: number | null): void {
    openTimeoutMs = timeoutMs ?? DEFAULT_OPEN_TIMEOUT_MS;
  },

  /** The current open deadline in milliseconds. */
  getOpenTimeoutMs(): number {
    return openTimeoutMs;
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

  /**
   * Overrides the descriptive now-playing fields with host-supplied values;
   * `undefined` falls back to the publication's own metadata.
   *
   * This is the cross-platform way to drive the system media entry. Reaching for
   * the platform's own API directly (iOS `MPNowPlayingInfoCenter`) works on one
   * platform only, and Android's media session is owned by the library.
   */
  setNowPlayingMetadata(metadata?: NowPlayingMetadata): void {
    getNativeAudio().setNowPlayingMetadata(metadata);
  },

  setSleepTimer(seconds?: number): void {
    getNativeAudio().setSleepTimer(seconds);
  },

  /**
   * Replaces the session's bookmark list. Each bookmark is acknowledged with an
   * `update` change event, so a host that persists bookmarks elsewhere sees
   * them round-trip.
   */
  setBookmarks(bookmarks: AudiobookBookmark[]): void {
    getNativeAudio().setBookmarks(bookmarks);
  },

  /** Adds a bookmark at `position` seconds on the chapter timeline. */
  addBookmark(position: number, note?: string): void {
    getNativeAudio().addBookmark(position, note);
  },

  /** Updates the note on an existing bookmark. No-op if the id is unknown. */
  updateBookmark(id: string, note?: string): void {
    getNativeAudio().updateBookmark(id, note);
  },

  /** Removes a bookmark. No-op if the id is unknown. */
  removeBookmark(id: string): void {
    getNativeAudio().removeBookmark(id);
  },

  close(): void {
    getNativeAudio().close();
    emitState(idleState);
  },

  subscribe(listener: Listener): () => void {
    listeners.add(listener);
    listener(currentState);
    if (Platform.OS === 'android' || Platform.OS === 'ios') {
      getNativeAudio();
    }
    return () => listeners.delete(listener);
  },

  subscribeBookmarks(listener: BookmarkListener): () => void {
    bookmarkListeners.add(listener);
    if (Platform.OS === 'android' || Platform.OS === 'ios') {
      getNativeAudio();
    }
    return () => bookmarkListeners.delete(listener);
  },
};
