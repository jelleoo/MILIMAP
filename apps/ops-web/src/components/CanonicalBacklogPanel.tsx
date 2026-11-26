import { useMemo, useState } from 'react';
import {
  CheckCircle2,
  ExternalLink,
  MapPin,
  Search,
  ShieldAlert,
} from 'lucide-react';
import { buildNaverMapSearchUrl, extractSafeUrls } from '../lib/safeUrl';
import type { CanonicalBacklogGroup, CanonicalBacklogItem, CanonicalBacklogSummary } from '../types/ops';
import type { DriftCheckEntry } from './DriftReviewPanel';
import { Badge, Button, Card, CardContent, CardDescription, CardHeader, CardTitle, Input, Select, Textarea } from './ui/primitives';

interface CanonicalBacklogPanelProps {
  summary: CanonicalBacklogSummary | null;
  items: CanonicalBacklogItem[];
  checksById: Record<string, DriftCheckEntry>;
  onSaveCheck: (id: string, entry: DriftCheckEntry) => void;
  onClearCheck: (id: string) => void;
}

export function CanonicalBacklogPanel({
  summary,
  items,
  checksById,
  onSaveCheck,
  onClearCheck,
}: CanonicalBacklogPanelProps) {
  const [groupFilter, setGroupFilter] = useState<'ALL' | CanonicalBacklogGroup>('ALL');
  const [regionFilter, setRegionFilter] = useState<string>('ALL');
  const [statusFilter, setStatusFilter] = useState<'ALL' | 'UNCHECKED' | 'CHECKED'>('ALL');
  const [searchQuery, setSearchQuery] = useState('');
  const [selectedId, setSelectedId] = useState<string | null>(null);
  const [memoInput, setMemoInput] = useState('');
  const [memoEditingId, setMemoEditingId] = useState<string | null>(null);

  const districts = useMemo(
    () => Array.from(new Set(items.map((it) => it.district).filter((d): d is string => Boolean(d)))).sort(),
    [items],
  );

  const filteredItems = useMemo(() => {
    const q = searchQuery.trim().toLowerCase();
    return items.filter((item) => {
      if (groupFilter !== 'ALL' && item.backlogGroup !== groupFilter) return false;
      if (regionFilter !== 'ALL' && item.district !== regionFilter) return false;
      const checked = Boolean(checksById[item.id]?.checked);
      if (statusFilter === 'UNCHECKED' && checked) return false;
      if (statusFilter === 'CHECKED' && !checked) return false;
      if (q) {
        const hay = [
          item.businessName,
          item.sido ?? '',
          item.district ?? '',
          item.roadAddress ?? '',
          item.reasonDetail,
          item.sourceType ?? '',
          item.businessId ?? '',
        ]
          .join(' ')
          .toLowerCase();
        if (!hay.includes(q)) return false;
      }
      return true;
    });
  }, [items, groupFilter, regionFilter, statusFilter, searchQuery, checksById]);

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

  const groupTabs: Array<{ id: 'ALL' | CanonicalBacklogGroup; label: string; count: number }> = [
    { id: 'ALL', label: '전체', count: summary?.TotalBacklogCount ?? items.length },
    {
      id: 'UNPINNED_IN_APP',
      label: '지도 핀 미확정',
      count: summary?.UnpinnedInAppCount ?? items.filter((i) => i.backlogGroup === 'UNPINNED_IN_APP').length,
    },
    {
      id: 'COORD_RECHECK',
      label: '좌표 재확인 필요',
      count: summary?.CoordRecheckCount ?? items.filter((i) => i.backlogGroup === 'COORD_RECHECK').length,
    },
    {
      id: 'OUTDATED_OR_OCR',
      label: '공고 재확인·OCR 보류',
      count: summary?.OutdatedOrOcrCount ?? items.filter((i) => i.backlogGroup === 'OUTDATED_OR_OCR').length,
    },
    {
      id: 'UNOFFICIAL_SOURCE',
      label: '비공식 출처',
      count: summary?.UnofficialSourceCount ?? items.filter((i) => i.backlogGroup === 'UNOFFICIAL_SOURCE').length,
    },
  ];

  return (
    <div className="space-y-4">
      <div className="flex items-start gap-3 rounded-xl border border-amber-300 bg-amber-50 px-4 py-3.5 text-amber-950">
        <ShieldAlert className="mt-0.5 h-5 w-5 shrink-0 text-amber-800" />
        <div className="space-y-0.5">
          <div className="text-sm font-semibold">
            직접 확인이 필요합니다 — 현재 앱 지도에 마커를 띄우지 않았거나 배포가 보류된 정본 데이터입니다.
          </div>
          <p className="text-xs text-amber-900">
            정본 전체({summary?.CanonicalTotalCount?.toLocaleString() ?? '-'}곳) 중{' '}
            <span className="font-semibold">지도 핀 미확정({summary?.UnpinnedInAppCount ?? 0}곳)</span>과{' '}
            <span className="font-semibold">배포 보류({summary?.HeldCount ?? 0}곳)</span> 항목입니다. 아래 링크로 공식 출처와 실제 위치를 확인해 보강할 수 있습니다.
          </p>
        </div>
      </div>

      <Card className="p-3.5">
        <div className="flex flex-col gap-3 lg:flex-row lg:items-center lg:justify-between">
          <div className="flex flex-wrap gap-1.5">
            {groupTabs.map((tab) => (
              <button
                key={tab.id}
                type="button"
                onClick={() => {
                  setGroupFilter(tab.id);
                  setSelectedId(null);
                }}
                className={`inline-flex items-center gap-1.5 rounded-lg px-3 py-1.5 text-xs font-medium transition cursor-pointer ${
                  groupFilter === tab.id
                    ? 'bg-slate-900 text-white shadow-2xs'
                    : 'bg-slate-100 text-slate-700 hover:bg-slate-200'
                }`}
              >
                <span>{tab.label}</span>
                <span
                  className={`tabular-nums rounded px-1.5 py-0.2 text-[11px] ${
                    groupFilter === tab.id ? 'bg-white/20 text-white' : 'bg-white text-slate-700'
                  }`}
                >
                  {tab.count}
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
            <Select value={regionFilter} onChange={(e) => setRegionFilter(e.target.value)} aria-label="시군구 필터">
              <option value="ALL">전체 시군구</option>
              {districts.map((dist) => (
                <option key={dist} value={dist}>
                  {dist}
                </option>
              ))}
            </Select>
            <Select
              value={statusFilter}
              onChange={(e) => setStatusFilter(e.target.value as 'ALL' | 'UNCHECKED' | 'CHECKED')}
              aria-label="확인 상태 필터"
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
                ? '미배포·좌표 미확정 정본 백로그 데이터가 없습니다.'
                : '필터 조건에 해당하는 항목이 없습니다.'}
            </Card>
          ) : (
            filteredItems.map((item) => {
              const isSelected = selectedItem?.id === item.id;
              const checkEntry = checksById[item.id];
              const firstUrl = extractSafeUrls(null, item.sourceUrls)[0];
              return (
                <div
                  key={item.id}
                  role="button"
                  tabIndex={0}
                  onClick={() => {
                    setSelectedId(item.id);
                    setMemoEditingId(item.id);
                    setMemoInput(checksById[item.id]?.memo ?? '');
                  }}
                  onKeyDown={(e) => {
                    if (e.key === 'Enter' || e.key === ' ') {
                      e.preventDefault();
                      setSelectedId(item.id);
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
                      <Badge tone={item.severity === 'red' ? 'red' : 'amber'}>{item.backlogLabel}</Badge>
                      {checkEntry?.checked && (
                        <Badge tone="emerald">
                          <CheckCircle2 className="h-3 w-3" />
                          확인됨
                        </Badge>
                      )}
                    </div>
                    {firstUrl && (
                      <a
                        href={firstUrl}
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
                    {[item.district, item.roadAddress].filter(Boolean).join(' · ') || '주소 없음'}
                  </div>
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
                      직접 확인 필요 · {selectedItem.backlogLabel}
                    </Badge>
                    {selectedItem.sourceType && <Badge tone="neutral">{selectedItem.sourceType}</Badge>}
                    {checksById[selectedItem.id]?.checked && <Badge tone="emerald">개발자 확인 완료</Badge>}
                  </div>
                  {selectedItem.canonicalRowNumber && (
                    <span className="font-mono text-xs text-slate-500">
                      정본 CSV {selectedItem.canonicalRowNumber}행
                    </span>
                  )}
                </div>
                <div>
                  <CardTitle className="text-lg font-bold text-slate-900">{selectedItem.businessName}</CardTitle>
                  <CardDescription className="mt-0.5 text-xs text-slate-600">
                    {[selectedItem.sido, selectedItem.district, selectedItem.roadAddress].filter(Boolean).join(' · ') ||
                      '주소 정보 없음'}
                  </CardDescription>
                </div>
              </CardHeader>

              <CardContent className="space-y-4">
                <div className="rounded-xl border border-amber-300 bg-amber-50/80 p-4">
                  <div className="space-y-2">
                    <div className="text-sm font-semibold text-slate-900">
                      직접 확인이 필요합니다 — {selectedItem.reasonDetail}
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
                          {arr.length > 1 ? `출처/위치 링크 직접 확인 #${idx + 1}` : '공식 출처 직접 확인'}
                        </a>
                      ))}
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
                        네이버 지도에서 위치 확인
                      </a>
                    </div>
                  </div>
                </div>

                <dl className="grid grid-cols-1 gap-2.5 rounded-lg border border-slate-200 bg-slate-50/70 p-3.5 text-xs sm:grid-cols-2">
                  <div>
                    <dt className="text-slate-500">업종</dt>
                    <dd className="mt-0.5 font-medium text-slate-900">{selectedItem.category || '-'}</dd>
                  </div>
                  <div>
                    <dt className="text-slate-500">할인 정보</dt>
                    <dd className="mt-0.5 font-medium text-slate-900">{selectedItem.benefitDescription || '-'}</dd>
                  </div>
                  <div>
                    <dt className="text-slate-500">혜택 상태 / 좌표 검증</dt>
                    <dd className="mt-0.5 font-medium text-slate-900">
                      {selectedItem.benefitStatus || '-'} / {selectedItem.coordStatus || '-'}
                    </dd>
                  </div>
                  <div>
                    <dt className="text-slate-500">최근 확인일</dt>
                    <dd className="mt-0.5 font-medium text-slate-900">{selectedItem.lastVerifiedAt || '-'}</dd>
                  </div>
                </dl>

                <div className="space-y-2.5 border-t border-slate-200 pt-4">
                  <label className="text-xs font-semibold text-slate-700">보강 확인 메모 (로컬 저장)</label>
                  <Textarea
                    placeholder="좌표 확인 결과, 실제 영업 여부, 공식 출처 확인 내용을 기록하세요."
                    value={activeMemo}
                    onChange={(e) => {
                      setMemoEditingId(selectedItem.id);
                      setMemoInput(e.target.value);
                    }}
                  />
                  <div className="flex flex-wrap items-center justify-between gap-2">
                    {checksById[selectedItem.id]?.checked ? (
                      <Button size="sm" variant="ghost" onClick={() => onClearCheck(selectedItem.id)}>
                        확인 표시 해제
                      </Button>
                    ) : (
                      <span className="text-xs text-slate-500">확인된 항목은 다음 데이터 확장 릴리스 컷에 반영합니다.</span>
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
              왼쪽 목록에서 항목을 선택하면 상세 정보와 직접 확인 링크가 표시됩니다.
            </Card>
          )}
        </div>
      </div>
    </div>
  );
}
