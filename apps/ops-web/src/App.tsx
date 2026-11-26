import { useEffect, useMemo, useRef, useState } from 'react';
import {
  Activity,
  ClipboardCheck,
  Download,
  FlaskConical,
  ShieldCheck,
  Upload,
} from 'lucide-react';
import { LedgerExportModal } from './components/LedgerExportModal';
import { OverviewView, type QueueTargetFilter } from './components/OverviewView';
import { ReviewQueueView, itemUniqueKey } from './components/ReviewQueueView';
import { Badge, Button } from './components/ui/primitives';
import { createDemoSnapshot } from './lib/demoSnapshot';
import { parseUploadedOpsJson } from './lib/snapshotParser';
import type {
  BenefitReleaseApprovalRecord,
  OpsDashboardSnapshot,
  ReviewDomain,
} from './types/ops';

type ActiveTab = 'overview' | 'review-queue';

const STORAGE_RECORDS_KEY = 'milimap_ops_approval_records_v1';
const STORAGE_APPROVER_KEY = 'milimap_ops_approver_v1';

const FALLBACK_MANIFEST = {
  manifestVersion: 1,
  seedName: 'benefits',
  seedVersion: 14,
  hashAlgorithm: 'SHA-256-LF-UTF8',
  generatedAt: '2026-11-23T11:22:09Z',
  canonicalCsvSha256: '',
  totalCount: 1018,
  exactPinCount: 998,
  unconfirmedCoordinateCount: 20,
  seedSha256: '',
  manualSeedCount: 0,
  manualSeedSha256: '',
};

export function App() {
  const fileInputRef = useRef<HTMLInputElement | null>(null);
  const [activeTab, setActiveTab] = useState<ActiveTab>('overview');
  const [bucketFilter, setBucketFilter] = useState<QueueTargetFilter>('ATTENTION');
  const [domainFilter, setDomainFilter] = useState<'ALL' | ReviewDomain>('ALL');
  const [draftStatusFilter, setDraftStatusFilter] = useState<'ALL' | 'PENDING' | 'DRAFTED'>('ALL');
  const [searchQuery, setSearchQuery] = useState('');
  const [selectedKey, setSelectedKey] = useState<string | null>(null);

  const [snapshot, setSnapshot] = useState<OpsDashboardSnapshot>({
    ContractType: 'OpsDashboardSnapshot',
    ContractVersion: 1,
    GeneratedAtUtc: '',
    ProductionAction: 'NONE',
    SeedBaseline: FALLBACK_MANIFEST,
    WeeklyDrift: null,
    ReviewQueue: null,
  });
  const [isDemo, setIsDemo] = useState(false);
  const [uploadNotice, setUploadNotice] = useState<{ tone: 'info' | 'error'; text: string } | null>(null);
  const [isDragOver, setIsDragOver] = useState(false);
  const [exportModalOpen, setExportModalOpen] = useState(false);

  const [recordsByBusinessId, setRecordsByBusinessId] = useState<Record<string, BenefitReleaseApprovalRecord>>(() => {
    try {
      const raw = localStorage.getItem(STORAGE_RECORDS_KEY);
      return raw ? (JSON.parse(raw) as Record<string, BenefitReleaseApprovalRecord>) : {};
    } catch {
      return {};
    }
  });
  const [defaultApprover, setDefaultApprover] = useState<string>(() => {
    try {
      return localStorage.getItem(STORAGE_APPROVER_KEY) ?? '';
    } catch {
      return '';
    }
  });

  useEffect(() => {
    let active = true;
    fetch('/ops-snapshot.json')
      .then(async (resp) => {
        if (!resp.ok) throw new Error(`HTTP ${resp.status}`);
        return (await resp.json()) as OpsDashboardSnapshot;
      })
      .then((loaded) => {
        if (active && loaded?.ContractType === 'OpsDashboardSnapshot') {
          setSnapshot(loaded);
        }
      })
      .catch(() => {
        // Fallback baseline already initialized cleanly.
      });
    return () => {
      active = false;
    };
  }, []);

  useEffect(() => {
    try {
      localStorage.setItem(STORAGE_RECORDS_KEY, JSON.stringify(recordsByBusinessId));
    } catch {
      // Ignore storage quota errors in restricted browsing modes.
    }
  }, [recordsByBusinessId]);

  useEffect(() => {
    try {
      localStorage.setItem(STORAGE_APPROVER_KEY, defaultApprover);
    } catch {
      // Ignore storage errors.
    }
  }, [defaultApprover]);

  const displayedSnapshot = useMemo(
    () => (isDemo ? createDemoSnapshot(snapshot.SeedBaseline) : snapshot),
    [isDemo, snapshot],
  );

  const reviewItems = displayedSnapshot.ReviewQueue?.Items ?? [];
  const attentionCount =
    (displayedSnapshot.ReviewQueue?.Summary.DomainReviewCount ?? 0) +
    (displayedSnapshot.ReviewQueue?.Summary.DiagnosticHoldCount ?? 0);
  const draftedRecords = useMemo(() => Object.values(recordsByBusinessId), [recordsByBusinessId]);

  const handleOpenQueue = (filter: QueueTargetFilter) => {
    setBucketFilter(filter);
    setSelectedKey(null);
    setActiveTab('review-queue');
  };

  const handleFiles = async (files: FileList | null) => {
    if (!files || files.length === 0) return;
    try {
      let messages: string[] = [];
      for (const file of Array.from(files)) {
        const text = await file.text();
        const parsed = parseUploadedOpsJson(text);
        if (parsed.kind === 'snapshot') {
          setSnapshot(parsed.data);
          setIsDemo(false);
          messages.push(`스냅샷(${file.name})을 불러왔습니다.`);
        } else if (parsed.kind === 'review-queue') {
          setSnapshot((prev) => ({ ...prev, ReviewQueue: parsed.data }));
          setIsDemo(false);
          messages.push(`리뷰 큐(${parsed.data.Summary.ExportedItemCount}건)를 불러왔습니다.`);
        } else if (parsed.kind === 'weekly-drift') {
          setSnapshot((prev) => ({ ...prev, WeeklyDrift: parsed.data }));
          setIsDemo(false);
          messages.push(`주간 출처 점검(${parsed.data.sources.length}개 출처)을 불러왔습니다.`);
        } else if (parsed.kind === 'approval-ledger') {
          const nextMap: Record<string, BenefitReleaseApprovalRecord> = {};
          for (const rec of parsed.data.Records) {
            nextMap[rec.businessId] = rec;
          }
          setRecordsByBusinessId(nextMap);
          messages.push(`기존 승인 원장(${parsed.data.Records.length}건)을 불러왔습니다.`);
        }
      }
      setUploadNotice({ tone: 'info', text: messages.join(' ') });
    } catch (err) {
      setUploadNotice({
        tone: 'error',
        text: err instanceof Error ? err.message : '파일을 해석할 수 없습니다.',
      });
    } finally {
      if (fileInputRef.current) fileInputRef.current.value = '';
    }
  };

  const handleSaveRecord = (record: BenefitReleaseApprovalRecord, approverName: string) => {
    setRecordsByBusinessId((prev) => ({ ...prev, [record.businessId]: record }));
    if (approverName) setDefaultApprover(approverName);
  };

  const handleDeleteRecord = (businessId: string) => {
    setRecordsByBusinessId((prev) => {
      const next = { ...prev };
      delete next[businessId];
      return next;
    });
  };

  const handleAttachLocationObservation = (businessId: string, locationObservationId: string) => {
    setRecordsByBusinessId((prev) => {
      const target = prev[businessId];
      if (!target) return prev;
      return {
        ...prev,
        [businessId]: {
          ...target,
          locationObservationId,
        },
      };
    });
  };

  return (
    <div
      className="min-h-screen bg-slate-50 text-slate-900"
      onDragOver={(e) => {
        e.preventDefault();
        setIsDragOver(true);
      }}
      onDragLeave={() => setIsDragOver(false)}
      onDrop={(e) => {
        e.preventDefault();
        setIsDragOver(false);
        void handleFiles(e.dataTransfer.files);
      }}
    >
      {isDragOver && (
        <div className="pointer-events-none fixed inset-0 z-50 flex items-center justify-center border-4 border-dashed border-amber-500 bg-slate-900/35 backdrop-blur-[1px]">
          <div className="rounded-xl bg-white px-6 py-4 text-sm font-semibold text-slate-900 shadow-lg">
            여기에 JSON 리포트 파일을 놓으면 대시보드에 바로 반영됩니다
          </div>
        </div>
      )}

      <input
        ref={fileInputRef}
        type="file"
        accept=".json,application/json"
        multiple
        className="hidden"
        onChange={(e) => void handleFiles(e.target.files)}
      />

      <div className="flex min-h-screen flex-col lg:flex-row">
        {/* Left Navigation Sidebar */}
        <aside className="w-full shrink-0 border-b border-slate-200 bg-white lg:w-64 lg:border-r lg:border-b-0">
          <div className="flex h-full flex-col justify-between p-4">
            <div className="space-y-5">
              <div className="space-y-2 border-b border-slate-100 pb-4">
                <div className="flex items-center justify-between">
                  <span className="text-sm font-bold tracking-tight text-slate-900">MILIMAP Ops</span>
                  <Badge tone="dark">DEV ONLY</Badge>
                </div>
                <p className="text-xs text-slate-500">내부 데이터 자동화 · 수동 확인 관제</p>
                <div className="inline-flex items-center gap-1 rounded border border-slate-200 bg-slate-50 px-2 py-0.5 font-mono text-[10px] text-slate-600">
                  <ShieldCheck className="h-3 w-3 text-emerald-700" />
                  ProductionAction: {displayedSnapshot.ProductionAction}
                </div>
              </div>

              <nav className="space-y-1">
                <button
                  type="button"
                  onClick={() => setActiveTab('overview')}
                  className={`flex w-full items-center justify-between rounded-lg px-3 py-2 text-sm font-medium transition cursor-pointer ${
                    activeTab === 'overview'
                      ? 'bg-slate-900 text-white'
                      : 'text-slate-700 hover:bg-slate-100'
                  }`}
                >
                  <span className="flex items-center gap-2">
                    <Activity className="h-4 w-4" />
                    자동화 현황
                  </span>
                </button>

                <button
                  type="button"
                  onClick={() => handleOpenQueue(attentionCount > 0 ? 'ATTENTION' : 'ALL')}
                  className={`flex w-full items-center justify-between rounded-lg px-3 py-2 text-sm font-medium transition cursor-pointer ${
                    activeTab === 'review-queue'
                      ? 'bg-slate-900 text-white'
                      : 'text-slate-700 hover:bg-slate-100'
                  }`}
                >
                  <span className="flex items-center gap-2">
                    <ClipboardCheck className="h-4 w-4" />
                    직접 확인 대기열
                  </span>
                  {attentionCount > 0 && (
                    <span
                      className={`tabular-nums rounded-md px-1.5 py-0.5 text-xs font-semibold ${
                        activeTab === 'review-queue'
                          ? 'bg-amber-500 text-white'
                          : 'bg-amber-100 text-amber-900'
                      }`}
                    >
                      {attentionCount}
                    </span>
                  )}
                </button>
              </nav>
            </div>

            <div className="mt-6 space-y-2 border-t border-slate-100 pt-4 text-[11px] text-slate-500">
              <div>실운영 시드: v{displayedSnapshot.SeedBaseline.seedVersion} ({displayedSnapshot.SeedBaseline.totalCount.toLocaleString()}건)</div>
              <div>자동 정본 변경: 차단 (사람 승인 필수)</div>
            </div>
          </div>
        </aside>

        {/* Main Workspace */}
        <div className="flex min-w-0 flex-1 flex-col">
          <header className="sticky top-0 z-20 flex flex-wrap items-center justify-between gap-3 border-b border-slate-200 bg-white/95 px-6 py-3 backdrop-blur-xs">
            <div>
              <h1 className="text-base font-semibold text-slate-900">
                {activeTab === 'overview' ? '데이터 자동화 파이프라인 현황' : '애매한 데이터 · 직접 확인 대기열'}
              </h1>
              <p className="text-xs text-slate-500">
                {isDemo
                  ? 'DEMO 샘플 데이터 미리보기 중'
                  : displayedSnapshot.ReviewQueue || displayedSnapshot.WeeklyDrift
                    ? '로드된 파이프라인 리포트 기준'
                    : '기본 번들 시드 기준선 (리포트 JSON을 끌어다 놓아 확장)'}
              </p>
            </div>

            <div className="flex flex-wrap items-center gap-2">
              <Button
                variant={isDemo ? 'primary' : 'outline'}
                size="sm"
                onClick={() => setIsDemo((prev) => !prev)}
              >
                <FlaskConical className="h-3.5 w-3.5" />
                {isDemo ? '샘플 미리보기 끄기' : '샘플 미리보기'}
              </Button>
              <Button variant="outline" size="sm" onClick={() => fileInputRef.current?.click()}>
                <Upload className="h-3.5 w-3.5" />
                JSON 불러오기
              </Button>
              <Button size="sm" onClick={() => setExportModalOpen(true)}>
                <Download className="h-3.5 w-3.5" />
                승인 원장 내보내기 ({draftedRecords.length})
              </Button>
            </div>
          </header>

          <main className="flex-1 p-6">
            {uploadNotice && (
              <div
                className={`mb-4 flex items-center justify-between rounded-lg border px-4 py-2.5 text-xs ${
                  uploadNotice.tone === 'error'
                    ? 'border-red-300 bg-red-50 text-red-800'
                    : 'border-blue-200 bg-blue-50 text-blue-900'
                }`}
              >
                <span>{uploadNotice.text}</span>
                <button
                  type="button"
                  className="ml-4 font-medium underline cursor-pointer"
                  onClick={() => setUploadNotice(null)}
                >
                  닫기
                </button>
              </div>
            )}

            {activeTab === 'overview' ? (
              <OverviewView
                snapshot={displayedSnapshot}
                isDemo={isDemo}
                recordsByBusinessId={recordsByBusinessId}
                onOpenQueue={handleOpenQueue}
                onTriggerUpload={() => fileInputRef.current?.click()}
                onEnableDemo={() => setIsDemo(true)}
              />
            ) : (
              <ReviewQueueView
                items={reviewItems}
                bucketFilter={bucketFilter}
                onChangeBucketFilter={(next) => {
                  setBucketFilter(next);
                  setSelectedKey(null);
                }}
                recordsByBusinessId={recordsByBusinessId}
                defaultApprover={defaultApprover}
                selectedKey={selectedKey ?? (reviewItems[0] ? itemUniqueKey(reviewItems[0]) : null)}
                onSelectKey={setSelectedKey}
                onSaveRecord={handleSaveRecord}
                onDeleteRecord={handleDeleteRecord}
                onAttachLocationObservation={handleAttachLocationObservation}
                onBackOverview={() => setActiveTab('overview')}
                domainFilter={domainFilter}
                onChangeDomainFilter={setDomainFilter}
                draftStatusFilter={draftStatusFilter}
                onChangeDraftStatusFilter={setDraftStatusFilter}
                searchQuery={searchQuery}
                onChangeSearchQuery={setSearchQuery}
              />
            )}
          </main>
        </div>
      </div>

      <LedgerExportModal
        open={exportModalOpen}
        records={draftedRecords}
        onClose={() => setExportModalOpen(false)}
        onClearAll={() => setRecordsByBusinessId({})}
      />
    </div>
  );
}

export default App;
