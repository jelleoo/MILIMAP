import { useMemo } from 'react';
import { ArrowLeft, CheckCircle2, ExternalLink, Search, ShieldAlert } from 'lucide-react';
import { BUCKET_META, formatCodeLabel, getItemReasonSummary, isNeedsHumanAttention } from '../lib/reasonLabels';
import { extractSafeUrls } from '../lib/safeUrl';
import type {
  BenefitReleaseApprovalRecord,
  CanonicalBacklog,
  ReviewDomain,
  ReviewQueueItem,
  WeeklyDriftNewCandidate,
  WeeklyDriftReviewItem,
} from '../types/ops';
import { ApprovalDrawer } from './ApprovalDrawer';
import { CanonicalBacklogPanel } from './CanonicalBacklogPanel';
import { DriftReviewPanel, type DriftCheckEntry } from './DriftReviewPanel';
import { NewCandidatesPanel } from './NewCandidatesPanel';
import type { QueueSourceTab, QueueTargetFilter } from './OverviewView';
import { Badge, Button, Card, Input, Select } from './ui/primitives';

interface ReviewQueueViewProps {
  queueSource: QueueSourceTab;
  onChangeQueueSource: (source: QueueSourceTab) => void;
  driftItems: WeeklyDriftReviewItem[];
  newCandidates: WeeklyDriftNewCandidate[];
  canonicalBacklog: CanonicalBacklog | null;
  checksById: Record<string, DriftCheckEntry>;
  onSaveCheck: (id: string, entry: DriftCheckEntry) => void;
  onClearCheck: (id: string) => void;
  items: ReviewQueueItem[];
  bucketFilter: QueueTargetFilter;
  onChangeBucketFilter: (filter: QueueTargetFilter) => void;
  recordsByBusinessId: Record<string, BenefitReleaseApprovalRecord>;
  defaultApprover: string;
  selectedKey: string | null;
  onSelectKey: (key: string) => void;
  onSaveRecord: (record: BenefitReleaseApprovalRecord, approverName: string) => void;
  onDeleteRecord: (businessId: string) => void;
  onAttachLocationObservation: (businessId: string, locationObservationId: string) => void;
  onBackOverview: () => void;
  domainFilter: 'ALL' | ReviewDomain;
  onChangeDomainFilter: (domain: 'ALL' | ReviewDomain) => void;
  draftStatusFilter: 'ALL' | 'PENDING' | 'DRAFTED';
  onChangeDraftStatusFilter: (status: 'ALL' | 'PENDING' | 'DRAFTED') => void;
  searchQuery: string;
  onChangeSearchQuery: (q: string) => void;
}

export function itemUniqueKey(item: ReviewQueueItem): string {
  return `${item.Domain}:${item.BusinessId}:${item.CurrentObservationId}`;
}

export function ReviewQueueView({
  queueSource,
  onChangeQueueSource,
  driftItems,
  newCandidates,
  canonicalBacklog,
  checksById,
  onSaveCheck,
  onClearCheck,
  items,
  bucketFilter,
  onChangeBucketFilter,
  recordsByBusinessId,
  defaultApprover,
  selectedKey,
  onSelectKey,
  onSaveRecord,
  onDeleteRecord,
  onAttachLocationObservation,
  onBackOverview,
  domainFilter,
  onChangeDomainFilter,
  draftStatusFilter,
  onChangeDraftStatusFilter,
  searchQuery,
  onChangeSearchQuery,
}: ReviewQueueViewProps) {
  const counts = useMemo(() => {
    let attention = 0;
    let domainReview = 0;
    let diagnosticHold = 0;
    let fastReview = 0;
    for (const it of items) {
      if (it.OperatorBucket === 'DOMAIN_REVIEW') {
        domainReview++;
        attention++;
      } else if (it.OperatorBucket === 'DIAGNOSTIC_HOLD') {
        diagnosticHold++;
        attention++;
      } else if (it.OperatorBucket === 'FAST_REVIEW') {
        fastReview++;
      }
    }
    return { total: items.length, attention, domainReview, diagnosticHold, fastReview };
  }, [items]);

  const filteredItems = useMemo(() => {
    const q = searchQuery.trim().toLowerCase();
    return items.filter((item) => {
      if (bucketFilter === 'ATTENTION' && !isNeedsHumanAttention(item.OperatorBucket)) return false;
      if (
        bucketFilter !== 'ALL' &&
        bucketFilter !== 'ATTENTION' &&
        item.OperatorBucket !== bucketFilter
      ) {
        return false;
      }
      if (domainFilter !== 'ALL' && item.Domain !== domainFilter) return false;
      const isDrafted = Boolean(recordsByBusinessId[item.BusinessId]);
      if (draftStatusFilter === 'PENDING' && isDrafted) return false;
      if (draftStatusFilter === 'DRAFTED' && !isDrafted) return false;

      if (q) {
        const hay = [
          item.BusinessName ?? '',
          item.District ?? '',
          item.RoadAddress ?? '',
          item.BusinessId,
          ...getItemReasonSummary(item),
        ]
          .join(' ')
          .toLowerCase();
        if (!hay.includes(q)) return false;
      }
      return true;
    });
  }, [items, bucketFilter, domainFilter, draftStatusFilter, searchQuery, recordsByBusinessId]);

  const selectedItem = useMemo(() => {
    if (filteredItems.length === 0) return null;
    if (selectedKey) {
      const match = filteredItems.find((it) => itemUniqueKey(it) === selectedKey);
      if (match) return match;
    }
    return filteredItems[0];
  }, [filteredItems, selectedKey]);

  const filterTabs: Array<{ id: QueueTargetFilter; label: string; count: number }> = [
    { id: 'ATTENTION', label: '직접 확인 필요', count: counts.attention },
    { id: 'DOMAIN_REVIEW', label: '내용 애매', count: counts.domainReview },
    { id: 'DIAGNOSTIC_HOLD', label: '수집·읽기 오류', count: counts.diagnosticHold },
    { id: 'FAST_REVIEW', label: '이상 없음', count: counts.fastReview },
    { id: 'ALL', label: '전체', count: counts.total },
  ];

  const sourceTabs: Array<{ id: QueueSourceTab; label: string; count: number; highlight?: boolean }> = [
    { id: 'drift', label: '변경·재확인 필요', count: driftItems.length, highlight: driftItems.length > 0 },
    { id: 'new-candidates', label: '신규 추가 후보', count: newCandidates.length },
    { id: 'backlog', label: '미배포·좌표 미확정', count: canonicalBacklog?.Summary.TotalBacklogCount ?? 0 },
    { id: 'phase5', label: '심층 검증·승인', count: counts.total },
  ];

  return (
    <div className="space-y-4">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <div className="flex flex-wrap items-center gap-2">
          <Button variant="outline" size="sm" onClick={onBackOverview}>
            <ArrowLeft className="h-3.5 w-3.5" />
            전체 현황으로 돌아가기
          </Button>
          <div className="inline-flex flex-wrap rounded-lg border border-slate-200 bg-white p-0.5">
            {sourceTabs.map((tab) => (
              <button
                key={tab.id}
                type="button"
                onClick={() => onChangeQueueSource(tab.id)}
                className={`inline-flex items-center gap-1.5 rounded-md px-3 py-1.5 text-xs font-medium transition cursor-pointer ${
                  queueSource === tab.id ? 'bg-slate-900 text-white' : 'text-slate-700 hover:bg-slate-100'
                }`}
              >
                <span>{tab.label}</span>
                <span
                  className={`tabular-nums rounded px-1.5 py-0.2 text-[11px] ${
                    queueSource === tab.id
                      ? 'bg-white/20 text-white'
                      : tab.highlight
                        ? 'bg-amber-100 text-amber-900'
                        : 'bg-slate-100 text-slate-700'
                  }`}
                >
                  {tab.count}
                </span>
              </button>
            ))}
          </div>
        </div>
      </div>

      {queueSource === 'drift' && (
        <DriftReviewPanel
          items={driftItems}
          checksById={checksById}
          onSaveCheck={onSaveCheck}
          onClearCheck={onClearCheck}
        />
      )}

      {queueSource === 'new-candidates' && (
        <NewCandidatesPanel
          items={newCandidates}
          checksById={checksById}
          onSaveCheck={onSaveCheck}
          onClearCheck={onClearCheck}
        />
      )}

      {queueSource === 'backlog' && (
        <CanonicalBacklogPanel
          summary={canonicalBacklog?.Summary ?? null}
          items={canonicalBacklog?.Items ?? []}
          checksById={checksById}
          onSaveCheck={onSaveCheck}
          onClearCheck={onClearCheck}
        />
      )}

      {queueSource === 'phase5' && (
        <>
          <div className="flex items-start gap-3 rounded-xl border border-amber-300 bg-amber-50 px-4 py-3.5 text-amber-950">
            <ShieldAlert className="mt-0.5 h-5 w-5 shrink-0 text-amber-800" />
            <div className="space-y-0.5">
              <div className="text-sm font-semibold">
                직접 확인이 필요합니다 — 심층 검증에서 확인이 필요한 항목을 승인 파일로 내보내는 화면입니다.
              </div>
              <p className="text-xs text-amber-900">
                각 항목의 <span className="font-semibold">공식 출처 직접 확인 ↗</span> 또는{' '}
                <span className="font-semibold">네이버 지도 확인 ↗</span> 링크로 실제 공고·영업 상태를 확인한 뒤, 오른쪽 패널에서 승인 내용을 작성해 주세요.
              </p>
            </div>
          </div>

          <Card className="p-3.5">
            <div className="flex flex-col gap-3 lg:flex-row lg:items-center lg:justify-between">
              <div className="flex flex-wrap gap-1.5">
                {filterTabs.map((tab) => (
                  <button
                    key={tab.id}
                    type="button"
                    onClick={() => onChangeBucketFilter(tab.id)}
                    className={`inline-flex items-center gap-1.5 rounded-lg px-3 py-1.5 text-xs font-medium transition cursor-pointer ${
                      bucketFilter === tab.id
                        ? 'bg-slate-900 text-white shadow-2xs'
                        : 'bg-slate-100 text-slate-700 hover:bg-slate-200'
                    }`}
                  >
                    <span>{tab.label}</span>
                    <span
                      className={`tabular-nums rounded px-1.5 py-0.2 text-[11px] ${
                        bucketFilter === tab.id ? 'bg-white/20 text-white' : 'bg-white text-slate-700'
                      }`}
                    >
                      {tab.count}
                    </span>
                  </button>
                ))}
              </div>

              <div className="flex flex-wrap items-center gap-2">
                <div className="relative min-w-[210px] flex-1">
                  <Search className="pointer-events-none absolute top-2.5 left-2.5 h-4 w-4 text-slate-400" />
                  <Input
                    className="pl-8"
                    placeholder="업소명, 시군구, 사유 검색..."
                    value={searchQuery}
                    onChange={(e) => onChangeSearchQuery(e.target.value)}
                  />
                </div>
                <Select
                  value={domainFilter}
                  onChange={(e) => onChangeDomainFilter(e.target.value as 'ALL' | ReviewDomain)}
                  aria-label="종류 필터"
                >
                  <option value="ALL">전체 종류</option>
                  <option value="BENEFIT">혜택 정보</option>
                  <option value="LOCATION">위치 좌표</option>
                </Select>
                <Select
                  value={draftStatusFilter}
                  onChange={(e) =>
                    onChangeDraftStatusFilter(e.target.value as 'ALL' | 'PENDING' | 'DRAFTED')
                  }
                  aria-label="작성 상태 필터"
                >
                  <option value="ALL">전체 상태</option>
                  <option value="PENDING">미작성</option>
                  <option value="DRAFTED">작성 완료</option>
                </Select>
              </div>
            </div>
          </Card>

          <div className="grid grid-cols-1 gap-4 xl:grid-cols-12">
            <div className="space-y-2.5 xl:col-span-5">
              {filteredItems.length === 0 ? (
                <Card className="p-8 text-center text-sm text-slate-500">
                  현재 조건에 해당하는 심층 검증 항목이 없습니다.
                </Card>
              ) : (
                filteredItems.map((item) => {
                  const key = itemUniqueKey(item);
                  const isSelected = selectedItem ? itemUniqueKey(selectedItem) === key : false;
                  const bucketMeta = BUCKET_META[item.OperatorBucket];
                  const reasons = getItemReasonSummary(item).slice(0, 3);
                  const firstSafeUrl = extractSafeUrls(item.CanonicalSourceUrl, item.SourceUrls)[0];
                  const drafted = recordsByBusinessId[item.BusinessId];

                  return (
                    <div
                      key={key}
                      onClick={() => onSelectKey(key)}
                      role="button"
                      tabIndex={0}
                      onKeyDown={(e) => {
                        if (e.key === 'Enter' || e.key === ' ') {
                          e.preventDefault();
                          onSelectKey(key);
                        }
                      }}
                      className={`rounded-xl border p-4 transition cursor-pointer ${
                        isSelected
                          ? 'border-slate-900 bg-white ring-2 ring-slate-900/10'
                          : 'border-slate-200 bg-white hover:border-slate-300'
                      }`}
                    >
                      <div className="flex flex-wrap items-center justify-between gap-1.5">
                        <div className="flex flex-wrap items-center gap-1.5">
                          <Badge tone={bucketMeta.tone}>{bucketMeta.shortLabel}</Badge>
                          <Badge tone="neutral">{item.Domain}</Badge>
                          {drafted && (
                            <Badge tone="emerald">
                              <CheckCircle2 className="h-3 w-3" />
                              {drafted.benefitDecision}
                            </Badge>
                          )}
                        </div>
                        {firstSafeUrl && (
                          <a
                            href={firstSafeUrl}
                            target="_blank"
                            rel="noopener noreferrer"
                            onClick={(e) => e.stopPropagation()}
                            className="inline-flex items-center gap-1 rounded-md border border-slate-200 bg-slate-50 px-2 py-0.5 text-[11px] font-medium text-slate-700 hover:bg-slate-100"
                          >
                            직접 확인
                            <ExternalLink className="h-3 w-3" />
                          </a>
                        )}
                      </div>

                      <div className="mt-2 font-semibold text-slate-900">
                        {item.BusinessName || '(업소명 미상)'}
                      </div>
                      <div className="mt-0.5 text-xs text-slate-500">
                        {[item.District, item.RoadAddress].filter(Boolean).join(' · ') || item.BusinessId}
                      </div>

                      {reasons.length > 0 && (
                        <div className="mt-2.5 flex flex-wrap gap-1">
                          {reasons.map((code) => (
                            <span
                              key={code}
                              className="rounded bg-slate-100 px-1.5 py-0.5 text-[11px] text-slate-700"
                            >
                              {formatCodeLabel(code)}
                            </span>
                          ))}
                        </div>
                      )}
                    </div>
                  );
                })
              )}
            </div>

            <div className="xl:col-span-7">
              <ApprovalDrawer
                item={selectedItem}
                existingRecord={selectedItem ? recordsByBusinessId[selectedItem.BusinessId] : undefined}
                defaultApprover={defaultApprover}
                relatedBenefitRecord={
                  selectedItem && selectedItem.Domain === 'LOCATION'
                    ? recordsByBusinessId[selectedItem.BusinessId]
                    : undefined
                }
                onSaveRecord={onSaveRecord}
                onDeleteRecord={onDeleteRecord}
                onAttachLocationObservation={onAttachLocationObservation}
              />
            </div>
          </div>
        </>
      )}
    </div>
  );
}
