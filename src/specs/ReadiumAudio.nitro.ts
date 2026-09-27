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

/**
 * Descriptive fields a host can supply for the system now-playing entry
 * (lock screen, media notification, notification shade).
 *
 * The publication's own metadata is used when this is not set, so a host only
 * needs to supply what it knows better — typically the server-side title, author
 * and cover, which are richer than what the publication file declares.
 */
export interface NowPlayingMetadata {
  title?: string;
  artist?: string;
  albumTitle?: string;
  /** Absolute http(s) URL or a file/content URI. */
  artworkUrl?: string;
  defaultPlaybackRate?: number;
}

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
  /**
   * Overrides the descriptive now-playing fields with host-supplied values.
   * Pass undefined to fall back to the publication's own metadata.
   *
   * iOS writes these to `MPNowPlayingInfoCenter`. Android has no equivalent
   * setter on the media session — descriptive metadata lives on the player's
   * playlist — so it is applied there. Both update live; neither requires a
   * reload of the book.
   */
  setNowPlayingMetadata(metadata?: NowPlayingMetadata): void;
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
