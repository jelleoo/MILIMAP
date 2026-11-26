import { useMemo, useState } from 'react';
import {
  CheckCircle2,
  ExternalLink,
  MapPin,
  PlusCircle,
  Search,
} from 'lucide-react';
import { buildNaverMapSearchUrl, extractSafeUrls } from '../lib/safeUrl';
import type { WeeklyDriftNewCandidate } from '../types/ops';
import type { DriftCheckEntry } from './DriftReviewPanel';
import { Badge, Button, Card, CardContent, CardDescription, CardHeader, CardTitle, Input, Select, Textarea } from './ui/primitives';

interface NewCandidatesPanelProps {
  items: WeeklyDriftNewCandidate[];
  checksById: Record<string, DriftCheckEntry>;
  onSaveCheck: (id: string, entry: DriftCheckEntry) => void;
  onClearCheck: (id: string) => void;
}

export function NewCandidatesPanel({
  items,
  checksById,
  onSaveCheck,
  onClearCheck,
}: NewCandidatesPanelProps) {
  const [categoryFilter, setCategoryFilter] = useState<string>('ALL');
  const [officeFilter, setOfficeFilter] = useState<string>('ALL');
  const [statusFilter, setStatusFilter] = useState<'ALL' | 'UNCHECKED' | 'CHECKED'>('ALL');
  const [searchQuery, setSearchQuery] = useState('');
  const [selectedId, setSelectedId] = useState<string | null>(null);
  const [memoInput, setMemoInput] = useState('');
  const [memoEditingId, setMemoEditingId] = useState<string | null>(null);

  const categories = useMemo(
    () => Array.from(new Set(items.map((it) => it.category).filter(Boolean))).sort(),
    [items],
  );
  const offices = useMemo(
    () => Array.from(new Set(items.map((it) => it.regionalOffice).filter(Boolean))).sort(),
    [items],
  );

  const filteredItems = useMemo(() => {
    const q = searchQuery.trim().toLowerCase();
    return items.filter((item) => {
      if (categoryFilter !== 'ALL' && item.category !== categoryFilter) return false;
      if (officeFilter !== 'ALL' && item.regionalOffice !== officeFilter) return false;
      const checked = Boolean(checksById[item.id]?.checked);
      if (statusFilter === 'UNCHECKED' && checked) return false;
      if (statusFilter === 'CHECKED' && !checked) return false;
      if (q) {
        const hay = [
          item.businessName,
          item.roadAddress,
          item.category,
          item.regionalOffice,
          item.institutionCode,
        ]
          .join(' ')
          .toLowerCase();
        if (!hay.includes(q)) return false;
      }
      return true;
    });
  }, [items, categoryFilter, officeFilter, statusFilter, searchQuery, checksById]);

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

  const selectItem = (item: WeeklyDriftNewCandidate) => {
    setSelectedId(item.id);
    setMemoEditingId(item.id);
    setMemoInput(checksById[item.id]?.memo ?? '');
  };

  return (
    <div className="space-y-4">
      <div className="flex items-start gap-3 rounded-xl border border-blue-200 bg-blue-50/80 px-4 py-3.5 text-blue-950">
        <PlusCircle className="mt-0.5 h-5 w-5 shrink-0 text-blue-700" />
        <div className="space-y-0.5">
          <div className="text-sm font-semibold">
            신규 추가 후보 ({items.length}곳) — 공식 목록에 새로 포착되었지만 아직 우리 앱 정본에 없는 매장입니다.
          </div>
          <p className="text-xs text-blue-900">
            직접 확인이 필요합니다 — 아래 링크로 실제 매장 위치·영업 여부와 혜택 내용을 확인한 뒤 다음 데이터 확장에 포함할 수 있습니다.
          </p>
        </div>
      </div>

      <Card className="p-3.5">
        <div className="flex flex-wrap items-center gap-2">
          <div className="relative min-w-[220px] flex-1">
            <Search className="pointer-events-none absolute top-2.5 left-2.5 h-4 w-4 text-slate-400" />
            <Input
              className="pl-8"
              placeholder="업소명, 주소, 업종, 관할 병무청 검색..."
              value={searchQuery}
              onChange={(e) => setSearchQuery(e.target.value)}
            />
          </div>
          <Select value={categoryFilter} onChange={(e) => setCategoryFilter(e.target.value)} aria-label="업종 필터">
            <option value="ALL">전체 업종</option>
            {categories.map((cat) => (
              <option key={cat} value={cat}>
                {cat}
              </option>
            ))}
          </Select>
          <Select value={officeFilter} onChange={(e) => setOfficeFilter(e.target.value)} aria-label="관할 청 필터">
            <option value="ALL">전체 관할 청</option>
            {offices.map((off) => (
              <option key={off} value={off}>
                {off}
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
      </Card>

      <div className="grid grid-cols-1 gap-4 xl:grid-cols-12">
        <div className="max-h-[70vh] space-y-2.5 overflow-y-auto pr-0.5 xl:col-span-5">
          {filteredItems.length === 0 ? (
            <Card className="p-8 text-center text-sm text-slate-500">
              {items.length === 0
                ? '공식 사이트 자동 점검 파일이 연결되면 신규 추가 후보 목록이 여기에 표시됩니다.'
                : '검색 조건에 해당하는 신규 후보가 없습니다.'}
            </Card>
          ) : (
            filteredItems.map((item) => {
              const isSelected = selectedItem?.id === item.id;
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
                      <Badge tone="blue">신규 추가 후보</Badge>
                      {item.category && <Badge tone="neutral">{item.category}</Badge>}
                      {checkEntry?.checked && (
                        <Badge tone="emerald">
                          <CheckCircle2 className="h-3 w-3" />
                          확인됨
                        </Badge>
                      )}
                    </div>
                    <span className="font-mono text-[11px] text-slate-400">cd={item.institutionCode || '-'}</span>
                  </div>
                  <div className="mt-2 font-semibold text-slate-900">{item.businessName}</div>
                  <div className="mt-0.5 text-xs text-slate-500">{item.roadAddress || '주소 없음'}</div>
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
                    <Badge tone="blue">신규 추가 후보</Badge>
                    <Badge tone="neutral">{selectedItem.sourceName}</Badge>
                    {selectedItem.category && <Badge tone="neutral">{selectedItem.category}</Badge>}
                    {checksById[selectedItem.id]?.checked && <Badge tone="emerald">개발자 확인 완료</Badge>}
                  </div>
                  <span className="font-mono text-xs text-slate-500">기관코드: {selectedItem.institutionCode || '-'}</span>
                </div>
                <div>
                  <CardTitle className="text-lg font-bold text-slate-900">{selectedItem.businessName}</CardTitle>
                  <CardDescription className="mt-0.5 text-xs text-slate-600">
                    {selectedItem.roadAddress || '주소 정보 없음'}
                  </CardDescription>
                </div>
              </CardHeader>

              <CardContent className="space-y-4">
                <div className="rounded-xl border border-amber-300 bg-amber-50/80 p-4">
                  <div className="space-y-2">
                    <div className="text-sm font-semibold text-slate-900">
                      직접 확인이 필요합니다 — 앱에 새로 추가하기 전 실제 매장 위치와 운영 여부를 확인해 주세요.
                    </div>
                    <div className="flex flex-wrap gap-2 pt-1">
                      {extractSafeUrls(null, selectedItem.sourceUrls).map((url) => (
                        <a
                          key={url}
                          href={url}
                          target="_blank"
                          rel="noopener noreferrer"
                          className="inline-flex items-center gap-1.5 rounded-lg bg-slate-900 px-3 py-1.5 text-xs font-medium text-white shadow-xs transition hover:bg-slate-800"
                        >
                          <ExternalLink className="h-3.5 w-3.5" />
                          공식 출처 직접 확인
                        </a>
                      ))}
                      <a
                        href={buildNaverMapSearchUrl(selectedItem.businessName, selectedItem.roadAddress)}
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

                <dl className="grid grid-cols-1 gap-2 rounded-lg border border-slate-200 bg-slate-50/70 p-3.5 text-xs sm:grid-cols-2">
                  <div>
                    <dt className="text-slate-500">업종</dt>
                    <dd className="mt-0.5 font-medium text-slate-900">{selectedItem.category || '-'}</dd>
                  </div>
                  <div>
                    <dt className="text-slate-500">전화번호</dt>
                    <dd className="mt-0.5 font-medium text-slate-900">{selectedItem.phone || '-'}</dd>
                  </div>
                  <div>
                    <dt className="text-slate-500">관할 병무청</dt>
                    <dd className="mt-0.5 font-medium text-slate-900">{selectedItem.regionalOffice || '-'}</dd>
                  </div>
                  <div>
                    <dt className="text-slate-500">현재 정본 상태</dt>
                    <dd className="mt-0.5 font-medium text-amber-800">미등록 (데이터 확장 대상)</dd>
                  </div>
                </dl>

                <div className="space-y-2.5 border-t border-slate-200 pt-4">
                  <label className="text-xs font-semibold text-slate-700">추가 검토 메모 (로컬 저장)</label>
                  <Textarea
                    placeholder="영업 확인 결과나 좌표 보강 필요 여부를 적어두세요."
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
                      <span className="text-xs text-slate-500">실제 반영은 데이터 확장 스크립트·PR로 진행합니다.</span>
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
                      추가 후보 확인 완료로 표시
                    </Button>
                  </div>
                </div>
              </CardContent>
            </Card>
          ) : (
            <Card className="flex min-h-[360px] items-center justify-center p-8 text-sm text-slate-500">
              왼쪽 목록에서 신규 후보 매장을 선택하면 상세 정보와 직접 확인 링크가 표시됩니다.
            </Card>
          )}
        </div>
      </div>
    </div>
  );
}
