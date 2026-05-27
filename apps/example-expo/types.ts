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
  {
    title: 'reaader-test',
    format: 'epub',
    url: 'http://localhost:3000/readium/c5c93e39-fb55-4cf3-87b5-bf86689d7cb0/webpub/QW5keSBXZWlyL1RoZSBNYXJ0aWFuL0FuZHkgV2VpciAtIFRoZSBNYXJ0aWFuLmVwdWI/manifest.json',
  },
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
  {
    title: 'Thorium Reader User Guide (English)',
    format: 'epub',
    url: 'https://publication-server.readium.org/webpub/Z3M6Ly9yZWFkaXVtLXBsYXlncm91bmQtZmlsZXMvdGhvcml1bS1kZXNrdG9wLXVzZXItZ3VpZGUvdGhvcml1bS1yZWFkZXItdXNlci1ndWlkZS1lbmdsaXNoLmVwdWI/manifest.json',
  },
  {
    title: 'Thorium Reader User Guide (French)',
    format: 'epub',
    url: 'https://publication-server.readium.org/webpub/Z3M6Ly9yZWFkaXVtLXBsYXlncm91bmQtZmlsZXMvdGhvcml1bS1kZXNrdG9wLXVzZXItZ3VpZGUvZ3VpZGUtdXRpbGlzYXRldXItdGhvcml1bS1yZWFkZXItZnJhbmNhaXMuZXB1Yg/manifest.json',
  },
  {
    title: 'Thorium Reader User Guide (Spanish)',
    format: 'epub',
    url: 'https://publication-server.readium.org/webpub/Z3M6Ly9yZWFkaXVtLXBsYXlncm91bmQtZmlsZXMvdGhvcml1bS1kZXNrdG9wLXVzZXItZ3VpZGUvZ3VpYS11c3VhcmlvLXRob3JpdW0tcmVhZGVyLWVzcGFub2wuZXB1Yg/manifest.json',
  },
  {
    title: 'Fundamental Accessibility Tests: Basic Functionality v2.0.0',
    format: 'epub',
    url: 'https://publication-server.readium.org/webpub/aHR0cHM6Ly9naXRodWIuY29tL2RhaXN5L2VwdWItYWNjZXNzaWJpbGl0eS10ZXN0cy9yZWxlYXNlcy9kb3dubG9hZC9mdW5kYW1lbnRhbC0yLjAvRnVuZGFtZW50YWwtQWNjZXNzaWJpbGl0eS1UZXN0cy1CYXNpYy1GdW5jdGlvbmFsaXR5LXYyLjAuMC5lcHVi/manifest.json',
  },
  {
    title: 'Fundamental Accessibility Tests: Non-Visual Reading v2.0.1',
    format: 'epub',
    url: 'https://publication-server.readium.org/webpub/aHR0cHM6Ly9naXRodWIuY29tL2RhaXN5L2VwdWItYWNjZXNzaWJpbGl0eS10ZXN0cy9yZWxlYXNlcy9kb3dubG9hZC9ub24tdmlzdWFsLXJlYWRpbmctMi4wLjEvRnVuZGFtZW50YWwtQWNjZXNzaWJpbGl0eS1UZXN0cy1Ob24tVmlzdWFsLVJlYWRpbmctdjIuMC4xLmVwdWI/manifest.json',
  },
  {
    title: 'Fundamental Accessibility Tests: Visual Adjustments v2.0.0',
    format: 'epub',
    url: 'https://publication-server.readium.org/webpub/aHR0cHM6Ly9naXRodWIuY29tL2RhaXN5L2VwdWItYWNjZXNzaWJpbGl0eS10ZXN0cy9yZWxlYXNlcy9kb3dubG9hZC9mdW5kYW1lbnRhbC0yLjAvRnVuZGFtZW50YWwtQWNjZXNzaWJpbGl0eS1UZXN0cy1WaXN1YWwtQWRqdXN0bWVudHMtdjIuMC4wLmVwdWI/manifest.json',
  },
  {
    title: 'Advanced Accessibility Tests: Media Overlays v1.0.0',
    format: 'epub',
    url: 'https://publication-server.readium.org/webpub/aHR0cHM6Ly9naXRodWIuY29tL2RhaXN5L2VwdWItYWNjZXNzaWJpbGl0eS10ZXN0cy9yZWxlYXNlcy9kb3dubG9hZC9tZWRpYS1vdmVybGF5cy0xLjAvQWR2YW5jZWQtQWNjZXNzaWJpbGl0eS1UZXN0cy1NZWRpYS1PdmVybGF5cy12MS4wLjAuZXB1Yg/manifest.json',
  },
  {
    title: 'Accessibility Tests: Extended Descriptions v1.1.1',
    format: 'epub',
    url: 'https://publication-server.readium.org/webpub/aHR0cHM6Ly9naXRodWIuY29tL2RhaXN5L2VwdWItYWNjZXNzaWJpbGl0eS10ZXN0cy9yZWxlYXNlcy9kb3dubG9hZC9tYXRoLWV4dGRlc2MtMS4xLjEvQWNjZXNzaWJpbGl0eS1UZXN0cy1FeHRlbmRlZC1EZXNjcmlwdGlvbnMtdjEuMS4xLmVwdWI/manifest.json',
  },

  // Additional experimental web publications
  {
    title: 'Readium CSS Docs (WebPub)',
    format: 'epub',
    url: 'https://readium.org/css/docs/manifest.json',
  },
  {
    title: 'Moby Dick (Readium Example WebPub)',
    format: 'epub',
    url: 'https://readium.org/webpub-manifest/examples/MobyDick/manifest.json',
  },
  {
    title: 'Molly Hopper (CSS Docs Sample)',
    format: 'epub',
    url: 'https://readium.org/css/docs/manifest.json',
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
  {
    title: 'Israel Sailing (RTL + CJK Sample)',
    format: 'epub',
    url: 'https://publication-server.readium.org/webpub/aHR0cHM6Ly9naXRodWIuY29tL0lEUEYvZXB1YjMtc2FtcGxlcy9yZWxlYXNlcy9kb3dubG9hZC8yMDIzMDcwNC9pc3JhZWxzYWlsaW5nLmVwdWI/manifest.json',
  },
  {
    title: 'JLReq (RTL + CJK Sample)',
    format: 'epub',
    url: 'https://publication-server.readium.org/webpub/aHR0cHM6Ly9naXRodWIuY29tL0lEUEYvZXB1YjMtc2FtcGxlcy9yZWxlYXNlcy9kb3dubG9hZC8yMDIzMDcwNC9qbHJlcS1pbi1qYXBhbmVzZS5lcHVi/manifest.json',
  },
  {
    title: 'Kusamakura (RTL + CJK Sample)',
    format: 'epub',
    url: 'https://publication-server.readium.org/webpub/aHR0cHM6Ly9naXRodWIuY29tL0lEUEYvZXB1YjMtc2FtcGxlcy9yZWxlYXNlcy9kb3dubG9hZC8yMDIzMDcwNC9rdXNhbWFrdXJhLWphcGFuZXNlLXZlcnRpY2FsLXdyaXRpbmcuZXB1Yg/manifest.json',
  },
  {
    title: 'Regime Anticancer Arabic (RTL + CJK Sample)',
    format: 'epub',
    url: 'https://publication-server.readium.org/webpub/aHR0cHM6Ly9naXRodWIuY29tL0lEUEYvZXB1YjMtc2FtcGxlcy9yZWxlYXNlcy9kb3dubG9hZC8yMDIzMDcwNC9yZWdpbWUtYW50aWNhbmNlci1hcmFiaWMuZXB1Yg/manifest.json',
  },

  // PDF
  {
    title: 'PDF Sample (iOS)',
    format: 'pdf',
    url: 'https://www.w3.org/WAI/ER/tests/xhtml/testfiles/resources/pdf/dummy.pdf',
  },

  // Other
  {
    title: 'Moby Dick (Packaged EPUB)',
    format: 'epub',
    url: 'https://www.gutenberg.org/ebooks/2701.epub3.images',
  },
];
