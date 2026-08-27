import {
  type HybridView,
  type HybridViewProps,
  type HybridViewMethods,
} from 'react-native-nitro-modules';

// ── Locator ──────────────────────────────────────────────────────────────────

export interface LocatorLocations {
  progression: number;
  position?: number;
  totalProgression?: number;
}

export interface LocatorText {
  before?: string;
  highlight?: string;
  after?: string;
}

export interface Locator {
  href: string;
  type: string;
  target?: number;
  title?: string;
  locations?: LocatorLocations;
  text?: LocatorText;
}

// ── Link ─────────────────────────────────────────────────────────────────────

export interface Link {
  href: string;
  title?: string;
  rels?: string[];
  languages?: string[];
  depth?: number;
  hasChildren?: boolean;
  parentHref?: string;
  position?: number;
}

// ── Preferences ──────────────────────────────────────────────────────────────

export interface Preferences {
  backgroundColor?: string;
  columnCount?: string;
  fit?: string;
  fontFamily?: string;
  fontSize?: number;
  fontWeight?: number;
  hyphens?: boolean;
  imageFilter?: string;
  language?: string;
  letterSpacing?: number;
  ligatures?: boolean;
  linkColor?: string;
  lineHeight?: number;
  pageMargins?: number;
  paragraphIndent?: number;
  paragraphSpacing?: number;
  publisherStyles?: boolean;
  readingProgression?: string;
  scroll?: boolean;
  spread?: string;
  textAlign?: string;
  textColor?: string;
  textNormalization?: boolean;
  theme?: string;
  typeScale?: number;
  verticalText?: boolean;
  wordSpacing?: number;
  merging?: boolean;
  comicReadingMode?: string;
  comicScaleType?: string;
  comicStretchSmallPages?: boolean;
  comicWidthLimitEnabled?: boolean;
  comicWidthLimitPercent?: number;
  comicScrollAmountPercent?: number;
  comicImagePreloadAmount?: number;
}

// ── Decoration ───────────────────────────────────────────────────────────────

export interface DecorationStyle {
  type: string;
  tint?: string;
  isActive?: boolean;
  id?: string;
  html?: string;
  css?: string;
  layout?: string;
  width?: string;
}

export interface Decoration {
  id: string;
  locator: Locator;
  style: DecorationStyle;
  extras?: Record<string, string>;
}

export interface DecorationGroup {
  name: string;
  decorations: Decoration[];
}

// ── Rect / Point ─────────────────────────────────────────────────────────────

export interface Rect {
  x: number;
  y: number;
  width: number;
  height: number;
}

export interface Point {
  x: number;
  y: number;
}

// ── Selection ────────────────────────────────────────────────────────────────

export interface SelectionAction {
  id: string;
  label: string;
}

// ── Publication Metadata ─────────────────────────────────────────────────────

export interface Contributor {
  name: string;
  sortAs?: string;
  identifier?: string;
  role?: string;
  position?: number;
}

export interface Subject {
  name: string;
  sortAs?: string;
  code?: string;
  scheme?: string;
}

export interface SeriesInfo {
  name: string;
  position?: number;
}

export interface BelongsTo {
  series?: SeriesInfo[];
  collection?: SeriesInfo[];
}

export interface AccessibilityCertification {
  certifiedBy?: string;
  credential?: string;
  report?: string;
}

export interface Accessibility {
  conformsTo?: string[];
  certification?: AccessibilityCertification;
  accessMode?: string[];
  accessModeSufficient?: string[];
  feature?: string[];
  hazard?: string[];
  summary?: string;
}

export interface PublicationMetadata {
  title: string;
  sortAs?: string;
  subtitle?: string;
  identifier?: string;
  accessibility?: Accessibility;
  modified?: string;
  published?: string;
  language?: string[];
  author?: Contributor[];
  translator?: Contributor[];
  editor?: Contributor[];
  artist?: Contributor[];
  illustrator?: Contributor[];
  letterer?: Contributor[];
  penciler?: Contributor[];
  colorist?: Contributor[];
  inker?: Contributor[];
  narrator?: Contributor[];
  contributor?: Contributor[];
  publisher?: Contributor[];
  imprint?: Contributor[];
  subject?: Subject[];
  layout?: string;
  readingProgression?: string;
  description?: string;
  duration?: number;
  numberOfPages?: number;
  belongsTo?: BelongsTo;
}

// ── Events ───────────────────────────────────────────────────────────────────

export interface PublicationReadyEvent {
  tableOfContents: Link[];
  positions: Locator[];
  metadata: PublicationMetadata;
  capabilities: PublicationCapabilities;
}

export interface PublicationCapabilities {
  search: boolean;
  searchHref?: string;
}

export interface PublicationSearchPage {
  query: string;
  locators: Locator[];
  total?: number;
  hasNext: boolean;
}

export interface DecorationActivatedEvent {
  decoration: Decoration;
  group: string;
  rect?: Rect;
  point?: Point;
}

export interface SelectionEvent {
  locator?: Locator;
  selectedText?: string;
}

export interface SelectionActionEvent {
  locator: Locator;
  selectedText: string;
  actionId: string;
}

export interface AudiobookPlaybackState {
  isPlaying: boolean;
  position: number;
  duration: number;
  rate: number;
  volume: number;
  currentHref?: string;
  currentTitle?: string;
  sleepTimerRemaining?: number;
}

export interface AudiobookBookmark {
  id: string;
  locator: Locator;
  position: number;
  note?: string;
}

export interface AudiobookBookmarkChangeEvent {
  type: string;
  bookmark: AudiobookBookmark;
}

// ── File ─────────────────────────────────────────────────────────────────────

export interface ReadiumFile {
  url: string;
  initialLocation?: Locator;
}

// ── HybridView ───────────────────────────────────────────────────────────────

export interface ReadiumViewProps extends HybridViewProps {
  reopenActiveAudiobook?: boolean;
  file?: ReadiumFile;
  preferences?: Preferences;
  decorations?: DecorationGroup[];
  selectionActions?: SelectionAction[];
  audiobookBookmarks?: AudiobookBookmark[];
  onLocationChange?: (locator: Locator) => void;
  onTap?: (point: Point) => void;
  onPublicationReady?: (event: PublicationReadyEvent) => void;
  onDecorationActivated?: (event: DecorationActivatedEvent) => void;
  onSelectionChange?: (event: SelectionEvent) => void;
  onSelectionAction?: (event: SelectionActionEvent) => void;
  onAudiobookPlaybackStateChange?: (state: AudiobookPlaybackState) => void;
  onAudiobookBookmarkChange?: (event: AudiobookBookmarkChangeEvent) => void;
}

export interface ReadiumViewMethods extends HybridViewMethods {
  goTo(locator: Locator): void;
  goForward(): void;
  goBackward(): void;
  search(query: string): Promise<PublicationSearchPage>;
  searchNext(): Promise<PublicationSearchPage>;
  cancelSearch(): void;
  play(): void;
  pause(): void;
  seekTo(position: number): void;
  setPlaybackRate(rate: number): void;
  setVolume(volume: number): void;
  setSleepTimer(seconds?: number): void;
  destroy(): void;
}

export type ReadiumView = HybridView<ReadiumViewProps, ReadiumViewMethods>;
