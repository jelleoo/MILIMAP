import { describe, expect, it } from 'vitest';
import { parseUploadedOpsJson } from '../snapshotParser';

describe('snapshotParser', () => {
  it('parses OpsDashboardSnapshot, Phase5ReviewQueueExport, WeeklyBenefitDriftSummary, and Ledger', () => {
    const snap = parseUploadedOpsJson(
      JSON.stringify({
        ContractType: 'OpsDashboardSnapshot',
        ContractVersion: 1,
        GeneratedAtUtc: '2026-11-26T00:00:00Z',
        ProductionAction: 'NONE',
        SeedBaseline: { totalCount: 1018 },
        WeeklyDrift: null,
        ReviewQueue: null,
        CanonicalBacklog: {
          Summary: {
            CanonicalTotalCount: 1137,
            SeedActiveCount: 1018,
            ExactPinCount: 998,
            UnpinnedInAppCount: 20,
            HeldCount: 119,
            CoordRecheckCount: 55,
            OutdatedOrOcrCount: 38,
            UnofficialSourceCount: 26,
            TotalBacklogCount: 139,
          },
          Items: [],
        },
      }),
    );
    expect(snap.kind).toBe('snapshot');
    if (snap.kind === 'snapshot') {
      expect(snap.data.CanonicalBacklog?.Summary.TotalBacklogCount).toBe(139);
    }

    const rq = parseUploadedOpsJson(
      JSON.stringify({
        ContractType: 'Phase5ReviewQueueExport',
        ContractVersion: 1,
        ExportedAt: '2026-11-26T00:00:00Z',
        Summary: { ExportedItemCount: 0 },
        Items: [],
      }),
    );
    expect(rq.kind).toBe('review-queue');

    const drift = parseUploadedOpsJson(
      JSON.stringify({
        contractType: 'WeeklyBenefitDriftSummary',
        contractVersion: 1,
        generatedAtUtc: '2026-11-26T00:00:00Z',
        canonicalRowCount: 1137,
        automaticCanonicalMutation: false,
        sources: [],
        reviewItems: [
          {
            id: 'drift-mma-changed-1',
            sourceId: 'mma',
            sourceName: '병무청 나라사랑가게',
            category: 'CONTENT_CHANGED',
            categoryLabel: '내용 변경',
            severity: 'amber',
            businessName: '테스트',
            reasonSummary: 'DISCOUNT',
            sourceUrls: ['https://www.mma.go.kr/about/udgg/list.do?mc=mma0003357'],
          },
        ],
      }),
    );
    expect(drift.kind).toBe('weekly-drift');
    if (drift.kind === 'weekly-drift') {
      expect(drift.data.reviewItems).toHaveLength(1);
    }

    const ledger = parseUploadedOpsJson(
      JSON.stringify({
        ContractType: 'BenefitReleaseApprovalLedger',
        ContractVersion: 1,
        Records: [],
      }),
    );
    expect(ledger.kind).toBe('approval-ledger');
  });

  it('strips UTF-8 BOM and rejects unsupported JSON contracts', () => {
    const withBom =
      '\uFEFF' +
      JSON.stringify({
        ContractType: 'BenefitReleaseApprovalLedger',
        ContractVersion: 1,
        Records: [],
      });
    expect(parseUploadedOpsJson(withBom).kind).toBe('approval-ledger');
    expect(() => parseUploadedOpsJson('{"ContractType":"Unknown"}')).toThrow(/지원하지 않는 JSON/);
    expect(() => parseUploadedOpsJson('{broken')).toThrow(/올바른 JSON/);
  });
});
