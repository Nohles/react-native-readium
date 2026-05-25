export type Format = 'epub' | 'audiobook' | 'comic' | 'pdf';

export type Sample = {
  title: string;
  format: Format;
  url: string;
};

export const samples: Sample[] = [
  {
    title: 'Moby Dick (EPUB)',
    format: 'epub',
    url: 'https://www.gutenberg.org/ebooks/2701.epub3.images',
  },
  {
    title: 'Flatland (Audiobook, iOS)',
    format: 'audiobook',
    url: 'https://readium.org/webpub-manifest/examples/Flatland/manifest.json',
  },
  {
    title: 'PDF Sample (iOS)',
    format: 'pdf',
    url: 'https://www.w3.org/WAI/ER/tests/xhtml/testfiles/resources/pdf/dummy.pdf',
  },
];
