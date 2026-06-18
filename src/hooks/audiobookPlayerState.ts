import type {
  AudiobookPlaybackState,
  AudiobookSessionState,
  AudiobookSessionStatus,
  PublicationMetadata,
} from '../interfaces';

export type AudiobookPlayerStateSource = 'session' | 'view';

export interface AudiobookPlayerState {
  status: AudiobookSessionStatus;
  isPlaying: boolean;
  publication?: PublicationMetadata;
  position: number;
  duration: number;
  rate: number;
  volume: number;
  currentHref?: string;
  currentTitle?: string;
  sleepTimerRemaining?: number;
  error?: string;
  source?: AudiobookPlayerStateSource;
}

export interface NormalizeAudiobookPlayerStateOptions {
  sessionState?: AudiobookSessionState | null;
  playbackState?: AudiobookPlaybackState | null;
  previousState?: AudiobookPlayerState | null;
}

export const initialAudiobookPlayerState: AudiobookPlayerState = {
  status: 'idle',
  isPlaying: false,
  position: 0,
  duration: 0,
  rate: 1,
  volume: 1,
};

export function normalizeAudiobookPlayerState({
  sessionState,
  playbackState,
  previousState,
}: NormalizeAudiobookPlayerStateOptions): AudiobookPlayerState {
  if (sessionState != null && sessionState.status !== 'idle') {
    return {
      status: sessionState.status,
      isPlaying: sessionState.status === 'playing',
      publication: sessionState.publication ?? previousState?.publication,
      position: sessionState.position,
      duration: sessionState.duration,
      rate: sessionState.rate,
      volume: sessionState.volume,
      currentHref: sessionState.currentHref,
      currentTitle: sessionState.currentTitle,
      sleepTimerRemaining: sessionState.sleepTimerRemaining,
      error: sessionState.error,
      source: 'session',
    };
  }

  if (playbackState != null) {
    return {
      status: playbackState.isPlaying ? 'playing' : 'paused',
      isPlaying: playbackState.isPlaying,
      publication: previousState?.publication,
      position: playbackState.position,
      duration: playbackState.duration,
      rate: playbackState.rate,
      volume: playbackState.volume,
      currentHref: playbackState.currentHref,
      currentTitle: playbackState.currentTitle,
      sleepTimerRemaining: playbackState.sleepTimerRemaining,
      source: 'view',
    };
  }

  if (sessionState != null) {
    return {
      status: sessionState.status,
      isPlaying: false,
      publication: sessionState.publication,
      position: sessionState.position,
      duration: sessionState.duration,
      rate: sessionState.rate,
      volume: sessionState.volume,
      currentHref: sessionState.currentHref,
      currentTitle: sessionState.currentTitle,
      sleepTimerRemaining: sessionState.sleepTimerRemaining,
      error: sessionState.error,
      source: 'session',
    };
  }

  return initialAudiobookPlayerState;
}
