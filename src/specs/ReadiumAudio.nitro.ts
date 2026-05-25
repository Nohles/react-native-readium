import type { HybridObject } from 'react-native-nitro-modules';
import type { PublicationMetadata, ReadiumFile } from './ReadiumView.nitro';

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
  open(file: ReadiumFile): void;
  play(): void;
  pause(): void;
  seekTo(position: number): void;
  goForward(): void;
  goBackward(): void;
  setPlaybackRate(rate: number): void;
  setVolume(volume: number): void;
  setSleepTimer(seconds?: number): void;
  close(): void;
}
