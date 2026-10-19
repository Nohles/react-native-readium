import type { ReadiumAudio } from '../specs/ReadiumAudio.nitro';

export function createNativeAudio(): ReadiumAudio {
  throw new Error('Headless ReadiumAudio playback requires iOS or Android.');
}
