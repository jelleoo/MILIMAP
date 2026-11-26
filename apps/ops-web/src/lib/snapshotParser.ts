import type {
  BenefitReleaseApprovalLedger,
  OpsDashboardSnapshot,
  Phase5ReviewQueueExport,
  WeeklyBenefitDriftSummary,
} from '../types/ops';

export type ParsedUploadedJson =
  | { kind: 'snapshot'; data: OpsDashboardSnapshot }
  | { kind: 'review-queue'; data: Phase5ReviewQueueExport }
  | { kind: 'weekly-drift'; data: WeeklyBenefitDriftSummary }
  | { kind: 'approval-ledger'; data: BenefitReleaseApprovalLedger };

function isPlainObject(value: unknown): value is Record<string, unknown> {
  return Boolean(value) && typeof value === 'object' && !Array.isArray(value);
}

function isFiniteNumber(value: unknown): value is number {
  return typeof value === 'number' && Number.isFinite(value);
}

function isNonEmptyString(value: unknown): value is string {
  return typeof value === 'string' && value.trim().length > 0;
}

function validateSeedBaseline(baseline: unknown): boolean {
  if (!isPlainObject(baseline)) return false;
  return (
    isFiniteNumber(baseline.seedVersion) &&
    isFiniteNumber(baseline.totalCount) &&
    isFiniteNumber(baseline.exactPinCount) &&
    isFiniteNumber(baseline.unconfirmedCoordinateCount) &&
    typeof baseline.generatedAt === 'string'
  );
}

function validateReviewQueueBody(obj: Record<string, unknown>): void {
  if (!isPlainObject(obj.Summary) || !Array.isArray(obj.Items)) {
    throw new Error('지원하지 않는 Phase5ReviewQueueExport 구조입니다.');
  }
  const sum = obj.Summary;
  if (
    !isFiniteNumber(sum.ExportedItemCount) ||
    !isFiniteNumber(sum.FastReviewCount) ||
    !isFiniteNumber(sum.DomainReviewCount) ||
    !isFiniteNumber(sum.DiagnosticHoldCount)
  ) {
    throw new Error('Phase5ReviewQueueExport Summary 카운트가 올바르지 않습니다.');
  }
  for (const item of obj.Items) {
    if (!isPlainObject(item) || typeof item.BusinessId !== 'string') {
      throw new Error('Phase5ReviewQueueExport Items 항목에 유효한 BusinessId가 없습니다.');
    }
  }
}

function validateWeeklyDriftBody(obj: Record<string, unknown>): void {
  if (!Array.isArray(obj.sources)) {
    throw new Error('지원하지 않는 WeeklyBenefitDriftSummary 구조입니다.');
  }
  for (const src of obj.sources) {
    if (!isPlainObject(src)) {
      throw new Error('WeeklyBenefitDriftSummary sources 항목이 객체가 아닙니다.');
    }
  }
  if (obj.reviewItems !== undefined && obj.reviewItems !== null && !Array.isArray(obj.reviewItems)) {
    throw new Error('WeeklyBenefitDriftSummary reviewItems는 배열이어야 합니다.');
  }
  if (obj.newCandidates !== undefined && obj.newCandidates !== null && !Array.isArray(obj.newCandidates)) {
    throw new Error('WeeklyBenefitDriftSummary newCandidates는 배열이어야 합니다.');
  }
}

export function parseUploadedOpsJson(rawText: string): ParsedUploadedJson {
  let parsed: unknown;
  try {
    parsed = JSON.parse(rawText.replace(/^\uFEFF/, ''));
  } catch {
    throw new Error('올바른 JSON 파일이 아닙니다. 문법 오류를 확인해 주세요.');
  }

  if (!isPlainObject(parsed)) {
    throw new Error('최상위 JSON 값이 객체가 아닙니다.');
  }

  const obj = parsed;

  if (obj.ContractType === 'OpsDashboardSnapshot') {
    if (obj.ContractVersion !== 1 || !validateSeedBaseline(obj.SeedBaseline)) {
      throw new Error('지원하지 않는 OpsDashboardSnapshot 버전 또는 SeedBaseline 누락/오류입니다.');
    }
    if (obj.WeeklyDrift !== undefined && obj.WeeklyDrift !== null) {
      if (!isPlainObject(obj.WeeklyDrift)) {
        throw new Error('OpsDashboardSnapshot WeeklyDrift 구조가 올바르지 않습니다.');
      }
      validateWeeklyDriftBody(obj.WeeklyDrift);
    }
    if (obj.ReviewQueue !== undefined && obj.ReviewQueue !== null) {
      if (!isPlainObject(obj.ReviewQueue)) {
        throw new Error('OpsDashboardSnapshot ReviewQueue 구조가 올바르지 않습니다.');
      }
      validateReviewQueueBody(obj.ReviewQueue);
    }
    if (obj.CanonicalBacklog !== undefined && obj.CanonicalBacklog !== null) {
      if (
        !isPlainObject(obj.CanonicalBacklog) ||
        !isPlainObject(obj.CanonicalBacklog.Summary) ||
        !Array.isArray(obj.CanonicalBacklog.Items)
      ) {
        throw new Error('OpsDashboardSnapshot CanonicalBacklog 구조가 올바르지 않습니다.');
      }
    }
    return { kind: 'snapshot', data: obj as unknown as OpsDashboardSnapshot };
  }

  if (obj.ContractType === 'Phase5ReviewQueueExport') {
    if (obj.ContractVersion !== 1) {
      throw new Error('지원하지 않는 Phase5ReviewQueueExport 버전입니다.');
    }
    validateReviewQueueBody(obj);
    return { kind: 'review-queue', data: obj as unknown as Phase5ReviewQueueExport };
  }

  if (obj.contractType === 'WeeklyBenefitDriftSummary') {
    if (obj.contractVersion !== 1) {
      throw new Error('지원하지 않는 WeeklyBenefitDriftSummary 버전입니다.');
    }
    validateWeeklyDriftBody(obj);
    return { kind: 'weekly-drift', data: obj as unknown as WeeklyBenefitDriftSummary };
  }

  if (obj.ContractType === 'BenefitReleaseApprovalLedger') {
    if (obj.ContractVersion !== 1 || !Array.isArray(obj.Records)) {
      throw new Error('지원하지 않는 BenefitReleaseApprovalLedger 구조입니다.');
    }
    const seenIds = new Set<string>();
    for (const record of obj.Records) {
      if (!isPlainObject(record) || !isNonEmptyString(record.businessId)) {
        throw new Error('BenefitReleaseApprovalLedger Records 항목에 유효한 businessId가 없습니다.');
      }
      if (seenIds.has(record.businessId)) {
        throw new Error(`BenefitReleaseApprovalLedger 중복 businessId가 존재합니다: ${record.businessId}`);
      }
      seenIds.add(record.businessId);
    }
    return { kind: 'approval-ledger', data: obj as unknown as BenefitReleaseApprovalLedger };
  }

  throw new Error(
    '지원하지 않는 JSON 형식입니다. (OpsDashboardSnapshot, Phase5ReviewQueueExport, WeeklyBenefitDriftSummary, BenefitReleaseApprovalLedger만 지원)',
  );
}
