import { describe, expect, it } from 'vitest';
import {
  buildApprovalLedger,
  buildApprovalRecord,
  isValidCalendarDate,
  isValidHumanApprover,
  isValidIso8601WithOffset,
  validateApprovalDraft,
  type ApprovalDraft,
} from '../approvalLedger';
import type { ReviewQueueItem } from '../../types/ops';

function sampleItem(overrides: Partial<ReviewQueueItem> = {}): ReviewQueueItem {
  return {
    OperatorBucket: 'DOMAIN_REVIEW',
    BusinessId: 'biz-0123456789abcdef0123456789abcdef',
    CanonicalRowNumber: 12,
    BusinessName: '테스트식당',
    District: '동두천시',
    RoadAddress: '경기도 동두천시 테스트로 1',
    CanonicalBenefitStatus: '이용 가능',
    CanonicalCoordinateStatus: '확인 완료',
    CanonicalSourceUrl: 'https://www.ddc.go.kr/ddc/contents.do?key=1570',
    Domain: 'BENEFIT',
    ReviewKey: 'cmp-1',
    RunId: 'run-1',
    CurrentObservationId: 'obs-1',
    ReviewRoute: 'HUMAN_DOMAIN_REVIEW',
    OperationalStatus: 'COMPLETE',
    Comparable: true,
    ReviewClass: 'YELLOW',
    BenefitState: 'NEEDS_VERIFICATION',
    ProductionAction: 'NONE',
    ...overrides,
  };
}

function validDraft(overrides: Partial<ApprovalDraft> = {}): ApprovalDraft {
  return {
    benefitDecision: 'APPROVE_ACTIVE',
    coordinateDecision: 'KEEP_PIN',
    verifiedSourceUrl: 'https://www.ddc.go.kr/ddc/contents.do?key=1570',
    verifiedOn: '2026-11-26',
    approvedBy: 'dev-kim',
    approvedAt: '2026-11-26T13:15:00+09:00',
    rationale: '공식 테이블 확인 완료',
    locationObservationId: '',
    ...overrides,
  };
}

describe('approvalLedger', () => {
  it('validates real calendar dates, offsets, and human approvers', () => {
    expect(isValidCalendarDate('2026-02-28')).toBe(true);
    expect(isValidCalendarDate('2026-02-30')).toBe(false);
    expect(isValidIso8601WithOffset('2026-11-26T13:15:00+09:00')).toBe(true);
    expect(isValidIso8601WithOffset('2026-11-26T13:15:00Z')).toBe(true);
    expect(isValidIso8601WithOffset('2026-11-26T13:15:00')).toBe(false);

    expect(isValidHumanApprover('dev-kim')).toBe(true);
    expect(isValidHumanApprover('AUTO')).toBe(false);
    expect(isValidHumanApprover('BOT_runner')).toBe(false);
    expect(isValidHumanApprover('ADMIN_BOT')).toBe(false);
  });

  it('enforces ApproveActive, ApproveEnded, KeepPin, and Rationale rules', () => {
    const partialItem = sampleItem({ OperationalStatus: 'PARTIAL', Comparable: false });
    expect(validateApprovalDraft(partialItem, validDraft())).toEqual(
      expect.arrayContaining([expect.stringContaining('APPROVE_ACTIVE')]),
    );

    const yellowItem = sampleItem({ ReviewClass: 'YELLOW' });
    expect(validateApprovalDraft(yellowItem, validDraft({ rationale: '   ' }))).toEqual(
      expect.arrayContaining([expect.stringContaining('판단 사유')]),
    );

    expect(
      validateApprovalDraft(
        sampleItem(),
        validDraft({ benefitDecision: 'APPROVE_ENDED', coordinateDecision: 'KEEP_PIN', rationale: '' }),
      ).length,
    ).toBeGreaterThanOrEqual(2);

    const unconfirmedCoordItem = sampleItem({ CanonicalCoordinateStatus: '재확인 필요' });
    expect(validateApprovalDraft(unconfirmedCoordItem, validDraft({ coordinateDecision: 'KEEP_PIN' }))).toEqual(
      expect.arrayContaining([expect.stringContaining('KEEP_PIN')]),
    );
  });

  it('serializes strict contract-compatible records without optional blank fields', () => {
    const item = sampleItem({ CanonicalRowNumber: null });
    const record = buildApprovalRecord(item, validDraft({ locationObservationId: '' }));
    expect(Object.prototype.hasOwnProperty.call(record, 'canonicalRowNumber')).toBe(false);
    expect(Object.prototype.hasOwnProperty.call(record, 'locationObservationId')).toBe(false);

    const ledger = buildApprovalLedger([record]);
    expect(ledger.ContractType).toBe('BenefitReleaseApprovalLedger');
    expect(ledger.ContractVersion).toBe(1);
    expect(ledger.Records).toHaveLength(1);
    expect(() => buildApprovalLedger([record, record])).toThrow(/Duplicate businessId/);
  });
});
