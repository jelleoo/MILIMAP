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

export function parseUploadedOpsJson(rawText: string): ParsedUploadedJson {
  let parsed: unknown;
  try {
    parsed = JSON.parse(rawText.replace(/^\uFEFF/, ''));
  } catch {
    throw new Error('올바른 JSON 파일이 아닙니다. 문법 오류를 확인해 주세요.');
  }

  if (!parsed || typeof parsed !== 'object' || Array.isArray(parsed)) {
    throw new Error('최상위 JSON 값이 객체가 아닙니다.');
  }

  const obj = parsed as Record<string, unknown>;

  if (obj.ContractType === 'OpsDashboardSnapshot') {
    if (obj.ContractVersion !== 1 || !obj.SeedBaseline || typeof obj.SeedBaseline !== 'object') {
      throw new Error('지원하지 않는 OpsDashboardSnapshot 버전 또는 SeedBaseline 누락입니다.');
    }
    return { kind: 'snapshot', data: obj as unknown as OpsDashboardSnapshot };
  }

  if (obj.ContractType === 'Phase5ReviewQueueExport') {
    if (obj.ContractVersion !== 1 || !obj.Summary || !Array.isArray(obj.Items)) {
      throw new Error('지원하지 않는 Phase5ReviewQueueExport 구조입니다.');
    }
    return { kind: 'review-queue', data: obj as unknown as Phase5ReviewQueueExport };
  }

  if (obj.contractType === 'WeeklyBenefitDriftSummary') {
    if (obj.contractVersion !== 1 || !Array.isArray(obj.sources)) {
      throw new Error('지원하지 않는 WeeklyBenefitDriftSummary 구조입니다.');
    }
    return { kind: 'weekly-drift', data: obj as unknown as WeeklyBenefitDriftSummary };
  }

  if (obj.ContractType === 'BenefitReleaseApprovalLedger') {
    if (obj.ContractVersion !== 1 || !Array.isArray(obj.Records)) {
      throw new Error('지원하지 않는 BenefitReleaseApprovalLedger 구조입니다.');
    }
    return { kind: 'approval-ledger', data: obj as unknown as BenefitReleaseApprovalLedger };
  }

  throw new Error(
    '지원하지 않는 JSON 형식입니다. (OpsDashboardSnapshot, Phase5ReviewQueueExport, WeeklyBenefitDriftSummary, BenefitReleaseApprovalLedger만 지원)',
  );
}
