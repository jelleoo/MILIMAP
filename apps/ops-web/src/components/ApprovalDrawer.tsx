import { useEffect, useState } from 'react';
import {
  AlertCircle,
  CheckCircle2,
  ExternalLink,
  Link2,
  MapPin,
  ShieldAlert,
  Trash2,
} from 'lucide-react';
import {
  buildApprovalRecord,
  createDefaultApprovalDraft,
  formatLocalIsoTimestampWithOffset,
  validateApprovalDraft,
  type ApprovalDraft,
} from '../lib/approvalLedger';
import { BUCKET_META, formatCodeLabel, getItemReasonSummary, isNeedsHumanAttention } from '../lib/reasonLabels';
import { buildNaverMapSearchUrl, extractSafeUrls } from '../lib/safeUrl';
import type {
  BenefitDecision,
  BenefitReleaseApprovalRecord,
  CoordinateDecision,
  ReviewQueueItem,
} from '../types/ops';
import { Badge, Button, Card, CardContent, CardDescription, CardHeader, CardTitle, Input, Textarea } from './ui/primitives';

interface ApprovalDrawerProps {
  item: ReviewQueueItem | null;
  existingRecord?: BenefitReleaseApprovalRecord;
  defaultApprover: string;
  relatedBenefitRecord?: BenefitReleaseApprovalRecord;
  onSaveRecord: (record: BenefitReleaseApprovalRecord, approverName: string) => void;
  onDeleteRecord: (businessId: string) => void;
  onAttachLocationObservation: (businessId: string, locationObservationId: string) => void;
}

export function ApprovalDrawer({
  item,
  existingRecord,
  defaultApprover,
  relatedBenefitRecord,
  onSaveRecord,
  onDeleteRecord,
  onAttachLocationObservation,
}: ApprovalDrawerProps) {
  const [draft, setDraft] = useState<ApprovalDraft | null>(null);
  const [statusNotice, setStatusNotice] = useState<string | null>(null);

  useEffect(() => {
    if (!item) {
      setDraft(null);
      setStatusNotice(null);
      return;
    }
    setDraft(createDefaultApprovalDraft(item, existingRecord, defaultApprover));
    setStatusNotice(null);
  }, [item, existingRecord, defaultApprover]);

  if (!item || !draft) {
    return (
      <Card className="flex h-full min-h-[420px] items-center justify-center p-8 text-center text-sm text-slate-500">
        왼쪽 대기열에서 항목을 선택하면 직접 확인 링크와 승인 원장 입력 폼이 표시됩니다.
      </Card>
    );
  }

  const bucketMeta = BUCKET_META[item.OperatorBucket];
  const needsHuman = isNeedsHumanAttention(item.OperatorBucket);
  const safeUrls = extractSafeUrls(item.CanonicalSourceUrl, item.SourceUrls);
  const naverMapUrl = buildNaverMapSearchUrl(item.BusinessName, item.RoadAddress, item.District);
  const reasonCodes = getItemReasonSummary(item);
  const validationErrors = validateApprovalDraft(item, draft);
  const canApproveActive = item.OperationalStatus === 'COMPLETE' && item.Comparable;

  const handleDecisionChange = (decision: BenefitDecision) => {
    setDraft((prev) => {
      if (!prev) return prev;
      return {
        ...prev,
        benefitDecision: decision,
        coordinateDecision: decision === 'APPROVE_ENDED' ? 'SUPPRESS_PIN' : prev.coordinateDecision,
      };
    });
    setStatusNotice(null);
  };

  const handleCoordinateChange = (coord: CoordinateDecision) => {
    setDraft((prev) => (prev ? { ...prev, coordinateDecision: coord } : prev));
    setStatusNotice(null);
  };

  const handleSave = () => {
    const refreshedDraft: ApprovalDraft = {
      ...draft,
      approvedAt: formatLocalIsoTimestampWithOffset(),
    };
    const errs = validateApprovalDraft(item, refreshedDraft);
    if (errs.length > 0) {
      setDraft(refreshedDraft);
      return;
    }
    const record = buildApprovalRecord(item, refreshedDraft);
    onSaveRecord(record, refreshedDraft.approvedBy.trim());
    setDraft(refreshedDraft);
    setStatusNotice('승인 원장에 저장되었습니다. 상단 또는 하단 버튼으로 JSON을 내려받아 검증기에 전달하세요.');
  };

  return (
    <Card className="flex flex-col overflow-hidden">
      <CardHeader className="space-y-2 bg-slate-50/70">
        <div className="flex flex-wrap items-center justify-between gap-2">
          <div className="flex flex-wrap items-center gap-2">
            <Badge tone={bucketMeta.tone}>{bucketMeta.label}</Badge>
            <Badge tone="neutral">{item.Domain}</Badge>
            {item.ReviewClass && <Badge tone="neutral">판정: {item.ReviewClass}</Badge>}
            {existingRecord && <Badge tone="emerald">원장 작성 완료</Badge>}
          </div>
          <span className="font-mono text-[11px] text-slate-500">{item.BusinessId}</span>
        </div>

        <div>
          <CardTitle className="text-lg font-bold text-slate-900">
            {item.BusinessName || '(업소명 미상)'}
          </CardTitle>
          <CardDescription className="mt-0.5 text-xs text-slate-600">
            {[item.District, item.RoadAddress].filter(Boolean).join(' · ') || '주소 정보 없음'}
            {item.CanonicalRowNumber ? ` · 정본 CSV ${item.CanonicalRowNumber}행` : ''}
          </CardDescription>
        </div>
      </CardHeader>

      <CardContent className="space-y-5">
        {/* Manual verification alert & direct links */}
        <div
          className={
            needsHuman
              ? 'rounded-xl border border-amber-300 bg-amber-50/80 p-4'
              : 'rounded-xl border border-emerald-200 bg-emerald-50/60 p-4'
          }
        >
          <div className="flex items-start gap-2.5">
            <ShieldAlert
              className={
                needsHuman ? 'mt-0.5 h-4 w-4 shrink-0 text-amber-800' : 'mt-0.5 h-4 w-4 shrink-0 text-emerald-700'
              }
            />
            <div className="min-w-0 flex-1 space-y-2">
              <div className="text-sm font-semibold text-slate-900">
                {needsHuman
                  ? '직접 확인이 필요합니다 — 아래 링크로 실제 공식 출처를 열어 확인해 주세요.'
                  : '자동 검증을 통과한 항목입니다 — 필요 시 링크로 최종 확인 후 승인할 수 있습니다.'}
              </div>
              <p className="text-xs text-slate-700">{bucketMeta.description}</p>

              {reasonCodes.length > 0 && (
                <div className="flex flex-wrap gap-1.5 pt-1">
                  {reasonCodes.map((code) => (
                    <Badge key={code} tone={needsHuman ? 'amber' : 'neutral'}>
                      {formatCodeLabel(code)}
                    </Badge>
                  ))}
                </div>
              )}

              {/* Direct External Verification Links */}
              <div className="flex flex-wrap gap-2 pt-2">
                {safeUrls.length > 0 ? (
                  safeUrls.map((url, idx) => (
                    <a
                      key={url}
                      href={url}
                      target="_blank"
                      rel="noopener noreferrer"
                      className="inline-flex items-center gap-1.5 rounded-lg bg-slate-900 px-3 py-1.5 text-xs font-medium text-white shadow-xs transition hover:bg-slate-800"
                    >
                      <ExternalLink className="h-3.5 w-3.5" />
                      {safeUrls.length > 1 ? `공식 출처 직접 확인 #${idx + 1}` : '공식 출처 직접 확인'}
                    </a>
                  ))
                ) : (
                  <span className="inline-flex items-center gap-1 rounded-md border border-red-300 bg-red-50 px-2.5 py-1 text-xs font-medium text-red-800">
                    <AlertCircle className="h-3.5 w-3.5" />
                    안전한 http(s) 공식 출처 URL이 없습니다. 아래 입력란에 확인 URL을 직접 입력하세요.
                  </span>
                )}

                <a
                  href={naverMapUrl}
                  target="_blank"
                  rel="noopener noreferrer"
                  className="inline-flex items-center gap-1.5 rounded-lg border border-slate-300 bg-white px-3 py-1.5 text-xs font-medium text-slate-800 shadow-2xs transition hover:bg-slate-50"
                >
                  <MapPin className="h-3.5 w-3.5 text-emerald-700" />
                  네이버 지도에서 직접 확인
                </a>
              </div>
            </div>
          </div>
        </div>

        {/* Canonical vs Observation Comparison */}
        <div className="grid grid-cols-1 gap-3 md:grid-cols-2">
          <div className="rounded-lg border border-slate-200 bg-slate-50/60 p-3.5">
            <div className="mb-2 text-xs font-semibold text-slate-700">현재 정본 CSV 상태</div>
            <dl className="space-y-1.5 text-xs">
              <div className="flex justify-between gap-2">
                <dt className="text-slate-500">혜택 상태</dt>
                <dd className="font-medium text-slate-900">{item.CanonicalBenefitStatus || '-'}</dd>
              </div>
              <div className="flex justify-between gap-2">
                <dt className="text-slate-500">좌표 검증</dt>
                <dd className="font-medium text-slate-900">{item.CanonicalCoordinateStatus || '-'}</dd>
              </div>
              <div className="flex justify-between gap-2">
                <dt className="text-slate-500">최근 확인일</dt>
                <dd className="font-medium text-slate-900">{item.CanonicalLastVerifiedAt || '-'}</dd>
              </div>
            </dl>
          </div>

          <div className="rounded-lg border border-slate-200 bg-slate-50/60 p-3.5">
            <div className="mb-2 text-xs font-semibold text-slate-700">파이프라인 최신 관측</div>
            <dl className="space-y-1.5 text-xs">
              <div className="flex justify-between gap-2">
                <dt className="text-slate-500">라우트 / 상태</dt>
                <dd className="font-medium text-slate-900">
                  {item.ReviewRoute} ({item.OperationalStatus})
                </dd>
              </div>
              <div className="flex justify-between gap-2">
                <dt className="text-slate-500">비교 가능 / 혜택</dt>
                <dd className="font-medium text-slate-900">
                  {item.Comparable ? '비교 가능' : '비교 불가'} · {item.BenefitState || item.LocationEvaluationStatus || '-'}
                </dd>
              </div>
              <div className="flex justify-between gap-2">
                <dt className="text-slate-500">관측 시각</dt>
                <dd className="font-mono text-[11px] text-slate-700">{item.ObservedAt || '-'}</dd>
              </div>
            </dl>
          </div>
        </div>

        {/* Validated Claims / Evidence */}
        {item.ValidatedClaims && item.ValidatedClaims.length > 0 && (
          <div className="rounded-lg border border-slate-200 p-3.5">
            <div className="mb-2 text-xs font-semibold text-slate-700">관측된 혜택 근거 비교</div>
            <div className="space-y-2">
              {item.ValidatedClaims.map((claim, idx) => (
                <div key={idx} className="rounded-md bg-slate-50 p-2.5 text-xs">
                  <div className="font-medium text-slate-900">
                    [{claim.ClaimType || 'CLAIM'}] {claim.Value || '-'}
                  </div>
                  {claim.EvidenceText && (
                    <div className="mt-1 text-slate-700">근거: {claim.EvidenceText}</div>
                  )}
                  {claim.EvidenceReference && (
                    <div className="mt-0.5 font-mono text-[11px] text-slate-500">
                      위치: {claim.EvidenceReference}
                    </div>
                  )}
                </div>
              ))}
            </div>
          </div>
        )}

        {/* Approval Ledger Form */}
        {item.Domain === 'BENEFIT' ? (
          <div className="space-y-4 border-t border-slate-200 pt-4">
            <div className="flex items-center justify-between">
              <h4 className="text-sm font-semibold text-slate-900">
                검증기(`validate-benefit-release-approvals.ps1`) 승인 결정 작성
              </h4>
              <span className="font-mono text-[11px] text-slate-500">Obs: {item.CurrentObservationId}</span>
            </div>

            <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
              <div className="space-y-1.5">
                <label className="text-xs font-medium text-slate-700">혜택 판정 (`benefitDecision`)</label>
                <div className="grid grid-cols-1 gap-1.5">
                  {(
                    [
                      { value: 'APPROVE_ACTIVE', label: '운영 승인 (APPROVE_ACTIVE)', disabled: !canApproveActive },
                      { value: 'HOLD_NEEDS_VERIFICATION', label: '보류 / 추가확인 (HOLD)', disabled: false },
                      { value: 'APPROVE_ENDED', label: '혜택 종료 확정 (APPROVE_ENDED)', disabled: false },
                    ] as const
                  ).map((opt) => (
                    <button
                      key={opt.value}
                      type="button"
                      disabled={opt.disabled}
                      onClick={() => handleDecisionChange(opt.value)}
                      className={`flex items-center justify-between rounded-lg border px-3 py-2 text-left text-xs font-medium transition cursor-pointer disabled:cursor-not-allowed disabled:opacity-45 ${
                        draft.benefitDecision === opt.value
                          ? 'border-slate-900 bg-slate-900 text-white'
                          : 'border-slate-200 bg-white text-slate-800 hover:bg-slate-50'
                      }`}
                    >
                      <span>{opt.label}</span>
                      {opt.disabled && <span className="text-[10px]">비교불가</span>}
                    </button>
                  ))}
                </div>
              </div>

              <div className="space-y-1.5">
                <label className="text-xs font-medium text-slate-700">좌표 핀 판정 (`coordinateDecision`)</label>
                <div className="grid grid-cols-1 gap-1.5">
                  <button
                    type="button"
                    disabled={draft.benefitDecision === 'APPROVE_ENDED'}
                    onClick={() => handleCoordinateChange('KEEP_PIN')}
                    className={`flex items-center justify-between rounded-lg border px-3 py-2 text-left text-xs font-medium transition cursor-pointer disabled:cursor-not-allowed disabled:opacity-45 ${
                      draft.coordinateDecision === 'KEEP_PIN'
                        ? 'border-emerald-700 bg-emerald-700 text-white'
                        : 'border-slate-200 bg-white text-slate-800 hover:bg-slate-50'
                    }`}
                  >
                    <span>지도 핀 유지 (KEEP_PIN)</span>
                  </button>
                  <button
                    type="button"
                    onClick={() => handleCoordinateChange('SUPPRESS_PIN')}
                    className={`flex items-center justify-between rounded-lg border px-3 py-2 text-left text-xs font-medium transition cursor-pointer ${
                      draft.coordinateDecision === 'SUPPRESS_PIN'
                        ? 'border-slate-900 bg-slate-900 text-white'
                        : 'border-slate-200 bg-white text-slate-800 hover:bg-slate-50'
                    }`}
                  >
                    <span>지도 핀 숨김 (SUPPRESS_PIN)</span>
                  </button>
                </div>
                <p className="text-[11px] text-slate-500">
                  정본 좌표상태: {item.CanonicalCoordinateStatus || '미상'}
                </p>
              </div>
            </div>

            <div className="grid grid-cols-1 gap-3 sm:grid-cols-3">
              <div className="space-y-1 sm:col-span-1">
                <label className="text-xs font-medium text-slate-700">승인자 (`approvedBy`)*</label>
                <Input
                  placeholder="예: dev-kim"
                  value={draft.approvedBy}
                  onChange={(e) => {
                    setDraft({ ...draft, approvedBy: e.target.value });
                    setStatusNotice(null);
                  }}
                />
              </div>
              <div className="space-y-1 sm:col-span-1">
                <label className="text-xs font-medium text-slate-700">확인일 (`verifiedOn`)*</label>
                <Input
                  placeholder="YYYY-MM-DD"
                  value={draft.verifiedOn}
                  onChange={(e) => {
                    setDraft({ ...draft, verifiedOn: e.target.value });
                    setStatusNotice(null);
                  }}
                />
              </div>
              <div className="space-y-1 sm:col-span-1">
                <label className="text-xs font-medium text-slate-700">좌표 관측 ID (선택)</label>
                <Input
                  placeholder="locationObservationId"
                  value={draft.locationObservationId}
                  onChange={(e) => {
                    setDraft({ ...draft, locationObservationId: e.target.value });
                    setStatusNotice(null);
                  }}
                />
              </div>
            </div>

            <div className="space-y-1">
              <label className="text-xs font-medium text-slate-700">
                확인한 공식 출처 URL (`verifiedSourceUrl`, 복수 URL은 <code> | </code>로 구분)*
              </label>
              <Input
                placeholder="https://..."
                value={draft.verifiedSourceUrl}
                onChange={(e) => {
                  setDraft({ ...draft, verifiedSourceUrl: e.target.value });
                  setStatusNotice(null);
                }}
              />
            </div>

            <div className="space-y-1">
              <label className="text-xs font-medium text-slate-700">
                판단 사유 (`rationale`
                {(draft.benefitDecision === 'APPROVE_ENDED' ||
                  (draft.benefitDecision === 'APPROVE_ACTIVE' && item.ReviewClass !== 'GREEN')) &&
                  ' — 필수'}
                )
              </label>
              <Textarea
                placeholder="공식 출처에서 확인한 구체적 사유나 변경/종료 근거를 기록하세요."
                value={draft.rationale}
                onChange={(e) => {
                  setDraft({ ...draft, rationale: e.target.value });
                  setStatusNotice(null);
                }}
              />
            </div>

            {validationErrors.length > 0 && (
              <div className="rounded-lg border border-red-200 bg-red-50 p-3 text-xs text-red-800">
                <div className="mb-1 font-semibold">검증기 계약 확인 필요:</div>
                <ul className="list-disc space-y-0.5 pl-4">
                  {validationErrors.map((err) => (
                    <li key={err}>{err}</li>
                  ))}
                </ul>
              </div>
            )}

            {statusNotice && (
              <div className="flex items-center gap-2 rounded-lg border border-emerald-200 bg-emerald-50 p-3 text-xs text-emerald-900">
                <CheckCircle2 className="h-4 w-4 shrink-0 text-emerald-700" />
                <span>{statusNotice}</span>
              </div>
            )}

            <div className="flex flex-wrap items-center justify-between gap-2 pt-1">
              {existingRecord ? (
                <Button variant="ghost" size="sm" onClick={() => onDeleteRecord(item.BusinessId)}>
                  <Trash2 className="h-3.5 w-3.5 text-red-600" />
                  <span className="text-red-700">원장에서 제거</span>
                </Button>
              ) : (
                <span className="text-xs text-slate-500">저장 시 브라우저에 임시 보관되며 원장 JSON으로 내보낼 수 있습니다.</span>
              )}
              <Button disabled={validationErrors.length > 0} onClick={handleSave}>
                이 항목 승인 원장에 저장
              </Button>
            </div>
          </div>
        ) : (
          <div className="space-y-3 border-t border-slate-200 pt-4">
            <h4 className="text-sm font-semibold text-slate-900">LOCATION 좌표 관측 항목 안내</h4>
            <p className="text-xs leading-relaxed text-slate-600">
              `LOCATION` 축 항목은 단독 승인 레코드가 아니라 동일 업소(`{item.BusinessId}`)의 `BENEFIT` 승인 레코드에{' '}
              <code className="rounded bg-slate-100 px-1">locationObservationId</code>로 연결해 검증기에 전달합니다.
            </p>
            {relatedBenefitRecord ? (
              <div className="flex flex-wrap items-center justify-between gap-2 rounded-lg border border-blue-200 bg-blue-50/70 p-3">
                <span className="text-xs text-blue-950">
                  동일 업소의 BENEFIT 레코드가 원장에 있습니다. (`{item.CurrentObservationId}` 연결 가능)
                </span>
                <Button
                  size="sm"
                  variant="outline"
                  onClick={() => onAttachLocationObservation(item.BusinessId, item.CurrentObservationId)}
                >
                  <Link2 className="h-3.5 w-3.5" />
                  BENEFIT 레코드에 연결
                </Button>
              </div>
            ) : (
              <div className="rounded-lg border border-slate-200 bg-slate-50 p-3 text-xs text-slate-600">
                먼저 동일 업소의 `BENEFIT` 항목을 승인 원장에 저장하면 이 `locationObservationId`를 원클릭으로 연결할 수 있습니다.
              </div>
            )}
          </div>
        )}
      </CardContent>
    </Card>
  );
}
