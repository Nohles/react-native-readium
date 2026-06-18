import type { Locator } from 'react-native-readium';

import {
  DEFAULT_PROXIED_INITIAL_LOCATION,
  DEFAULT_PROXIED_MANIFEST_URL,
} from './lib/proxied-audiobook';

export type Format = 'epub' | 'audiobook' | 'comic' | 'pdf';

export type Sample = {
  title: string;
  format: Format;
  url: string;
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
    title: 'Flatland (Audiobook)',
    format: 'audiobook',
    url: 'https://readium.org/webpub-manifest/examples/Flatland/manifest.json',
  },
  {
    title: 'The Martian (Proxied manifest, iOS)',
    format: 'audiobook',
    url: 'http://192.168.1.199:3000/readium/9b4fb794-7711-4aff-aab7-1a8c15378c68/webpub/QW5keSBXZWlyL1RoZSBNYXJ0aWFuL1RoZSBNYXJ0aWFuLm1wMw/manifest.json',
  },

  // RTL + CJK
  {
    title: 'Haruko (RTL + CJK Sample)',
    format: 'epub',
    url: 'https://publication-server.readium.org/webpub/aHR0cHM6Ly9naXRodWIuY29tL0lEUEYvZXB1YjMtc2FtcGxlcy9yZWxlYXNlcy9kb3dubG9hZC8yMDIzMDcwNC9oYXJ1a28taHRtbC1qcGVnLmVwdWI/manifest.json',
  },

  // PDF
  {
    title: 'PDF Sample (iOS)',
    format: 'pdf',
    url: 'https://www.w3.org/WAI/ER/tests/xhtml/testfiles/resources/pdf/dummy.pdf',
  },
  {
    title: 'cadet',
    format: 'comic',
    url: 'http://localhost:15080/webpub/QSBDYWRldCBCZWNvbWVzIGEgUHJvcGhldF8h/manifest.json',
  },
];
