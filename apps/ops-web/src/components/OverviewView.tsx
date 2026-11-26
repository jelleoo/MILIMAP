import {
  AlertTriangle,
  ArrowRight,
  CheckCircle2,
  Database,
  FileWarning,
  FlaskConical,
  Link2,
  Link2Off,
  MapPin,
  PlusCircle,
  RefreshCw,
  ShieldAlert,
  Upload,
} from 'lucide-react';
import type { BenefitReleaseApprovalRecord, OpsDashboardSnapshot } from '../types/ops';
import { Badge, Button, Card, CardContent, CardDescription, CardHeader, CardTitle } from './ui/primitives';

export type QueueTargetFilter = 'ATTENTION' | 'DOMAIN_REVIEW' | 'DIAGNOSTIC_HOLD' | 'FAST_REVIEW' | 'ALL';
export type QueueSourceTab = 'drift' | 'new-candidates' | 'backlog' | 'phase5';

interface OverviewViewProps {
  snapshot: OpsDashboardSnapshot;
  isDemo: boolean;
  recordsByBusinessId: Record<string, BenefitReleaseApprovalRecord>;
  localCheckedCount: number;
  onOpenQueue: (filter: QueueTargetFilter, source?: QueueSourceTab) => void;
  onTriggerUpload: () => void;
  onEnableDemo: () => void;
}

function sourceStatusBadge(status: string) {
  switch (status) {
    case 'OK':
      return <Badge tone="emerald">정상 확인</Badge>;
    case 'DRIFT_DETECTED':
      return <Badge tone="amber">새 변경 감지</Badge>;
    case 'FETCH_FAILED':
      return <Badge tone="red">접속 실패</Badge>;
    default:
      return <Badge tone="neutral">{status}</Badge>;
  }
}

export function OverviewView({
  snapshot,
  isDemo,
  recordsByBusinessId,
  localCheckedCount,
  onOpenQueue,
  onTriggerUpload,
  onEnableDemo,
}: OverviewViewProps) {
  const { SeedBaseline: seed, WeeklyDrift: drift, ReviewQueue: queue, CanonicalBacklog: backlog } = snapshot;
  const rawPinPct = seed.totalCount > 0 ? (seed.exactPinCount / seed.totalCount) * 100 : 0;
  const pinPct = rawPinPct.toFixed(1);
  const clampedPinPct = Math.min(100, Math.max(0, rawPinPct));

  const driftReviewCount = drift?.reviewItems?.length ?? 0;
  const newCandidateCount = drift?.newCandidates?.length ?? 0;
  const backlogCount = backlog?.Summary.TotalBacklogCount ?? 0;

  const domainReviewCount = queue?.Summary.DomainReviewCount ?? 0;
  const diagnosticHoldCount = queue?.Summary.DiagnosticHoldCount ?? 0;
  const fastReviewCount = queue?.Summary.FastReviewCount ?? 0;
  const phase5AttentionCount = domainReviewCount + diagnosticHoldCount;

  const totalActionableCount = driftReviewCount + backlogCount + phase5AttentionCount;
  const actionableReviewBusinessIds = new Set(
    (queue?.Items ?? [])
      .filter((item) => item.OperatorBucket === 'DOMAIN_REVIEW' || item.OperatorBucket === 'DIAGNOSTIC_HOLD')
      .map((item) => item.BusinessId),
  );
  const draftedCount = Object.keys(recordsByBusinessId).filter((id) =>
    actionableReviewBusinessIds.has(id),
  ).length;

  const driftSources = drift?.sources ?? [];
  const failedSourceCount = driftSources.filter((s) => s.status === 'FETCH_FAILED').length;
  const changedSourceCount = driftSources.filter((s) => s.status === 'DRIFT_DETECTED').length;
  const okSourceCount = driftSources.filter((s) => s.status === 'OK').length;

  const primaryQueueSource: QueueSourceTab =
    driftReviewCount > 0
      ? 'drift'
      : backlogCount > 0
        ? 'backlog'
        : phase5AttentionCount > 0
          ? 'phase5'
          : 'new-candidates';

  return (
    <div className="space-y-6">
      {isDemo && (
        <div className="flex flex-wrap items-center justify-between gap-3 rounded-xl border border-blue-200 bg-blue-50/80 px-4 py-3 text-sm text-blue-950">
          <div className="flex items-center gap-2.5">
            <FlaskConical className="h-4 w-4 shrink-0 text-blue-700" />
            <div>
              <span className="font-semibold">예시 화면 미리보기 모드</span>
              <span className="ml-2 text-xs text-blue-800">
                실제 운영 데이터가 아닌 이해를 돕기 위한 샘플입니다. 우측 상단에서 끌 수 있습니다.
              </span>
            </div>
          </div>
          <Button size="sm" variant="outline" onClick={onTriggerUpload}>
            <Upload className="h-3.5 w-3.5" />
            리포트 파일 올리기
          </Button>
        </div>
      )}

      {/* Intuitive Connection Status Buttons */}
      <Card className="p-4">
        <div className="flex flex-col gap-3 lg:flex-row lg:items-center lg:justify-between">
          <div>
            <div className="text-xs font-semibold text-slate-900">데이터 연결 상태</div>
            <div className="text-[11px] text-slate-500">
              초록색(연결됨) 버튼을 누르면 해당 데이터 목록으로 바로 이동하고, 미연결 버튼을 누르면 파일을 불러옵니다.
            </div>
          </div>
          <div className="flex flex-wrap gap-2">
            <span className="inline-flex items-center gap-1.5 rounded-lg border border-emerald-300 bg-emerald-50 px-3 py-1.5 text-xs font-medium text-emerald-900">
              <Link2 className="h-3.5 w-3.5 text-emerald-700" />
              앱 배포 데이터 · 연결됨 (v{seed.seedVersion} · {seed.totalCount.toLocaleString()}곳)
            </span>

            {drift ? (
              <button
                type="button"
                onClick={() => onOpenQueue('ATTENTION', driftReviewCount > 0 ? 'drift' : 'new-candidates')}
                className="inline-flex items-center gap-1.5 rounded-lg border border-emerald-300 bg-emerald-50 px-3 py-1.5 text-xs font-medium text-emerald-900 transition hover:bg-emerald-100 cursor-pointer"
              >
                <Link2 className="h-3.5 w-3.5 text-emerald-700" />
                공식 출처 자동 점검 · 연결됨 (확인 {driftReviewCount} · 신규 {newCandidateCount})
                <ArrowRight className="h-3 w-3" />
              </button>
            ) : (
              <button
                type="button"
                onClick={onTriggerUpload}
                className="inline-flex items-center gap-1.5 rounded-lg border border-amber-300 bg-amber-50 px-3 py-1.5 text-xs font-medium text-amber-900 transition hover:bg-amber-100 cursor-pointer"
              >
                <Link2Off className="h-3.5 w-3.5 text-amber-700" />
                공식 출처 자동 점검 · 미연결 (파일 올리기)
              </button>
            )}

            {backlog ? (
              <button
                type="button"
                onClick={() => onOpenQueue('ATTENTION', 'backlog')}
                className="inline-flex items-center gap-1.5 rounded-lg border border-emerald-300 bg-emerald-50 px-3 py-1.5 text-xs font-medium text-emerald-900 transition hover:bg-emerald-100 cursor-pointer"
              >
                <Link2 className="h-3.5 w-3.5 text-emerald-700" />
                미배포·좌표 미확정 · 연결됨 ({backlogCount}곳)
                <ArrowRight className="h-3 w-3" />
              </button>
            ) : (
              <span className="inline-flex items-center gap-1.5 rounded-lg border border-slate-200 bg-slate-50 px-3 py-1.5 text-xs font-medium text-slate-600">
                <Link2Off className="h-3.5 w-3.5 text-slate-400" />
                미배포·좌표 미확정 · 미포함
              </span>
            )}

            {queue ? (
              <button
                type="button"
                onClick={() => onOpenQueue('ATTENTION', 'phase5')}
                className="inline-flex items-center gap-1.5 rounded-lg border border-emerald-300 bg-emerald-50 px-3 py-1.5 text-xs font-medium text-emerald-900 transition hover:bg-emerald-100 cursor-pointer"
              >
                <Link2 className="h-3.5 w-3.5 text-emerald-700" />
                심층 검증 리포트 · 연결됨 ({queue.Summary.ExportedItemCount}건)
                <ArrowRight className="h-3 w-3" />
              </button>
            ) : (
              <button
                type="button"
                onClick={onTriggerUpload}
                className="inline-flex items-center gap-1.5 rounded-lg border border-slate-300 bg-slate-50 px-3 py-1.5 text-xs font-medium text-slate-700 transition hover:bg-slate-100 cursor-pointer"
              >
                <Link2Off className="h-3.5 w-3.5 text-slate-500" />
                심층 검증 리포트 · 미연결 (파일 올리기)
              </button>
            )}
          </div>
        </div>
      </Card>

      {/* Top Action / Attention Banner */}
      {totalActionableCount > 0 || newCandidateCount > 0 ? (
        <div className="flex flex-wrap items-center justify-between gap-4 rounded-xl border border-amber-300 bg-gradient-to-r from-amber-50 to-orange-50/70 px-5 py-4">
          <div className="flex items-start gap-3">
            <div className="mt-0.5 rounded-lg bg-amber-100 p-2 text-amber-800">
              <AlertTriangle className="h-5 w-5" />
            </div>
            <div>
              <div className="flex flex-wrap items-center gap-2">
                <h2 className="text-base font-semibold text-slate-900">
                  사람이 직접 확인해야 할 데이터가 {totalActionableCount.toLocaleString()}건 있습니다
                </h2>
                {driftReviewCount > 0 && <Badge tone="amber">변경·재확인 {driftReviewCount}건</Badge>}
                {backlogCount > 0 && <Badge tone="amber">미배포·좌표 미확정 {backlogCount}곳</Badge>}
                {newCandidateCount > 0 && <Badge tone="blue">신규 추가 후보 {newCandidateCount}곳</Badge>}
                {phase5AttentionCount > 0 && <Badge tone="red">심층 검증 보류 {phase5AttentionCount}건</Badge>}
              </div>
              <p className="mt-1 text-xs text-slate-700">
                자동 점검은 앱 데이터를 임의로 바꾸지 않습니다. 각 항목의 공식 사이트·네이버 지도 링크를 직접 확인하고 정리할 수 있습니다.
              </p>
            </div>
          </div>
          <div className="flex flex-wrap gap-2">
            {newCandidateCount > 0 && (
              <Button variant="outline" size="lg" onClick={() => onOpenQueue('ALL', 'new-candidates')}>
                <PlusCircle className="h-4 w-4 text-blue-700" />
                신규 후보 보기 ({newCandidateCount}곳)
              </Button>
            )}
            <Button variant="primary" size="lg" onClick={() => onOpenQueue('ATTENTION', primaryQueueSource)}>
              직접 확인 필요한 데이터 보기 ({totalActionableCount})
              <ArrowRight className="h-4 w-4" />
            </Button>
          </div>
        </div>
      ) : drift || queue || backlog ? (
        <div className="flex flex-wrap items-center justify-between gap-4 rounded-xl border border-emerald-200 bg-emerald-50/70 px-5 py-4">
          <div className="flex items-center gap-3">
            <CheckCircle2 className="h-5 w-5 text-emerald-700" />
            <div>
              <h2 className="text-sm font-semibold text-emerald-950">
                연결 완료 · 현재 직접 확인이 필요한 항목이 0건입니다
              </h2>
              <p className="text-xs text-emerald-800">
                {drift ? `공식 출처 최근 점검: ${drift.generatedAtUtc}` : '모든 연결된 데이터가 정상 상태입니다.'}
              </p>
            </div>
          </div>
          <Button variant="outline" onClick={() => onOpenQueue('ALL', 'drift')}>
            목록 열기
            <ArrowRight className="h-4 w-4" />
          </Button>
        </div>
      ) : (
        <Card className="border-dashed border-slate-300 bg-slate-50/60">
          <CardContent className="flex flex-col gap-4 py-6 lg:flex-row lg:items-center lg:justify-between">
            <div className="space-y-1.5">
              <div className="flex items-center gap-2">
                <Badge tone="neutral">기본 데이터만 로드됨</Badge>
                <span className="text-xs text-slate-500">생성 시각: {snapshot.GeneratedAtUtc || '-'}</span>
              </div>
              <h2 className="text-base font-semibold text-slate-900">
                아직 자동 점검 리포트가 연결되지 않았습니다
              </h2>
              <p className="text-xs text-slate-600">
                JSON 리포트 파일을 화면에 끌어다 놓거나, 예시 화면 보기로 동작을 먼저 확인해 보세요.
              </p>
            </div>
            <div className="flex shrink-0 flex-wrap gap-2">
              <Button variant="outline" onClick={onTriggerUpload}>
                <Upload className="h-4 w-4" />
                리포트 파일 올리기
              </Button>
              {!isDemo && (
                <Button variant="default" onClick={onEnableDemo}>
                  <FlaskConical className="h-4 w-4" />
                  예시 화면 보기
                </Button>
              )}
            </div>
          </CardContent>
        </Card>
      )}

      {/* KPI 4-Card Row */}
      <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 xl:grid-cols-4">
        <Card>
          <CardContent className="space-y-2">
            <div className="flex items-center justify-between text-xs font-medium text-slate-500">
              <span>현재 앱 배포 데이터</span>
              <Database className="h-4 w-4 text-slate-400" />
            </div>
            <div className="flex items-baseline gap-2">
              <span className="tabular-nums text-2xl font-bold text-slate-900">
                {seed.totalCount.toLocaleString()}곳
              </span>
              <Badge tone="blue">버전 v{seed.seedVersion}</Badge>
            </div>
            <p className="text-xs text-slate-500">
              정본 {backlog ? `${backlog.Summary.CanonicalTotalCount.toLocaleString()}곳 중` : ''} 실운영 반영 · {seed.generatedAt.slice(0, 10)}
            </p>
          </CardContent>
        </Card>

        <Card>
          <CardContent className="space-y-2">
            <div className="flex items-center justify-between text-xs font-medium text-slate-500">
              <span>지도 마커 표시 현황</span>
              <MapPin className="h-4 w-4 text-slate-400" />
            </div>
            <div className="flex items-baseline gap-2">
              <span className="tabular-nums text-2xl font-bold text-slate-900">
                {seed.exactPinCount.toLocaleString()}곳
              </span>
              <span className="tabular-nums text-xs font-semibold text-emerald-700">{pinPct}%</span>
            </div>
            <div className="h-1.5 w-full overflow-hidden rounded-full bg-slate-100">
              <div className="h-full rounded-full bg-emerald-600" style={{ width: `${clampedPinPct}%` }} />
            </div>
            <p className="text-xs text-slate-500">
              지도 핀 미확정: {seed.unconfirmedCoordinateCount.toLocaleString()}곳 · 배포 보류: {backlog?.Summary.HeldCount ?? 0}곳
            </p>
          </CardContent>
        </Card>

        <Card>
          <CardContent className="space-y-2">
            <div className="flex items-center justify-between text-xs font-medium text-slate-500">
              <span>공식 사이트 자동 점검</span>
              <RefreshCw className="h-4 w-4 text-slate-400" />
            </div>
            {drift ? (
              <>
                <div className="flex items-baseline gap-2">
                  <span className="tabular-nums text-2xl font-bold text-slate-900">
                    {okSourceCount} / {driftSources.length}곳
                  </span>
                  <span className="text-xs text-slate-500">정상 확인</span>
                </div>
                <div className="flex flex-wrap gap-1.5">
                  {changedSourceCount > 0 && <Badge tone="amber">변경 {changedSourceCount}</Badge>}
                  {failedSourceCount > 0 && <Badge tone="red">실패 {failedSourceCount}</Badge>}
                  {newCandidateCount > 0 && <Badge tone="blue">신규 후보 {newCandidateCount}</Badge>}
                </div>
              </>
            ) : (
              <>
                <div className="text-lg font-semibold text-slate-400">미연결</div>
                <p className="text-xs text-slate-500">자동 점검 파일이 연결되면 표시됩니다.</p>
              </>
            )}
          </CardContent>
        </Card>

        <Card>
          <CardContent className="space-y-2">
            <div className="flex items-center justify-between text-xs font-medium text-slate-500">
              <span>직접 확인 필요 합계</span>
              <ShieldAlert className="h-4 w-4 text-slate-400" />
            </div>
            <div className="flex items-baseline gap-2">
              <span className="tabular-nums text-2xl font-bold text-slate-900">
                {totalActionableCount.toLocaleString()}건
              </span>
              <Badge tone={localCheckedCount + draftedCount > 0 ? 'emerald' : 'neutral'}>
                확인 완료 {localCheckedCount + draftedCount}
              </Badge>
            </div>
            <p className="text-xs text-slate-500">
              변경·재확인 {driftReviewCount} · 백로그 {backlogCount} · 심층 {phase5AttentionCount}
            </p>
          </CardContent>
        </Card>
      </div>

      {/* Weekly Source Drift Table */}
      <Card>
        <CardHeader className="flex-row flex-wrap items-center justify-between gap-2">
          <div>
            <CardTitle>공식 사이트별 최신 점검 결과</CardTitle>
            <CardDescription>
              {drift
                ? `최근 자동 점검: ${drift.generatedAtUtc} · 전체 정본 ${drift.canonicalRowCount.toLocaleString()}건과 대조`
                : '공식 출처 자동 점검 리포트를 불러오면 병무청·동두천·파주·양주 결과가 표시됩니다.'}
            </CardDescription>
          </div>
          {drift && (
            <div className="flex flex-wrap gap-2">
              {newCandidateCount > 0 && (
                <Button size="sm" variant="outline" onClick={() => onOpenQueue('ALL', 'new-candidates')}>
                  신규 추가 후보 ({newCandidateCount}곳)
                  <ArrowRight className="h-3.5 w-3.5" />
                </Button>
              )}
              {driftReviewCount > 0 && (
                <Button size="sm" variant="primary" onClick={() => onOpenQueue('ATTENTION', 'drift')}>
                  변경·재확인 항목 보기 ({driftReviewCount}건)
                  <ArrowRight className="h-3.5 w-3.5" />
                </Button>
              )}
            </div>
          )}
        </CardHeader>
        <CardContent className="p-0">
          {drift && driftSources.length > 0 ? (
            <div className="overflow-x-auto">
              <table className="w-full text-left text-sm">
                <thead className="border-b border-slate-200 bg-slate-50/80 text-xs font-medium text-slate-500">
                  <tr>
                    <th className="px-5 py-3">공식 사이트</th>
                    <th className="px-4 py-3">점검 상태</th>
                    <th className="px-4 py-3 text-right">공식 목록 수</th>
                    <th className="px-4 py-3 text-right">정본 등록 수</th>
                    <th className="px-5 py-3">점검 상세 결과</th>
                  </tr>
                </thead>
                <tbody className="divide-y divide-slate-100">
                  {driftSources.map((src) => (
                    <tr key={src.id} className="hover:bg-slate-50/70">
                      <td className="px-5 py-3.5 font-medium text-slate-900">{src.name}</td>
                      <td className="px-4 py-3.5">{sourceStatusBadge(src.status)}</td>
                      <td className="tabular-nums px-4 py-3.5 text-right text-slate-700">
                        {src.officialCount !== null ? src.officialCount.toLocaleString() : '-'}
                      </td>
                      <td className="tabular-nums px-4 py-3.5 text-right text-slate-700">
                        {src.canonicalCount !== null ? src.canonicalCount.toLocaleString() : '-'}
                      </td>
                      <td className="px-5 py-3.5 text-xs text-slate-700">
                        <div>{src.detail}</div>
                        {src.error && (
                          <div className="mt-1 flex items-center gap-1 text-red-700">
                            <FileWarning className="h-3.5 w-3.5 shrink-0" />
                            <span>{src.error}</span>
                          </div>
                        )}
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          ) : (
            <div className="px-5 py-8 text-center text-xs text-slate-500">
              표시할 공식 출처 점검 결과가 없습니다.
            </div>
          )}
        </CardContent>
      </Card>

      {/* Canonical Backlog Breakdown */}
      {backlog && (
        <Card>
          <CardHeader className="flex-row flex-wrap items-center justify-between gap-2">
            <div>
              <CardTitle>정본 데이터 중 지도 미표시·보류 현황</CardTitle>
              <CardDescription>
                전체 정본 {backlog.Summary.CanonicalTotalCount.toLocaleString()}곳 중 아직 지도에 마커가 없거나 보강이 필요한 {backlogCount}곳입니다.
              </CardDescription>
            </div>
            <Button size="sm" variant="primary" onClick={() => onOpenQueue('ALL', 'backlog')}>
              미배포·좌표 미확정 전체 보기 ({backlogCount}곳)
              <ArrowRight className="h-3.5 w-3.5" />
            </Button>
          </CardHeader>
          <CardContent>
            <div className="grid grid-cols-1 gap-3 sm:grid-cols-2 xl:grid-cols-4">
              <div className="rounded-lg border border-amber-200 bg-amber-50/50 p-3.5">
                <div className="text-xs font-medium text-slate-600">앱 노출 중 · 지도 핀 미확정</div>
                <div className="mt-1 tabular-nums text-xl font-bold text-slate-900">
                  {backlog.Summary.UnpinnedInAppCount}곳
                </div>
                <div className="mt-1 text-[11px] text-slate-600">검색에는 나오지만 좌표가 비어 있음</div>
              </div>
              <div className="rounded-lg border border-amber-200 bg-amber-50/50 p-3.5">
                <div className="text-xs font-medium text-slate-600">공식 출처 · 좌표 재확인 필요</div>
                <div className="mt-1 tabular-nums text-xl font-bold text-slate-900">
                  {backlog.Summary.CoordRecheckCount}곳
                </div>
                <div className="mt-1 text-[11px] text-slate-600">좌표 검증 완료 후 앱에 추가 가능</div>
              </div>
              <div className="rounded-lg border border-amber-200 bg-amber-50/50 p-3.5">
                <div className="text-xs font-medium text-slate-600">공고 재확인 · OCR 보류</div>
                <div className="mt-1 tabular-nums text-xl font-bold text-slate-900">
                  {backlog.Summary.OutdatedOrOcrCount}곳
                </div>
                <div className="mt-1 text-[11px] text-slate-600">수원 스캔 PDF 등 직접 확인 필요</div>
              </div>
              <div className="rounded-lg border border-red-200 bg-red-50/40 p-3.5">
                <div className="text-xs font-medium text-slate-600">비공식 출처 (SNS·후기)</div>
                <div className="mt-1 tabular-nums text-xl font-bold text-slate-900">
                  {backlog.Summary.UnofficialSourceCount}곳
                </div>
                <div className="mt-1 text-[11px] text-slate-600">공식 출처 확보 전까지 배포 보류</div>
              </div>
            </div>
          </CardContent>
        </Card>
      )}

      {/* Phase 5 Bucket Cards */}
      <Card>
        <CardHeader className="flex-row flex-wrap items-center justify-between gap-2">
          <div>
            <CardTitle>심층 검증 결과 (승인 파일 생성용)</CardTitle>
            <CardDescription>
              {queue
                ? '각 카드를 누르면 해당 분류로 필터링된 심층 검증·승인 화면으로 이동합니다.'
                : '로컬 심층 검증 파일(review-queue-summary.json)을 올리면 세부 건수가 표시됩니다.'}
            </CardDescription>
          </div>
          {queue ? (
            <Button size="sm" variant="outline" onClick={() => onOpenQueue('ALL', 'phase5')}>
              전체 보기 ({queue.Summary.ExportedItemCount})
              <ArrowRight className="h-3.5 w-3.5" />
            </Button>
          ) : (
            <Button size="sm" variant="outline" onClick={onTriggerUpload}>
              <Upload className="h-3.5 w-3.5" />
              심층 검증 파일 올리기
            </Button>
          )}
        </CardHeader>
        <CardContent>
          <div className="grid grid-cols-1 gap-4 md:grid-cols-3">
            <div className="flex flex-col justify-between rounded-xl border border-amber-200 bg-amber-50/50 p-4">
              <div>
                <div className="flex items-center justify-between">
                  <Badge tone="amber">직접 확인 필요</Badge>
                  <span className="tabular-nums text-2xl font-bold text-amber-950">{domainReviewCount}</span>
                </div>
                <h4 className="mt-2.5 text-sm font-semibold text-slate-900">내용 애매 · 사람 판단 필요</h4>
                <p className="mt-1 text-xs leading-relaxed text-slate-600">
                  공식 출처와 정본 혜택 내용 불일치, 목록 미관측 등으로 사람이 원문을 확인해야 합니다.
                </p>
              </div>
              <Button
                className="mt-4 w-full justify-between"
                variant="primary"
                size="sm"
                disabled={!queue}
                onClick={() => onOpenQueue('DOMAIN_REVIEW', 'phase5')}
              >
                애매한 데이터 확인하기
                <ArrowRight className="h-3.5 w-3.5" />
              </Button>
            </div>

            <div className="flex flex-col justify-between rounded-xl border border-red-200 bg-red-50/40 p-4">
              <div>
                <div className="flex items-center justify-between">
                  <Badge tone="red">수집·읽기 오류</Badge>
                  <span className="tabular-nums text-2xl font-bold text-red-900">{diagnosticHoldCount}</span>
                </div>
                <h4 className="mt-2.5 text-sm font-semibold text-slate-900">자동 읽기 보류 (진단 필요)</h4>
                <p className="mt-1 text-xs leading-relaxed text-slate-600">
                  사이트 접속 실패, 표 파싱 실패, 스캔 PDF OCR 보류 등으로 자동 비교가 멈춘 항목입니다.
                </p>
              </div>
              <Button
                className="mt-4 w-full justify-between"
                variant="outline"
                size="sm"
                disabled={!queue}
                onClick={() => onOpenQueue('DIAGNOSTIC_HOLD', 'phase5')}
              >
                오류·보류 항목 보기
                <ArrowRight className="h-3.5 w-3.5" />
              </Button>
            </div>

            <div className="flex flex-col justify-between rounded-xl border border-emerald-200 bg-emerald-50/40 p-4">
              <div>
                <div className="flex items-center justify-between">
                  <Badge tone="emerald">이상 없음 (빠른 승인)</Badge>
                  <span className="tabular-nums text-2xl font-bold text-emerald-950">{fastReviewCount}</span>
                </div>
                <h4 className="mt-2.5 text-sm font-semibold text-slate-900">공식 출처와 일치</h4>
                <p className="mt-1 text-xs leading-relaxed text-slate-600">
                  공식 출처와 정본이 같아 최종 승인만 거치면 바로 반영할 수 있는 항목입니다.
                </p>
              </div>
              <Button
                className="mt-4 w-full justify-between"
                variant="outline"
                size="sm"
                disabled={!queue}
                onClick={() => onOpenQueue('FAST_REVIEW', 'phase5')}
              >
                이상 없는 목록 보기
                <ArrowRight className="h-3.5 w-3.5" />
              </Button>
            </div>
          </div>
        </CardContent>
      </Card>
    </div>
  );
}
