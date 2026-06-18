import { Fetcher, HttpFetcher, Link, Manifest } from '@readium/shared';
import {
  chapterManifestUrlFromSeries,
  firstComicChapterHref,
  isComicSeriesManifest,
} from './comicManifest';
import { normalizeManifest } from './manifestNormalizer';
import { normalizePublicationURL } from './publicationUtils';

/**
 * Fetches and deserializes the publication manifest
 */
export async function fetchManifest(publicationURL: string): Promise<{
  manifest: Manifest;
  fetcher: Fetcher;
  tableOfContentsManifest?: Manifest;
}> {
  const loaded = await fetchManifestFromPublicationURL(publicationURL);

  if (!isComicSeriesManifest(loaded.rawManifest)) {
    return loaded;
  }

  const firstChapterHref = firstComicChapterHref(loaded.rawManifest);
  const chapterManifestUrl = firstChapterHref
    ? chapterManifestUrlFromSeries(loaded.selfLink, firstChapterHref)
    : null;

  if (!chapterManifestUrl) {
    return loaded;
  }

  const chapter = await fetchManifestFromPublicationURL(
    normalizePublicationURL(chapterManifestUrl)
  );

  return {
    ...chapter,
    tableOfContentsManifest: loaded.manifest,
  };
}

async function fetchManifestFromPublicationURL(
  publicationURL: string
): Promise<{
  manifest: Manifest;
  fetcher: Fetcher;
  selfLink: string;
  rawManifest: any;
}> {
  const manifestLink = new Link({ href: 'manifest.json' });
  const fetcher: Fetcher = new HttpFetcher(undefined, publicationURL);
  const fetched = fetcher.get(manifestLink);
  const selfLink = (await fetched.link()).toURL(publicationURL)!;

  const response = await fetched.readAsJSON();
  const responseObj = normalizeManifest(response as any);

  let manifest;
  try {
    manifest = Manifest.deserialize(responseObj as string);
  } catch (error) {
    console.error('Error during manifest deserialization:', error);
    console.error('Manifest that failed:', responseObj);
    throw error;
  }

  if (!manifest) {
    console.error(
      'Failed to deserialize manifest (returned null/undefined):',
      responseObj
    );
    throw new Error('Manifest deserialization returned null/undefined');
  }

  manifest.setSelfLink(selfLink);
  return { manifest, fetcher, selfLink, rawManifest: responseObj };
}
