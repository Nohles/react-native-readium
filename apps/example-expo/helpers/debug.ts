type DebugDetails = Record<string, unknown> | unknown;

function debug(scope: string, message: string, details?: DebugDetails) {
  if (details === undefined) {
    console.log(`[${scope}] ${message}`);
  } else {
    console.log(`[${scope}] ${message}`, details);
  }
}

export function audiobookDebug(message: string, details?: DebugDetails) {
  debug('AudiobookDebug', message, details);
}

export function publicationDebug(message: string, details?: DebugDetails) {
  debug('PublicationDebug', message, details);
}

export function publicationNetworkHints(url: string) {
  const cleartext = url.startsWith('http://');
  return {
    url,
    cleartext,
    atsNote: cleartext
      ? 'This HTTP URL requires local-network/cleartext access in the native app.'
      : 'This HTTPS URL must be reachable from the device.',
  };
}
