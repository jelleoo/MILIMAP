export function sanitizeHttpUrl(raw: string | null | undefined): string | null {
  if (!raw) return null;
  const trimmed = raw.trim();
  if (!trimmed || /[\s\u0000-\u001F\u007F|]/.test(trimmed)) return null;
  try {
    const parsed = new URL(trimmed);
    if (parsed.protocol !== 'http:' && parsed.protocol !== 'https:') {
      return null;
    }
    if (!parsed.hostname || parsed.username || parsed.password) {
      return null;
    }
    return parsed.toString();
  } catch {
    return null;
  }
}

export function extractSafeUrls(
  canonicalUrl?: string | null,
  sourceUrls?: ReadonlyArray<string | null | undefined> | null,
): string[] {
  const seen = new Set<string>();
  const candidates: string[] = [];

  if (canonicalUrl) {
    for (const part of canonicalUrl.split(/\s*\|\s*/)) {
      candidates.push(part);
    }
  }
  if (sourceUrls) {
    for (const url of sourceUrls) {
      if (url) {
        for (const part of url.split(/\s*\|\s*/)) {
          candidates.push(part);
        }
      }
    }
  }

  const result: string[] = [];
  for (const candidate of candidates) {
    const safe = sanitizeHttpUrl(candidate);
    if (safe && !seen.has(safe)) {
      seen.add(safe);
      result.push(safe);
    }
  }
  return result;
}

export function validateHttpUrlList(value: string): boolean {
  if (!value || value.trim().length === 0 || value !== value.trim()) {
    return false;
  }
  const parts = value.split(' | ');
  if (parts.length < 1) return false;
  for (const part of parts) {
    if (!part || part.trim().length === 0 || part !== part.trim()) {
      return false;
    }
    if (!sanitizeHttpUrl(part)) {
      return false;
    }
  }
  return true;
}

export function buildNaverMapSearchUrl(
  businessName?: string | null,
  roadAddress?: string | null,
  district?: string | null,
): string {
  const query = [businessName, roadAddress || district]
    .map((part) => (part ?? '').trim())
    .filter(Boolean)
    .join(' ');
  const fallback = query || '수도권';
  return `https://map.naver.com/p/search/${encodeURIComponent(fallback)}`;
}
