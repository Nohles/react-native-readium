import { NitroModules } from 'react-native-nitro-modules';
import type { ReadiumAudio } from '../specs/ReadiumAudio.nitro';

export function createNativeAudio(): ReadiumAudio {
  return NitroModules.createHybridObject<ReadiumAudio>('ReadiumAudio');
}
