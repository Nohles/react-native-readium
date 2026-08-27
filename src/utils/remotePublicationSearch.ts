import type {
  Locator,
  PublicationSearchPage,
} from '../specs/ReadiumView.nitro';

const LOCATOR_COLLECTION_MEDIA_TYPE = 'application/vnd.readium.locators+json';

type RemoteSearchPage = PublicationSearchPage & { nextHref?: string };

const isRecord = (value: unknown): value is Record<string, unknown> =>
  typeof value === 'object' && value !== null;

const isLocator = (value: unknown): value is Locator =>
  isRecord(value) &&
  typeof value.href === 'string' &&
  typeof value.type === 'string';

export function expandSearchHref(
  searchHref: string,
  manifestHref: string,
  query: string
) {
  const expanded = searchHref.includes('{?query}')
    ? searchHref.replace('{?query}', `?query=${encodeURIComponent(query)}`)
    : searchHref;
  const url = new URL(expanded, manifestHref);
  if (!searchHref.includes('{?query}')) {
    url.searchParams.set('query', query);
  }
  return url.toString();
}

export async function fetchRemoteSearchPage({
  href,
  query,
  signal,
}: {
  href: string;
  query: string;
  signal?: AbortSignal;
}): Promise<RemoteSearchPage> {
  const response = await fetch(href, {
    signal,
    credentials: 'include',
    headers: { Accept: LOCATOR_COLLECTION_MEDIA_TYPE },
  });
  if (!response.ok) {
    throw new Error(`Search failed with status ${response.status}.`);
  }

  const json: unknown = await response.json();
  if (!isRecord(json) || !Array.isArray(json.locators)) {
    throw new Error('The publication returned an invalid search response.');
  }
  const locators = json.locators.filter(isLocator);
  if (locators.length !== json.locators.length) {
    throw new Error('The publication returned an invalid search locator.');
  }

  const metadata = isRecord(json.metadata) ? json.metadata : undefined;
  const total =
    typeof metadata?.numberOfItems === 'number'
      ? metadata.numberOfItems
      : undefined;
  const links = Array.isArray(json.links) ? json.links : [];
  const next = links.find((link) => {
    if (!isRecord(link)) return false;
    const rel = link.rel;
    return rel === 'next' || (Array.isArray(rel) && rel.includes('next'));
  });
  const nextHref =
    isRecord(next) && typeof next.href === 'string'
      ? new URL(next.href, href).toString()
      : undefined;

  return {
    query,
    locators,
    total,
    hasNext: Boolean(nextHref),
    nextHref,
  };
}
