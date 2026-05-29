import type {
  Preferences,
  Locator,
  File,
  DecorationGroup,
  SelectionAction,
  PublicationReadyEvent,
  DecorationActivatedEvent,
  SelectionEvent,
  SelectionActionEvent,
  AudiobookPlaybackState,
  AudiobookBookmark,
  AudiobookBookmarkChangeEvent,
} from '../interfaces';

export type ReadiumViewRef = {
  goTo: (locator: Locator) => void;
  goForward: () => void;
  goBackward: () => void;
  play: () => void;
  pause: () => void;
  seekTo: (position: number) => void;
  setPlaybackRate: (rate: number) => void;
  setVolume: (volume: number) => void;
  setSleepTimer: (seconds?: number) => void;
};

export type ReadiumProps = {
  file: File;
  reopenActiveAudiobook?: boolean;
  preferences: Preferences;
  decorations?: DecorationGroup[];
  selectionActions?: SelectionAction[];
  audiobookBookmarks?: AudiobookBookmark[];
  style?: any;
  onLocationChange?: (locator: Locator) => void;
  onPublicationReady?: (event: PublicationReadyEvent) => void;
  onDecorationActivated?: (event: DecorationActivatedEvent) => void;
  onSelectionChange?: (event: SelectionEvent) => void;
  onSelectionAction?: (event: SelectionActionEvent) => void;
  onAudiobookPlaybackStateChange?: (state: AudiobookPlaybackState) => void;
  onAudiobookBookmarkChange?: (event: AudiobookBookmarkChangeEvent) => void;
};
