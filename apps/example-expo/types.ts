import type { Locator } from 'react-native-readium';

import {
  DEFAULT_PROXIED_INITIAL_LOCATION,
  DEFAULT_PROXIED_MANIFEST_URL,
} from './helpers/proxied-audiobook';

export type Format = 'epub' | 'audiobook' | 'comic' | 'pdf';

export type Sample = {
  title: string;
  format: Format;
  url: string;
  asset?: number;
  /** Reader-style HTTP manifest test (probe manifest + audio, debug logs). */
  proxied?: boolean;
  initialLocation?: Locator;
};
export const samples: Sample[] = [
  // Ebook publications
  {
    title: 'Moby Dick (Streamed WebPub)',
    format: 'epub',
    url: 'https://publication-server.readium.org/webpub/Z3M6Ly9yZWFkaXVtLXBsYXlncm91bmQtZmlsZXMvZGVtby9tb2J5LWRpY2suZXB1Yg/manifest.json',
  },
  {
    title: 'The House of Seven Gables (WebPub)',
    format: 'epub',
    url: 'https://publication-server.readium.org/webpub/Z3M6Ly9yZWFkaXVtLXBsYXlncm91bmQtZmlsZXMvZGVtby9uYXRoYW5pZWwtaGF3dGhvcm5lX3RoZS1ob3VzZS1vZi10aGUtc2V2ZW4tZ2FibGVzX2FkdmFuY2VkLmVwdWI/manifest.json',
  },
  {
    title: 'Les Diaboliques (WebPub)',
    format: 'epub',
    url: 'https://publication-server.readium.org/webpub/Z3M6Ly9yZWFkaXVtLXBsYXlncm91bmQtZmlsZXMvZGVtby9sZXNfZGlhYm9saXF1ZXMuZXB1Yg/manifest.json',
  },
  {
    title: 'Bella the Dragon (WebPub)',
    format: 'epub',
    url: 'https://publication-server.readium.org/webpub/Z3M6Ly9yZWFkaXVtLXBsYXlncm91bmQtZmlsZXMvZGVtby9CZWxsYU9yaWdpbmFsMy5lcHVi/manifest.json',
  },

  // Audiobooks
  {
    title: 'Readium Sample Audiobook',
    format: 'audiobook',
    url: 'readium-sample.m4b',
    asset: require('../example-native/resources/readium-sample.m4b'),
  },
  {
    title: 'The Martian (Proxied manifest)',
    format: 'audiobook',
    url: DEFAULT_PROXIED_MANIFEST_URL,
    proxied: true,
    initialLocation: DEFAULT_PROXIED_INITIAL_LOCATION,
  },

  // RTL + CJK
  {
    title: 'Haruko (RTL + CJK Sample)',
    format: 'epub',
    url: 'https://publication-server.readium.org/webpub/aHR0cHM6Ly9naXRodWIuY29tL0lEUEYvZXB1YjMtc2FtcGxlcy9yZWxlYXNlcy9kb3dubG9hZC8yMDIzMDcwNC9oYXJ1a28taHRtbC1qcGVnLmVwdWI/manifest.json',
  },

  // PDF
  {
    title: 'PDF Sample',
    format: 'pdf',
    url: 'https://www.w3.org/WAI/ER/tests/xhtml/testfiles/resources/pdf/dummy.pdf',
  },
  {
    title: 'cadet',
    format: 'comic',
    url: 'http://localhost:15080/webpub/QSBDYWRldCBCZWNvbWVzIGEgUHJvcGhldF8h/manifest.json',
  },
];
