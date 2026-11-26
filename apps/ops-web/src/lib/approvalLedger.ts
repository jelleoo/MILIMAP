import {
  type BenefitDecision,
  type BenefitReleaseApprovalLedger,
  type BenefitReleaseApprovalRecord,
  type CoordinateDecision,
  type ReviewQueueItem,
} from '../types/ops';
import { extractSafeUrls, validateHttpUrlList } from './safeUrl';

export interface ApprovalDraft {
  benefitDecision: BenefitDecision;
  coordinateDecision: CoordinateDecision;
  verifiedSourceUrl: string;
  verifiedOn: string;
  approvedBy: string;
  approvedAt: string;
  rationale: string;
  locationObservationId: string;
}

const BUSINESS_ID_PATTERN = /^biz-[0-9a-f]{32}$/;
const TOKEN_PATTERN = /^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$/;
const CALENDAR_DATE_PATTERN = /^(\d{4})-(\d{2})-(\d{2})$/;
const ISO8601_WITH_OFFSET_PATTERN =
  /^(\d{4}-\d{2}-\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.(\d{1,9}))?(Z|([+-])(\d{2}):(\d{2}))$/;
const DISALLOWED_APPROVERS = new Set([
  'AUTO',
  'AUTOMATIC',
  'SYSTEM',
  'BOT',
  'UNKNOWN',
  'NONE',
  'N/A',
  'NULL',
  'ADMIN_BOT',
]);
const DISALLOWED_APPROVER_PREFIX = /^(AUTO|SYSTEM|BOT)[-_:\s]/;

export function isValidBusinessId(value: string): boolean {
  return BUSINESS_ID_PATTERN.test(value);
}

export function isValidHistoryToken(value: string): boolean {
  return Boolean(value) && TOKEN_PATTERN.test(value) && !value.includes('..');
}

export function isValidCalendarDate(value: string): boolean {
  if (!value || value !== value.trim()) return false;
  const match = CALENDAR_DATE_PATTERN.exec(value);
  if (!match) return false;
  const year = Number(match[1]);
  const month = Number(match[2]);
  const day = Number(match[3]);
  if (month < 1 || month > 12 || day < 1 || day > 31) return false;
  const probe = new Date(Date.UTC(year, month - 1, day));
  return (
    probe.getUTCFullYear() === year &&
    probe.getUTCMonth() === month - 1 &&
    probe.getUTCDate() === day
  );
}

export function isValidIso8601WithOffset(value: string): boolean {
  if (!value || value !== value.trim()) return false;
  const match = ISO8601_WITH_OFFSET_PATTERN.exec(value);
  if (!match) return false;
  if (!isValidCalendarDate(match[1])) return false;

  const hour = Number(match[2]);
  const minute = Number(match[3]);
  const second = Number(match[4]);
  if (hour < 0 || hour > 23 || minute < 0 || minute > 59 || second < 0 || second > 59) {
    return false;
  }

  if (match[6] !== 'Z') {
    const offHour = Number(match[8]);
    const offMin = Number(match[9]);
    if (offMin < 0 || offMin > 59 || offHour < 0 || offHour > 14 || (offHour === 14 && offMin !== 0)) {
      return false;
    }
  }
  return !Number.isNaN(Date.parse(value));
}

export function isValidHumanApprover(value: string): boolean {
  if (!value || value.trim().length === 0 || value !== value.trim()) {
    return false;
  }
  const upper = value.toUpperCase();
  if (DISALLOWED_APPROVERS.has(upper)) {
    return false;
  }
  if (DISALLOWED_APPROVER_PREFIX.test(upper)) {
    return false;
  }
  return true;
}

export function formatLocalIsoTimestampWithOffset(date: Date = new Date()): string {
  const pad = (n: number) => String(n).padStart(2, '0');
  const year = date.getFullYear();
  const month = pad(date.getMonth() + 1);
  const day = pad(date.getDate());
  const hour = pad(date.getHours());
  const minute = pad(date.getMinutes());
  const second = pad(date.getSeconds());
  const offsetMinutes = -date.getTimezoneOffset();
  if (offsetMinutes === 0) {
    return `${year}-${month}-${day}T${hour}:${minute}:${second}Z`;
  }
  const sign = offsetMinutes >= 0 ? '+' : '-';
  const abs = Math.abs(offsetMinutes);
  const offH = pad(Math.floor(abs / 60));
  const offM = pad(abs % 60);
  return `${year}-${month}-${day}T${hour}:${minute}:${second}${sign}${offH}:${offM}`;
}

export function formatLocalCalendarDate(date: Date = new Date()): string {
  const pad = (n: number) => String(n).padStart(2, '0');
  return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}`;
}

export function createDefaultApprovalDraft(
  item: ReviewQueueItem,
  existing?: BenefitReleaseApprovalRecord | null,
  defaultApprover: string = '',
): ApprovalDraft {
  if (existing) {
    return {
      benefitDecision: existing.benefitDecision,
      coordinateDecision: existing.coordinateDecision,
      verifiedSourceUrl: existing.verifiedSourceUrl,
      verifiedOn: existing.verifiedOn,
      approvedBy: existing.approvedBy,
      approvedAt: existing.approvedAt,
      rationale: existing.rationale,
      locationObservationId: existing.locationObservationId ?? '',
    };
  }

  const safeUrls = extractSafeUrls(item.CanonicalSourceUrl, item.SourceUrls);
  const canApproveActive = item.OperationalStatus === 'COMPLETE' && item.Comparable;
  const defaultDecision: BenefitDecision = !canApproveActive
    ? 'HOLD_NEEDS_VERIFICATION'
    : item.BenefitState === 'ENDED'
      ? 'HOLD_NEEDS_VERIFICATION'
      : item.OperatorBucket === 'FAST_REVIEW'
        ? 'APPROVE_ACTIVE'
        : 'HOLD_NEEDS_VERIFICATION';
  const canKeepPin = item.CanonicalCoordinateStatus === '확인 완료';

  return {
    benefitDecision: defaultDecision,
    coordinateDecision: canKeepPin ? 'KEEP_PIN' : 'SUPPRESS_PIN',
    verifiedSourceUrl: safeUrls.join(' | '),
    verifiedOn: formatLocalCalendarDate(),
    approvedBy: defaultApprover,
    approvedAt: formatLocalIsoTimestampWithOffset(),
    rationale: '',
    locationObservationId: '',
  };
}

export function validateApprovalDraft(item: ReviewQueueItem, draft: ApprovalDraft): string[] {
  const errors: string[] = [];

  if (item.Domain !== 'BENEFIT') {
    errors.push('LOCATION 단독 항목은 직접 승인 원장 레코드로 저장할 수 없으며, 동일 업소의 BENEFIT 레코드에 locationObservationId로 연결해야 합니다.');
    return errors;
  }
  if (!isValidBusinessId(item.BusinessId)) {
    errors.push('유효하지 않은 businessId 형식입니다.');
  }
  if (!isValidHistoryToken(item.ReviewKey) || !isValidHistoryToken(item.RunId) || !isValidHistoryToken(item.CurrentObservationId)) {
    errors.push('reviewKey / targetRunId / observationId 토큰이 유효하지 않습니다.');
  }
  if (draft.locationObservationId.trim().length > 0 && !isValidHistoryToken(draft.locationObservationId.trim())) {
    errors.push('locationObservationId 토큰 형식이 올바르지 않습니다.');
  }

  if (draft.benefitDecision === 'APPROVE_ACTIVE') {
    if (item.OperationalStatus !== 'COMPLETE' || !item.Comparable) {
      errors.push('OperationalStatus가 COMPLETE이고 Comparable=true인 항목만 APPROVE_ACTIVE 처리할 수 있습니다.');
    }
    if (item.ReviewClass !== 'GREEN' && draft.rationale.trim().length === 0) {
      errors.push('GREEN 등급이 아닌 항목을 APPROVE_ACTIVE로 승인하려면 판단 사유(rationale)를 반드시 입력해야 합니다.');
    }
  }

  if (draft.benefitDecision === 'APPROVE_ENDED') {
    if (draft.rationale.trim().length === 0) {
      errors.push('혜택 종료(APPROVE_ENDED) 확정 시 종료 근거(rationale)는 필수입니다.');
    }
    if (draft.coordinateDecision !== 'SUPPRESS_PIN') {
      errors.push('혜택 종료(APPROVE_ENDED) 확정 시 좌표 결정은 반드시 SUPPRESS_PIN이어야 합니다.');
    }
  }

  if (draft.coordinateDecision === 'KEEP_PIN' && item.CanonicalCoordinateStatus !== '확인 완료') {
    errors.push("정본 좌표검증상태가 '확인 완료'가 아니면 KEEP_PIN은 검증기(validate-benefit-release-approvals.ps1)에서 거부됩니다.");
  }

  if (!validateHttpUrlList(draft.verifiedSourceUrl)) {
    errors.push("확인 출처 URL(verifiedSourceUrl)은 http(s) 절대 URL이어야 합니다(복수 URL은 ' | '로 구분, 앞뒤 공백 불가).");
  }
  if (!isValidCalendarDate(draft.verifiedOn)) {
    errors.push('확인일(verifiedOn)은 실제 달력의 YYYY-MM-DD 형식이어야 합니다.');
  }
  if (!isValidHumanApprover(draft.approvedBy)) {
    errors.push('승인자(approvedBy)는 실제 사람 식별자여야 하며 AUTO/SYSTEM/BOT 등의 이름은 사용할 수 없습니다.');
  }
  if (!isValidIso8601WithOffset(draft.approvedAt)) {
    errors.push('승인 시각(approvedAt)은 시간대 오프셋(+09:00 또는 Z)이 포함된 ISO-8601 형식이어야 합니다.');
  }

  return errors;
}

export function buildApprovalRecord(item: ReviewQueueItem, draft: ApprovalDraft): BenefitReleaseApprovalRecord {
  const record: BenefitReleaseApprovalRecord = {
    businessId: item.BusinessId,
    reviewKey: item.ReviewKey,
    targetRunId: item.RunId,
    observationId: item.CurrentObservationId,
    benefitDecision: draft.benefitDecision,
    coordinateDecision: draft.benefitDecision === 'APPROVE_ENDED' ? 'SUPPRESS_PIN' : draft.coordinateDecision,
    verifiedSourceUrl: draft.verifiedSourceUrl.trim(),
    verifiedOn: draft.verifiedOn.trim(),
    approvedBy: draft.approvedBy.trim(),
    approvedAt: draft.approvedAt.trim(),
    rationale: draft.rationale,
  };

  if (typeof item.CanonicalRowNumber === 'number' && Number.isInteger(item.CanonicalRowNumber) && item.CanonicalRowNumber >= 2) {
    record.canonicalRowNumber = item.CanonicalRowNumber;
  }
  const locObs = draft.locationObservationId.trim();
  if (locObs.length > 0) {
    record.locationObservationId = locObs;
  }
  return record;
}

export function buildApprovalLedger(records: ReadonlyArray<BenefitReleaseApprovalRecord>): BenefitReleaseApprovalLedger {
  const seen = new Set<string>();
  const normalizedRecords: BenefitReleaseApprovalRecord[] = [];

  for (const raw of records) {
    if (seen.has(raw.businessId)) {
      throw new Error(`Duplicate businessId in ledger: ${raw.businessId}`);
    }
    seen.add(raw.businessId);

    const clean: BenefitReleaseApprovalRecord = {
      businessId: raw.businessId,
      reviewKey: raw.reviewKey,
      targetRunId: raw.targetRunId,
      observationId: raw.observationId,
      benefitDecision: raw.benefitDecision,
      coordinateDecision: raw.coordinateDecision,
      verifiedSourceUrl: raw.verifiedSourceUrl,
      verifiedOn: raw.verifiedOn,
      approvedBy: raw.approvedBy,
      approvedAt: raw.approvedAt,
      rationale: raw.rationale,
    };
    if (typeof raw.canonicalRowNumber === 'number' && Number.isInteger(raw.canonicalRowNumber) && raw.canonicalRowNumber >= 2) {
      clean.canonicalRowNumber = raw.canonicalRowNumber;
    }
    if (raw.locationObservationId && raw.locationObservationId.trim().length > 0) {
      clean.locationObservationId = raw.locationObservationId.trim();
    }
    normalizedRecords.push(clean);
  }

  return {
    ContractType: 'BenefitReleaseApprovalLedger',
    ContractVersion: 1,
    Records: normalizedRecords,
  };
}

export function buildValidateLedgerCommand(ledgerFilePath: string = 'C:/path/to/benefit-release-approval-ledger.json'): string {
  return [
    '& tools/data/validate-benefit-release-approvals.ps1 `',
    '  -HistoryRoot "C:/path/to/history-store" `',
    '  -CanonicalCsvPath "data/canonical/capital-area-military-benefits.csv" `',
    '  -CoordinateReviewCsvPath "data/canonical/reports/poi-coordinate-review-candidates-20261123-v14.csv" `',
    `  -ApprovalLedgerJsonPath "${ledgerFilePath}"`,
  ].join('\n');
}
