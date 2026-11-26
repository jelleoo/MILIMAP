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
  RefreshCw,
  ShieldAlert,
  Upload,
} from 'lucide-react';
import type { BenefitReleaseApprovalRecord, OpsDashboardSnapshot } from '../types/ops';
import { Badge, Button, Card, CardContent, CardDescription, CardHeader, CardTitle } from './ui/primitives';

export type QueueTargetFilter = 'ATTENTION' | 'DOMAIN_REVIEW' | 'DIAGNOSTIC_HOLD' | 'FAST_REVIEW' | 'ALL';
export type QueueSourceTab = 'drift' | 'phase5';

interface OverviewViewProps {
  snapshot: OpsDashboardSnapshot;
  isDemo: boolean;
  recordsByBusinessId: Record<string, BenefitReleaseApprovalRecord>;
  driftCheckedCount: number;
  onOpenQueue: (filter: QueueTargetFilter, source?: QueueSourceTab) => void;
  onTriggerUpload: () => void;
  onEnableDemo: () => void;
}

function sourceStatusBadge(status: string) {
  switch (status) {
    case 'OK':
      return <Badge tone="emerald">정상 수집 (OK)</Badge>;
    case 'DRIFT_DETECTED':
      return <Badge tone="amber">변경 감지 (DRIFT)</Badge>;
    case 'FETCH_FAILED':
      return <Badge tone="red">수집 실패 (FAILED)</Badge>;
    default:
      return <Badge tone="neutral">{status}</Badge>;
  }
}

export function OverviewView({
  snapshot,
  isDemo,
  recordsByBusinessId,
  driftCheckedCount,
  onOpenQueue,
  onTriggerUpload,
  onEnableDemo,
}: OverviewViewProps) {
  const { SeedBaseline: seed, WeeklyDrift: drift, ReviewQueue: queue } = snapshot;
  const pinPct = seed.totalCount > 0 ? ((seed.exactPinCount / seed.totalCount) * 100).toFixed(1) : '0.0';

  const driftReviewItems = drift?.reviewItems ?? [];
  const driftReviewCount = driftReviewItems.length;

  const domainReviewCount = queue?.Summary.DomainReviewCount ?? 0;
  const diagnosticHoldCount = queue?.Summary.DiagnosticHoldCount ?? 0;
  const fastReviewCount = queue?.Summary.FastReviewCount ?? 0;
  const phase5AttentionCount = domainReviewCount + diagnosticHoldCount;
  const totalAttentionCount = driftReviewCount + phase5AttentionCount;
  const draftedCount = Object.keys(recordsByBusinessId).length;

  const driftSources = drift?.sources ?? [];
  const failedSourceCount = driftSources.filter((s) => s.status === 'FETCH_FAILED').length;
  const changedSourceCount = driftSources.filter((s) => s.status === 'DRIFT_DETECTED').length;
  const okSourceCount = driftSources.filter((s) => s.status === 'OK').length;

  const primaryQueueSource: QueueSourceTab = phase5AttentionCount > 0 ? 'phase5' : 'drift';

  return (
    <div className="space-y-6">
      {isDemo && (
        <div className="flex flex-wrap items-center justify-between gap-3 rounded-xl border border-blue-200 bg-blue-50/80 px-4 py-3 text-sm text-blue-950">
          <div className="flex items-center gap-2.5">
            <FlaskConical className="h-4 w-4 shrink-0 text-blue-700" />
            <div>
              <span className="font-semibold">샘플 데이터(DEMO) 미리보기 모드</span>
              <span className="ml-2 text-xs text-blue-800">
                실제 정본/운영 데이터가 아닌 UI 확인용 가상 예시입니다. 실제 점검 JSON을 업로드하면 즉시 전환됩니다.
              </span>
            </div>
          </div>
          <Button size="sm" variant="outline" onClick={onTriggerUpload}>
            <Upload className="h-3.5 w-3.5" />
            실제 리포트 불러오기
          </Button>
        </div>
      )}

      {/* Live Pipeline Connection Status Buttons */}
      <Card className="p-4">
        <div className="flex flex-col gap-3 lg:flex-row lg:items-center lg:justify-between">
          <div>
            <div className="text-xs font-semibold text-slate-900">파이프라인 데이터 연결 상태</div>
            <div className="text-[11px] text-slate-500">
              연결됨 버튼을 누르면 해당 대기열로 바로 이동하고, 미연결 버튼을 누르면 JSON 리포트를 불러옵니다.
            </div>
          </div>
          <div className="flex flex-wrap gap-2">
            <span className="inline-flex items-center gap-1.5 rounded-lg border border-emerald-300 bg-emerald-50 px-3 py-1.5 text-xs font-medium text-emerald-900">
              <Link2 className="h-3.5 w-3.5 text-emerald-700" />
              번들 시드 기준선 · 연결됨 (v{seed.seedVersion})
            </span>

            {drift ? (
              <button
                type="button"
                onClick={() => onOpenQueue('ATTENTION', 'drift')}
                className="inline-flex items-center gap-1.5 rounded-lg border border-emerald-300 bg-emerald-50 px-3 py-1.5 text-xs font-medium text-emerald-900 transition hover:bg-emerald-100 cursor-pointer"
              >
                <Link2 className="h-3.5 w-3.5 text-emerald-700" />
                주간 드리프트 · 연결됨 ({driftReviewCount > 0 ? `확인 필요 ${driftReviewCount}건` : '이상 없음'})
                <ArrowRight className="h-3 w-3" />
              </button>
            ) : (
              <button
                type="button"
                onClick={onTriggerUpload}
                className="inline-flex items-center gap-1.5 rounded-lg border border-amber-300 bg-amber-50 px-3 py-1.5 text-xs font-medium text-amber-900 transition hover:bg-amber-100 cursor-pointer"
              >
                <Link2Off className="h-3.5 w-3.5 text-amber-700" />
                주간 드리프트 · 미연결 (불러오기)
              </button>
            )}

            {queue ? (
              <button
                type="button"
                onClick={() => onOpenQueue('ATTENTION', 'phase5')}
                className="inline-flex items-center gap-1.5 rounded-lg border border-emerald-300 bg-emerald-50 px-3 py-1.5 text-xs font-medium text-emerald-900 transition hover:bg-emerald-100 cursor-pointer"
              >
                <Link2 className="h-3.5 w-3.5 text-emerald-700" />
                Phase 5 리뷰 큐 · 연결됨 ({queue.Summary.ExportedItemCount}건)
                <ArrowRight className="h-3 w-3" />
              </button>
            ) : (
              <button
                type="button"
                onClick={onTriggerUpload}
                className="inline-flex items-center gap-1.5 rounded-lg border border-slate-300 bg-slate-50 px-3 py-1.5 text-xs font-medium text-slate-700 transition hover:bg-slate-100 cursor-pointer"
              >
                <Link2Off className="h-3.5 w-3.5 text-slate-500" />
                Phase 5 리뷰 큐 · 미연결 (불러오기)
              </button>
            )}
          </div>
        </div>
      </Card>

      {/* Top Action / Attention Banner */}
      {totalAttentionCount > 0 ? (
        <div className="flex flex-wrap items-center justify-between gap-4 rounded-xl border border-amber-300 bg-gradient-to-r from-amber-50 to-orange-50/70 px-5 py-4">
          <div className="flex items-start gap-3">
            <div className="mt-0.5 rounded-lg bg-amber-100 p-2 text-amber-800">
              <AlertTriangle className="h-5 w-5" />
            </div>
            <div>
              <div className="flex flex-wrap items-center gap-2">
                <h2 className="text-base font-semibold text-slate-900">
                  자동 검증 기준에 애매하게 걸쳐 직접 확인이 필요한 항목이 {totalAttentionCount}건 있습니다
                </h2>
                {driftReviewCount > 0 && <Badge tone="amber">주간 출처 변경·재확인 {driftReviewCount}건</Badge>}
                {domainReviewCount > 0 && <Badge tone="amber">Phase 5 내용 애매 {domainReviewCount}건</Badge>}
                {diagnosticHoldCount > 0 && <Badge tone="red">진단 보류 {diagnosticHoldCount}건</Badge>}
              </div>
              <p className="mt-1 text-xs text-slate-700">
                자동화는 정본 데이터를 임의로 수정하지 않습니다(<code className="rounded bg-white/80 px-1">ProductionAction=NONE</code>).
                직접 확인 대기열에서 공식 출처 링크를 열어 확인하세요.
              </p>
            </div>
          </div>
          <Button variant="primary" size="lg" onClick={() => onOpenQueue('ATTENTION', primaryQueueSource)}>
            직접 확인 필요한 데이터 보기 ({totalAttentionCount}건)
            <ArrowRight className="h-4 w-4" />
          </Button>
        </div>
      ) : drift || queue ? (
        <div className="flex flex-wrap items-center justify-between gap-4 rounded-xl border border-emerald-200 bg-emerald-50/70 px-5 py-4">
          <div className="flex items-center gap-3">
            <CheckCircle2 className="h-5 w-5 text-emerald-700" />
            <div>
              <h2 className="text-sm font-semibold text-emerald-950">
                연결 완료 · 현재 직접 확인이 필요한 애매한 항목이 0건입니다
              </h2>
              <p className="text-xs text-emerald-800">
                {drift ? `주간 드리프트 점검 완료(${drift.generatedAtUtc})` : ''}{' '}
                {queue ? `· Phase 5 FAST_REVIEW ${fastReviewCount}건` : ''}
              </p>
            </div>
          </div>
          <Button variant="outline" onClick={() => onOpenQueue('ALL', queue ? 'phase5' : 'drift')}>
            검토 대기열 열기
            <ArrowRight className="h-4 w-4" />
          </Button>
        </div>
      ) : (
        <Card className="border-dashed border-slate-300 bg-slate-50/60">
          <CardContent className="flex flex-col gap-4 py-6 lg:flex-row lg:items-center lg:justify-between">
            <div className="space-y-1.5">
              <div className="flex items-center gap-2">
                <Badge tone="neutral">기준선 스냅샷만 로드됨</Badge>
                <span className="text-xs text-slate-500">생성 시각: {snapshot.GeneratedAtUtc || '-'}</span>
              </div>
              <h2 className="text-base font-semibold text-slate-900">
                주간 드리프트 및 Phase 5 리뷰 큐 실행 리포트가 아직 연결되지 않았습니다
              </h2>
              <p className="text-xs text-slate-600">
                JSON 리포트 파일을 화면에 드래그 앤 드롭하거나, 샘플 데이터로 전체 화면을 미리 확인해 보세요.
              </p>
            </div>
            <div className="flex shrink-0 flex-wrap gap-2">
              <Button variant="outline" onClick={onTriggerUpload}>
                <Upload className="h-4 w-4" />
                JSON 리포트 불러오기
              </Button>
              {!isDemo && (
                <Button variant="default" onClick={onEnableDemo}>
                  <FlaskConical className="h-4 w-4" />
                  샘플 데이터로 화면 미리보기
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
              <span>번들 시드 기준선</span>
              <Database className="h-4 w-4 text-slate-400" />
            </div>
            <div className="flex items-baseline gap-2">
              <span className="tabular-nums text-2xl font-bold text-slate-900">
                {seed.totalCount.toLocaleString()}건
              </span>
              <Badge tone="blue">seed v{seed.seedVersion}</Badge>
            </div>
            <p className="text-xs text-slate-500">생성일: {seed.generatedAt}</p>
          </CardContent>
        </Card>

        <Card>
          <CardContent className="space-y-2">
            <div className="flex items-center justify-between text-xs font-medium text-slate-500">
              <span>지도 핀 커버리지</span>
              <MapPin className="h-4 w-4 text-slate-400" />
            </div>
            <div className="flex items-baseline gap-2">
              <span className="tabular-nums text-2xl font-bold text-slate-900">
                {seed.exactPinCount.toLocaleString()}건
              </span>
              <span className="tabular-nums text-xs font-semibold text-emerald-700">{pinPct}%</span>
            </div>
            <div className="h-1.5 w-full overflow-hidden rounded-full bg-slate-100">
              <div className="h-full rounded-full bg-emerald-600" style={{ width: `${pinPct}%` }} />
            </div>
            <p className="text-xs text-slate-500">
              좌표 미확정(목록·검색 전용): {seed.unconfirmedCoordinateCount.toLocaleString()}건
            </p>
          </CardContent>
        </Card>

        <Card>
          <CardContent className="space-y-2">
            <div className="flex items-center justify-between text-xs font-medium text-slate-500">
              <span>공식 출처 자동 점검</span>
              <RefreshCw className="h-4 w-4 text-slate-400" />
            </div>
            {drift ? (
              <>
                <div className="flex items-baseline gap-2">
                  <span className="tabular-nums text-2xl font-bold text-slate-900">
                    {okSourceCount} / {driftSources.length}
                  </span>
                  <span className="text-xs text-slate-500">정상 출처</span>
                </div>
                <div className="flex flex-wrap gap-1.5">
                  {changedSourceCount > 0 && <Badge tone="amber">변경 {changedSourceCount}</Badge>}
                  {failedSourceCount > 0 && <Badge tone="red">실패 {failedSourceCount}</Badge>}
                  {changedSourceCount === 0 && failedSourceCount === 0 && <Badge tone="emerald">오류 없음</Badge>}
                </div>
              </>
            ) : (
              <>
                <div className="text-lg font-semibold text-slate-400">미연결</div>
                <p className="text-xs text-slate-500">weekly-drift-summary.json을 불러오면 표시됩니다.</p>
              </>
            )}
          </CardContent>
        </Card>

        <Card>
          <CardContent className="space-y-2">
            <div className="flex items-center justify-between text-xs font-medium text-slate-500">
              <span>직접 확인 대기 · 확인 기록</span>
              <ShieldAlert className="h-4 w-4 text-slate-400" />
            </div>
            <div className="flex items-baseline gap-2">
              <span className="tabular-nums text-2xl font-bold text-slate-900">{totalAttentionCount}건</span>
              <Badge tone={draftedCount + driftCheckedCount > 0 ? 'emerald' : 'neutral'}>
                확인 {driftCheckedCount} · 원장 {draftedCount}
              </Badge>
            </div>
            <p className="text-xs text-slate-500">
              주간 드리프트 {driftReviewCount}건 · Phase 5 {phase5AttentionCount}건
            </p>
          </CardContent>
        </Card>
      </div>

      {/* Phase 5 Bucket Cards */}
      <Card>
        <CardHeader className="flex-row flex-wrap items-center justify-between gap-2">
          <div>
            <CardTitle>Phase 5 검증 결과 분포 & 수동 확인 이동</CardTitle>
            <CardDescription>
              {queue
                ? '각 버킷 카드를 누르면 해당 분류로 필터링된 Phase 5 직접 확인 대기열 화면으로 바로 이동합니다.'
                : 'Phase 5 배치 실행 파일(review-queue-summary.json)을 불러오면 세부 버킷 수량이 표시됩니다.'}
            </CardDescription>
          </div>
          {queue ? (
            <Button size="sm" variant="outline" onClick={() => onOpenQueue('ALL', 'phase5')}>
              전체 큐 보기 ({queue.Summary.ExportedItemCount})
              <ArrowRight className="h-3.5 w-3.5" />
            </Button>
          ) : (
            <Button size="sm" variant="outline" onClick={onTriggerUpload}>
              <Upload className="h-3.5 w-3.5" />
              review-queue-summary.json 불러오기
            </Button>
          )}
        </CardHeader>
        <CardContent>
          <div className="grid grid-cols-1 gap-4 md:grid-cols-3">
            <div className="flex flex-col justify-between rounded-xl border border-amber-200 bg-amber-50/50 p-4">
              <div>
                <div className="flex items-center justify-between">
                  <Badge tone="amber">DOMAIN_REVIEW</Badge>
                  <span className="tabular-nums text-2xl font-bold text-amber-950">{domainReviewCount}</span>
                </div>
                <h4 className="mt-2.5 text-sm font-semibold text-slate-900">내용 애매 · 사람 판단 필요</h4>
                <p className="mt-1 text-xs leading-relaxed text-slate-600">
                  공식 출처와 정본 혜택 내용 불일치, 목록 미관측, YELLOW/RED 판정 등으로 원문 확인이 필요합니다.
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
                  <Badge tone="red">DIAGNOSTIC_HOLD</Badge>
                  <span className="tabular-nums text-2xl font-bold text-red-900">{diagnosticHoldCount}</span>
                </div>
                <h4 className="mt-2.5 text-sm font-semibold text-slate-900">진단 보류 · 수집/파싱 오류</h4>
                <p className="mt-1 text-xs leading-relaxed text-slate-600">
                  HTTP/파싱 실패, 비교 불가 관측, 스캔 PDF OCR 보류 등 자동 비교가 완결되지 않은 항목입니다.
                </p>
              </div>
              <Button
                className="mt-4 w-full justify-between"
                variant="outline"
                size="sm"
                disabled={!queue}
                onClick={() => onOpenQueue('DIAGNOSTIC_HOLD', 'phase5')}
              >
                진단 보류 항목 보기
                <ArrowRight className="h-3.5 w-3.5" />
              </Button>
            </div>

            <div className="flex flex-col justify-between rounded-xl border border-emerald-200 bg-emerald-50/40 p-4">
              <div>
                <div className="flex items-center justify-between">
                  <Badge tone="emerald">FAST_REVIEW</Badge>
                  <span className="tabular-nums text-2xl font-bold text-emerald-950">{fastReviewCount}</span>
                </div>
                <h4 className="mt-2.5 text-sm font-semibold text-slate-900">빠른 승인 후보 (GREEN)</h4>
                <p className="mt-1 text-xs leading-relaxed text-slate-600">
                  공식 출처와 정본이 일치해 최종 사람 승인(`APPROVE_ACTIVE`)만 거치면 되는 항목입니다.
                </p>
              </div>
              <Button
                className="mt-4 w-full justify-between"
                variant="outline"
                size="sm"
                disabled={!queue}
                onClick={() => onOpenQueue('FAST_REVIEW', 'phase5')}
              >
                빠른 검토 목록 보기
                <ArrowRight className="h-3.5 w-3.5" />
              </Button>
            </div>
          </div>
        </CardContent>
      </Card>

      {/* Weekly Source Drift Table */}
      <Card>
        <CardHeader className="flex-row flex-wrap items-center justify-between gap-2">
          <div>
            <CardTitle>출처별 자동화 점검 현황 (`weekly-drift-summary.json`)</CardTitle>
            <CardDescription>
              {drift
                ? `최근 점검: ${drift.generatedAtUtc} · 정본 행 수 ${drift.canonicalRowCount.toLocaleString()}건 · 자동 정본 수정 ${drift.automaticCanonicalMutation ? '활성' : '차단(false)'}`
                : '주간 공식 출처 드리프트 점검 리포트를 불러오면 병무청·동두천·파주·양주 상태가 표시됩니다.'}
            </CardDescription>
          </div>
          {drift && driftReviewCount > 0 && (
            <Button size="sm" variant="primary" onClick={() => onOpenQueue('ATTENTION', 'drift')}>
              변경·재확인 항목 직접 확인하기 ({driftReviewCount}건)
              <ArrowRight className="h-3.5 w-3.5" />
            </Button>
          )}
        </CardHeader>
        <CardContent className="p-0">
          {drift && driftSources.length > 0 ? (
            <div className="overflow-x-auto">
              <table className="w-full text-left text-sm">
                <thead className="border-b border-slate-200 bg-slate-50/80 text-xs font-medium text-slate-500">
                  <tr>
                    <th className="px-5 py-3">공식 출처</th>
                    <th className="px-4 py-3">상태</th>
                    <th className="px-4 py-3 text-right">공식 건수</th>
                    <th className="px-4 py-3 text-right">정본 건수</th>
                    <th className="px-5 py-3">세부 내역 / 조치 필요 사항</th>
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
              표시할 출처별 드리프트 데이터가 없습니다.
            </div>
          )}
        </CardContent>
      </Card>
    </div>
  );
}
