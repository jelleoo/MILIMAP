import { useMemo, useState } from 'react';
import {
  AlertTriangle,
  CheckCircle2,
  ExternalLink,
  MapPin,
  Search,
  ShieldAlert,
} from 'lucide-react';
import { buildNaverMapSearchUrl, extractSafeUrls } from '../lib/safeUrl';
import type { WeeklyDriftReviewCategory, WeeklyDriftReviewItem } from '../types/ops';
import { Badge, Button, Card, CardContent, CardDescription, CardHeader, CardTitle, Input, Select, Textarea } from './ui/primitives';

export interface DriftCheckEntry {
  checked: boolean;
  memo: string;
  checkedAt: string;
}

interface DriftReviewPanelProps {
  items: WeeklyDriftReviewItem[];
  checksById: Record<string, DriftCheckEntry>;
  onSaveCheck: (id: string, entry: DriftCheckEntry) => void;
  onClearCheck: (id: string) => void;
}

export function DriftReviewPanel({
  items,
  checksById,
  onSaveCheck,
  onClearCheck,
}: DriftReviewPanelProps) {
  const [sourceFilter, setSourceFilter] = useState<'ALL' | 'mma' | 'ddc' | 'paju' | 'yangju'>('ALL');
  const [categoryFilter, setCategoryFilter] = useState<'ALL' | WeeklyDriftReviewCategory>('ALL');
  const [checkStatusFilter, setCheckStatusFilter] = useState<'ALL' | 'UNCHECKED' | 'CHECKED'>('ALL');
  const [searchQuery, setSearchQuery] = useState('');
  const [selectedId, setSelectedId] = useState<string | null>(null);
  const [memoInput, setMemoInput] = useState<string>('');
  const [memoEditingId, setMemoEditingId] = useState<string | null>(null);

  const sourceCounts = useMemo(() => {
    const map: Record<string, number> = { ALL: items.length, mma: 0, ddc: 0, paju: 0, yangju: 0 };
    for (const it of items) {
      map[it.sourceId] = (map[it.sourceId] ?? 0) + 1;
    }
    return map;
  }, [items]);

  const filteredItems = useMemo(() => {
    const q = searchQuery.trim().toLowerCase();
    return items.filter((item) => {
      if (sourceFilter !== 'ALL' && item.sourceId !== sourceFilter) return false;
      if (categoryFilter !== 'ALL' && item.category !== categoryFilter) return false;
      const checked = Boolean(checksById[item.id]?.checked);
      if (checkStatusFilter === 'UNCHECKED' && checked) return false;
      if (checkStatusFilter === 'CHECKED' && !checked) return false;
      if (q) {
        const hay = [
          item.businessName,
          item.district ?? '',
          item.roadAddress ?? '',
          item.reasonSummary,
          item.categoryLabel,
          item.businessId ?? '',
        ]
          .join(' ')
          .toLowerCase();
        if (!hay.includes(q)) return false;
      }
      return true;
    });
  }, [items, sourceFilter, categoryFilter, checkStatusFilter, searchQuery, checksById]);

  const selectedItem = useMemo(() => {
    if (filteredItems.length === 0) return null;
    if (selectedId) {
      const match = filteredItems.find((it) => it.id === selectedId);
      if (match) return match;
    }
    return filteredItems[0];
  }, [filteredItems, selectedId]);

  const activeMemo =
    selectedItem && memoEditingId === selectedItem.id
      ? memoInput
      : selectedItem
        ? (checksById[selectedItem.id]?.memo ?? '')
        : '';

  const selectItem = (item: WeeklyDriftReviewItem) => {
    setSelectedId(item.id);
    setMemoEditingId(item.id);
    setMemoInput(checksById[item.id]?.memo ?? '');
  };

  const sourceTabs: Array<{ id: 'ALL' | 'mma' | 'ddc' | 'paju' | 'yangju'; label: string }> = [
    { id: 'ALL', label: '전체 출처' },
    { id: 'mma', label: '병무청' },
    { id: 'ddc', label: '동두천시' },
    { id: 'paju', label: '파주시' },
    { id: 'yangju', label: '양주시' },
  ];

  return (
    <div className="space-y-4">
      <div className="flex items-start gap-3 rounded-xl border border-amber-300 bg-amber-50 px-4 py-3.5 text-amber-950">
        <ShieldAlert className="mt-0.5 h-5 w-5 shrink-0 text-amber-800" />
        <div className="space-y-0.5">
          <div className="text-sm font-semibold">
            직접 확인이 필요합니다 — 공식 출처 주간 점검에서 변경·미관측·재확인으로 걸린 항목입니다.
          </div>
          <p className="text-xs text-amber-900">
            자동화는 정본을 임의로 수정하거나 종료하지 않습니다. 아래 항목의{' '}
            <span className="font-semibold">공식 출처 직접 확인 ↗</span> 및{' '}
            <span className="font-semibold">네이버 지도 확인 ↗</span> 링크를 열어 실제 내용을 확인한 뒤 확인 메모를 남기세요.
          </p>
        </div>
      </div>

      <Card className="p-3.5">
        <div className="flex flex-col gap-3 lg:flex-row lg:items-center lg:justify-between">
          <div className="flex flex-wrap gap-1.5">
            {sourceTabs.map((tab) => (
              <button
                key={tab.id}
                type="button"
                onClick={() => {
                  setSourceFilter(tab.id);
                  setSelectedId(null);
                }}
                className={`inline-flex items-center gap-1.5 rounded-lg px-3 py-1.5 text-xs font-medium transition cursor-pointer ${
                  sourceFilter === tab.id
                    ? 'bg-slate-900 text-white shadow-2xs'
                    : 'bg-slate-100 text-slate-700 hover:bg-slate-200'
                }`}
              >
                <span>{tab.label}</span>
                <span
                  className={`tabular-nums rounded px-1.5 py-0.2 text-[11px] ${
                    sourceFilter === tab.id ? 'bg-white/20 text-white' : 'bg-white text-slate-700'
                  }`}
                >
                  {sourceCounts[tab.id] ?? 0}
                </span>
              </button>
            ))}
          </div>

          <div className="flex flex-wrap items-center gap-2">
            <div className="relative min-w-[200px] flex-1">
              <Search className="pointer-events-none absolute top-2.5 left-2.5 h-4 w-4 text-slate-400" />
              <Input
                className="pl-8"
                placeholder="업소명, 주소, 사유 검색..."
                value={searchQuery}
                onChange={(e) => setSearchQuery(e.target.value)}
              />
            </div>
            <Select
              value={categoryFilter}
              onChange={(e) => setCategoryFilter(e.target.value as 'ALL' | WeeklyDriftReviewCategory)}
              aria-label="유형 필터"
            >
              <option value="ALL">전체 유형</option>
              <option value="CONTENT_CHANGED">내용 변경</option>
              <option value="MISSING_IN_OFFICIAL">공식목록 미관측/미발견</option>
              <option value="DETAIL_RECHECK">상세정보 재확인</option>
              <option value="ADDRESS_RECHECK">주소 재확인</option>
              <option value="ATTACHMENT_CHANGED">첨부파일 변경</option>
            </Select>
            <Select
              value={checkStatusFilter}
              onChange={(e) => setCheckStatusFilter(e.target.value as 'ALL' | 'UNCHECKED' | 'CHECKED')}
              aria-label="확인 여부 필터"
            >
              <option value="ALL">전체 상태</option>
              <option value="UNCHECKED">미확인</option>
              <option value="CHECKED">확인 완료</option>
            </Select>
          </div>
        </div>
      </Card>

      <div className="grid grid-cols-1 gap-4 xl:grid-cols-12">
        <div className="max-h-[70vh] space-y-2.5 overflow-y-auto pr-0.5 xl:col-span-5">
          {filteredItems.length === 0 ? (
            <Card className="p-8 text-center text-sm text-slate-500">
              {items.length === 0
                ? '주간 출처 점검에서 직접 확인이 필요한 변경·재확인 항목이 없습니다.'
                : '현재 필터 조건에 해당하는 항목이 없습니다.'}
            </Card>
          ) : (
            filteredItems.map((item) => {
              const isSelected = selectedItem?.id === item.id;
              const safeUrls = extractSafeUrls(null, item.sourceUrls);
              const checkEntry = checksById[item.id];
              return (
                <div
                  key={item.id}
                  role="button"
                  tabIndex={0}
                  onClick={() => selectItem(item)}
                  onKeyDown={(e) => {
                    if (e.key === 'Enter' || e.key === ' ') {
                      e.preventDefault();
                      selectItem(item);
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
                      <Badge tone={item.severity === 'red' ? 'red' : 'amber'}>직접 확인 필요</Badge>
                      <Badge tone="neutral">{item.sourceName}</Badge>
                      <Badge tone="neutral">{item.categoryLabel}</Badge>
                      {checkEntry?.checked && (
                        <Badge tone="emerald">
                          <CheckCircle2 className="h-3 w-3" />
                          확인됨
                        </Badge>
                      )}
                    </div>
                    {safeUrls[0] && (
                      <a
                        href={safeUrls[0]}
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
                  <div className="mt-2 font-semibold text-slate-900">{item.businessName}</div>
                  <div className="mt-0.5 text-xs text-slate-500">
                    {[item.district, item.roadAddress].filter(Boolean).join(' · ') || item.reasonSummary}
                  </div>
                  <div className="mt-1.5 text-xs text-amber-900">{item.reasonSummary}</div>
                </div>
              );
            })
          )}
        </div>

        <div className="xl:col-span-7">
          {selectedItem ? (
            <Card className="overflow-hidden">
              <CardHeader className="space-y-2 bg-slate-50/70">
                <div className="flex flex-wrap items-center justify-between gap-2">
                  <div className="flex flex-wrap items-center gap-1.5">
                    <Badge tone={selectedItem.severity === 'red' ? 'red' : 'amber'}>
                      직접 확인 필요 · {selectedItem.categoryLabel}
                    </Badge>
                    <Badge tone="neutral">{selectedItem.sourceName}</Badge>
                    {checksById[selectedItem.id]?.checked && <Badge tone="emerald">개발자 확인 완료</Badge>}
                  </div>
                  {selectedItem.canonicalRowNumber && (
                    <span className="font-mono text-xs text-slate-500">
                      정본 CSV {selectedItem.canonicalRowNumber}행
                    </span>
                  )}
                </div>
                <div>
                  <CardTitle className="text-lg font-bold text-slate-900">
                    {selectedItem.businessName}
                  </CardTitle>
                  <CardDescription className="mt-0.5 text-xs text-slate-600">
                    {[selectedItem.district, selectedItem.roadAddress].filter(Boolean).join(' · ') ||
                      '주소 정보 없음'}
                    {selectedItem.businessId ? ` · ${selectedItem.businessId}` : ''}
                  </CardDescription>
                </div>
              </CardHeader>

              <CardContent className="space-y-4">
                <div className="rounded-xl border border-amber-300 bg-amber-50/80 p-4">
                  <div className="flex items-start gap-2.5">
                    <AlertTriangle className="mt-0.5 h-4 w-4 shrink-0 text-amber-800" />
                    <div className="space-y-2">
                      <div className="text-sm font-semibold text-slate-900">
                        직접 확인이 필요합니다 — {selectedItem.reasonSummary}
                      </div>
                      <div className="flex flex-wrap gap-2 pt-1">
                        {extractSafeUrls(null, selectedItem.sourceUrls).map((url, idx, arr) => (
                          <a
                            key={url}
                            href={url}
                            target="_blank"
                            rel="noopener noreferrer"
                            className="inline-flex items-center gap-1.5 rounded-lg bg-slate-900 px-3 py-1.5 text-xs font-medium text-white shadow-xs transition hover:bg-slate-800"
                          >
                            <ExternalLink className="h-3.5 w-3.5" />
                            {arr.length > 1 ? `공식 출처 직접 확인 #${idx + 1}` : '공식 출처 직접 확인'}
                          </a>
                        ))}
                        {selectedItem.category !== 'ATTACHMENT_CHANGED' && (
                          <a
                            href={buildNaverMapSearchUrl(
                              selectedItem.businessName,
                              selectedItem.roadAddress,
                              selectedItem.district,
                            )}
                            target="_blank"
                            rel="noopener noreferrer"
                            className="inline-flex items-center gap-1.5 rounded-lg border border-slate-300 bg-white px-3 py-1.5 text-xs font-medium text-slate-800 shadow-2xs transition hover:bg-slate-50"
                          >
                            <MapPin className="h-3.5 w-3.5 text-emerald-700" />
                            네이버 지도에서 직접 확인
                          </a>
                        )}
                      </div>
                    </div>
                  </div>
                </div>

                <div className="grid grid-cols-1 gap-3 md:grid-cols-2">
                  <div className="rounded-lg border border-slate-200 bg-slate-50/70 p-3.5">
                    <div className="mb-1.5 text-xs font-semibold text-slate-700">현재 정본 데이터</div>
                    <p className="text-xs leading-relaxed text-slate-800">
                      {selectedItem.canonicalDetail || '세부 정보 없음'}
                    </p>
                  </div>
                  <div className="rounded-lg border border-amber-200 bg-amber-50/40 p-3.5">
                    <div className="mb-1.5 text-xs font-semibold text-amber-950">최신 공식 출처 관측</div>
                    <p className="text-xs leading-relaxed text-slate-900">
                      {selectedItem.officialDetail || '관측 정보 없음'}
                    </p>
                  </div>
                </div>

                <div className="space-y-2.5 border-t border-slate-200 pt-4">
                  <label className="text-xs font-semibold text-slate-700">
                    개발자 확인 메모 (브라우저 로컬 저장 · 정본 반영 전 참고용)
                  </label>
                  <Textarea
                    placeholder="공식 출처에서 확인한 결과(예: 10% -> 15% 인상 확인, 폐업 확인 등)를 적어두세요."
                    value={activeMemo}
                    onChange={(e) => {
                      setMemoEditingId(selectedItem.id);
                      setMemoInput(e.target.value);
                    }}
                  />
                  <div className="flex flex-wrap items-center justify-between gap-2">
                    {checksById[selectedItem.id]?.checked ? (
                      <Button
                        size="sm"
                        variant="ghost"
                        onClick={() => onClearCheck(selectedItem.id)}
                      >
                        확인 표시 해제
                      </Button>
                    ) : (
                      <span className="text-xs text-slate-500">
                        실제 정본 CSV 수정은 데이터 PR 절차로 반영합니다.
                      </span>
                    )}
                    <Button
                      size="sm"
                      onClick={() =>
                        onSaveCheck(selectedItem.id, {
                          checked: true,
                          memo: activeMemo.trim(),
                          checkedAt: new Date().toISOString(),
                        })
                      }
                    >
                      <CheckCircle2 className="h-3.5 w-3.5" />
                      직접 확인 완료로 표시
                    </Button>
                  </div>
                </div>
              </CardContent>
            </Card>
          ) : (
            <Card className="flex min-h-[360px] items-center justify-center p-8 text-sm text-slate-500">
              왼쪽 목록에서 항목을 선택하면 정본 vs 공식 출처 비교와 직접 확인 링크가 표시됩니다.
            </Card>
          )}
        </div>
      </div>
    </div>
  );
}
