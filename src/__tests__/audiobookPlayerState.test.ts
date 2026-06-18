import {
  normalizeAudiobookPlayerState,
  type AudiobookPlayerState,
} from '../hooks/audiobookPlayerState';
import type {
  AudiobookPlaybackState,
  AudiobookSessionState,
} from '../interfaces';

const idleSession: AudiobookSessionState = {
  status: 'idle',
  position: 0,
  duration: 0,
  rate: 1,
  volume: 1,
};

const playbackState: AudiobookPlaybackState = {
  isPlaying: true,
  position: 12,
  duration: 120,
  rate: 1.25,
  volume: 0.8,
  currentHref: 'chapter-1.mp3',
  currentTitle: 'Chapter 1',
};

it('normalizes idle session state', () => {
  expect(normalizeAudiobookPlayerState({ sessionState: idleSession })).toEqual({
    status: 'idle',
    isPlaying: false,
    position: 0,
    duration: 0,
    rate: 1,
    volume: 1,
    currentHref: undefined,
    currentTitle: undefined,
    sleepTimerRemaining: undefined,
    error: undefined,
    publication: undefined,
    source: 'session',
  });
});

it('normalizes loading and error session states', () => {
  expect(
    normalizeAudiobookPlayerState({
      sessionState: {
        ...idleSession,
        status: 'loading',
      },
    })
  ).toMatchObject({
    status: 'loading',
    isPlaying: false,
    source: 'session',
  });

  expect(
    normalizeAudiobookPlayerState({
      sessionState: {
        ...idleSession,
        status: 'error',
        error: 'Unable to open audiobook.',
      },
    })
  ).toMatchObject({
    status: 'error',
    isPlaying: false,
    error: 'Unable to open audiobook.',
    source: 'session',
  });
});

it('normalizes playing and paused view playback states', () => {
  expect(
    normalizeAudiobookPlayerState({
      sessionState: idleSession,
      playbackState,
    })
  ).toMatchObject({
    status: 'playing',
    isPlaying: true,
    position: 12,
    duration: 120,
    rate: 1.25,
    volume: 0.8,
    currentHref: 'chapter-1.mp3',
    currentTitle: 'Chapter 1',
    source: 'view',
  });

  expect(
    normalizeAudiobookPlayerState({
      sessionState: idleSession,
      playbackState: {
        ...playbackState,
        isPlaying: false,
      },
    })
  ).toMatchObject({
    status: 'paused',
    isPlaying: false,
    source: 'view',
  });
});

it('prefers active persistent session state over view playback state', () => {
  const state = normalizeAudiobookPlayerState({
    sessionState: {
      ...idleSession,
      status: 'playing',
      position: 40,
      duration: 200,
      rate: 1,
      volume: 1,
      currentTitle: 'Session chapter',
    },
    playbackState: {
      ...playbackState,
      isPlaying: false,
      position: 10,
      currentTitle: 'View chapter',
    },
  });

  expect(state).toMatchObject({
    status: 'playing',
    isPlaying: true,
    position: 40,
    duration: 200,
    currentTitle: 'Session chapter',
    source: 'session',
  });
});

it('preserves publication metadata when view playback updates', () => {
  const previousState: AudiobookPlayerState = {
    ...normalizeAudiobookPlayerState({
      sessionState: {
        ...idleSession,
        status: 'ready',
        publication: {
          title: 'Flatland',
        },
      },
    }),
  };

  expect(
    normalizeAudiobookPlayerState({
      sessionState: idleSession,
      playbackState,
      previousState,
    }).publication
  ).toEqual({ title: 'Flatland' });
});
