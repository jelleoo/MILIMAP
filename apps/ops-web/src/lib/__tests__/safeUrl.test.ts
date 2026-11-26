import { describe, expect, it } from 'vitest';
import { buildNaverMapSearchUrl, extractSafeUrls, sanitizeHttpUrl, validateHttpUrlList } from '../safeUrl';

describe('safeUrl', () => {
  it('allows http and https urls while rejecting unsafe schemes and userinfo', () => {
    expect(sanitizeHttpUrl('https://www.ddc.go.kr/ddc/contents.do?key=1570')).toBe(
      'https://www.ddc.go.kr/ddc/contents.do?key=1570',
    );
    expect(sanitizeHttpUrl('http://open.mma.go.kr/test')).toBe('http://open.mma.go.kr/test');
    expect(sanitizeHttpUrl('javascript:alert(1)')).toBeNull();
    expect(sanitizeHttpUrl('data:text/html,<script>alert(1)</script>')).toBeNull();
    expect(sanitizeHttpUrl('file:///etc/passwd')).toBeNull();
    expect(sanitizeHttpUrl('https://user:pass@example.com/path')).toBeNull();
    expect(sanitizeHttpUrl('https://example.com/foo bar')).toBeNull();
    expect(sanitizeHttpUrl('https://example.com/a\nb')).toBeNull();
    expect(sanitizeHttpUrl('https://example.com/a|https://example.com/b')).toBeNull();
  });

  it('deduplicates pipe-separated canonical and source urls safely', () => {
    const urls = extractSafeUrls(
      'https://www.ddc.go.kr/a | javascript:evil() | https://www.paju.go.kr/b',
      ['https://www.ddc.go.kr/a', 'https://www.yangju.go.kr/c|https://www.mma.go.kr/d'],
    );
    expect(urls).toEqual([
      'https://www.ddc.go.kr/a',
      'https://www.paju.go.kr/b',
      'https://www.yangju.go.kr/c',
      'https://www.mma.go.kr/d',
    ]);
  });

  it('matches PowerShell Test-ReleaseHttpUrlList pipe delimiter contract', () => {
    expect(validateHttpUrlList('https://www.ddc.go.kr/a | https://www.paju.go.kr/b')).toBe(true);
    expect(validateHttpUrlList('https://a.com|https://b.com')).toBe(false);
    expect(validateHttpUrlList(' https://www.ddc.go.kr/a')).toBe(false);
    expect(validateHttpUrlList('https://www.ddc.go.kr/a | ')).toBe(false);
    expect(validateHttpUrlList('ftp://example.com/file')).toBe(false);
  });

  it('builds encoded Naver Map search url', () => {
    expect(buildNaverMapSearchUrl('나라사랑 한식당', '경기도 동두천시 평화로 123')).toBe(
      'https://map.naver.com/p/search/%EB%82%98%EB%9D%BC%EC%82%AC%EB%9E%91%20%ED%95%9C%EC%8B%9D%EB%8B%B9%20%EA%B2%BD%EA%B8%B0%EB%8F%84%20%EB%8F%99%EB%91%90%EC%B2%9C%EC%8B%9C%20%ED%8F%89%ED%99%94%EB%A1%9C%20123',
    );
  });
});
