type ManifestLink = { href?: string; title?: string };
type WebPubManifest = {
  metadata?: { title?: string };
  readingOrder?: ManifestLink[];
};

export function isWebPubManifestUrl(url: string): boolean {
  return /^https?:\/\//i.test(url) && /\/manifest\.json(?:[?#].*)?$/i.test(url);
}

export async function probeWebPubManifest(url: string): Promise<
  | {
      ok: true;
      status: number;
      title?: string;
      readingOrderCount: number;
      firstReadingOrderHref?: string;
      manifest: WebPubManifest;
    }
  | { ok: false; status: number; bodyPreview: string }
> {
  try {
    const response = await fetch(url);
    const body = await response.text();
    if (!response.ok) {
      return {
        ok: false,
        status: response.status,
        bodyPreview: body.slice(0, 160),
      };
    }

    const manifest = JSON.parse(body) as WebPubManifest;
    return {
      ok: true,
      status: response.status,
      title: manifest.metadata?.title,
      readingOrderCount: manifest.readingOrder?.length ?? 0,
      firstReadingOrderHref: manifest.readingOrder?.[0]?.href,
      manifest,
    };
  } catch (error) {
    return { ok: false, status: 0, bodyPreview: String(error) };
  }
}
