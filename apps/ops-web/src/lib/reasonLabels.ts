import type { OperatorBucket, ReviewQueueItem } from '../types/ops';

export interface BucketMeta {
  label: string;
  shortLabel: string;
  description: string;
  tone: 'amber' | 'red' | 'emerald';
}

export const BUCKET_META: Record<OperatorBucket, BucketMeta> = {
  DOMAIN_REVIEW: {
    label: '직접 확인 필요 (내용 애매)',
    shortLabel: '직접 확인 필요',
    description: '공식 출처와 정본 내용이 다르거나 목록에서 미관측되어 사람이 원문을 확인해야 합니다.',
    tone: 'amber',
  },
  DIAGNOSTIC_HOLD: {
    label: '진단 보류 (수집/파싱 오류)',
    shortLabel: '진단 보류',
    description: '수집 실패, 비교 불가, 파싱/OCR 보류 등으로 자동 검증이 완결되지 않은 항목입니다.',
    tone: 'red',
  },
  FAST_REVIEW: {
    label: '빠른 승인 후보 (자동 통과)',
    shortLabel: '빠른 검토',
    description: '공식 출처와 정본이 일치해 신속하게 확인·승인할 수 있는 항목입니다.',
    tone: 'emerald',
  },
};

const CODE_LABELS: Record<string, string> = {
  CLAIM_MISMATCH: '공식 출처와 혜택/정보 불일치',
  BENEFIT_DESCRIPTION_CHANGED: '할인 내용 변경 의심',
  BUSINESS_NOT_FOUND_IN_SOURCE: '최신 공식 목록에서 미관측',
  ENDED_CANDIDATE: '혜택 종료 후보',
  COORDINATE_RECHECK_REQUIRED: '좌표 재확인 필요',
  OCR_DEFERRED: '스캔 PDF OCR 보류 (수동 전사 필요)',
  NON_COMPARABLE_OBSERVATION: '비교 불가 관측',
  CANONICAL_ROW_MISSING: '정본 CSV 행 매칭 실패',
  SEMANTIC_PROJECTION_UNAVAILABLE: '의미 프로젝션 누락',
  HTML_TABLE_MISMATCH: 'HTML 표 구조 불일치',
  FETCH_FAILED: '공식 출처 조회 실패',
  PARTIAL: '부분 성공(비교 보류)',
  FAILED: '수집·파싱 실패',
};

export function formatCodeLabel(code: string): string {
  return CODE_LABELS[code] ?? code;
}

export function getItemReasonSummary(item: ReviewQueueItem): string[] {
  const raw = [
    ...(item.DiagnosticReasons ?? []),
    ...(item.ReasonCodes ?? []),
    ...(item.MaterialReasonCodes ?? []),
    ...(item.ConflictCodes ?? []),
    ...(item.ChangeCandidates ?? []),
  ];
  const unique: string[] = [];
  const seen = new Set<string>();
  for (const code of raw) {
    const trimmed = code.trim();
    if (trimmed && !seen.has(trimmed)) {
      seen.add(trimmed);
      unique.push(trimmed);
    }
  }
  return unique;
}

export function isNeedsHumanAttention(bucket: OperatorBucket): boolean {
  return bucket === 'DOMAIN_REVIEW' || bucket === 'DIAGNOSTIC_HOLD';
}
