import type { HybridObject } from 'react-native-nitro-modules';
import type {
  AudiobookBookmark,
  AudiobookBookmarkChangeEvent,
  PublicationMetadata,
  ReadiumFile,
} from './ReadiumView.nitro';

export type AudiobookSessionStatus =
  | 'idle'
  | 'loading'
  | 'ready'
  | 'playing'
  | 'paused'
  | 'ended'
  | 'error';

export interface AudiobookSessionState {
  status: AudiobookSessionStatus;
  publication?: PublicationMetadata;
  position: number;
  duration: number;
  rate: number;
  volume: number;
  currentHref?: string;
  currentTitle?: string;
  sleepTimerRemaining?: number;
  error?: string;
}

export interface ReadiumAudio
  extends HybridObject<{ ios: 'swift'; android: 'kotlin' }> {
  onStateChange?: (state: AudiobookSessionState) => void;
  onBookmarkChange?: (event: AudiobookBookmarkChangeEvent) => void;
  open(file: ReadiumFile): void;
  play(): void;
  pause(): void;
  seekTo(position: number): void;
  goForward(): void;
  goBackward(): void;
  setPlaybackRate(rate: number): void;
  setVolume(volume: number): void;
  setNowPlayingInfoEnabled(enabled: boolean): void;
  setNowPlayingMetadataEnabled(enabled: boolean): void;
  setSleepTimer(seconds?: number): void;
  /**
   * Replaces the session's bookmark list. Every bookmark emits an `update`
   * change event, so a host that persists bookmarks elsewhere can hand them back
   * to the session without losing the round trip.
   */
  setBookmarks(bookmarks: AudiobookBookmark[]): void;
  /** Adds a bookmark at [position] seconds on the chapter timeline. */
  addBookmark(position: number, note?: string): void;
  /** Updates the note on an existing bookmark. No-op if [id] is unknown. */
  updateBookmark(id: string, note?: string): void;
  /** Removes a bookmark. No-op if [id] is unknown. */
  removeBookmark(id: string): void;
  close(): void;
}
