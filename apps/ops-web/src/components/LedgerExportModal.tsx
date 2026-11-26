import { useState } from 'react';
import { Check, Copy, Download, X } from 'lucide-react';
import { buildApprovalLedger, buildValidateLedgerCommand } from '../lib/approvalLedger';
import type { BenefitReleaseApprovalRecord } from '../types/ops';
import { Badge, Button, Card, CardContent, CardDescription, CardHeader, CardTitle } from './ui/primitives';

interface LedgerExportModalProps {
  open: boolean;
  records: BenefitReleaseApprovalRecord[];
  onClose: () => void;
  onClearAll: () => void;
}

export function LedgerExportModal({ open, records, onClose, onClearAll }: LedgerExportModalProps) {
  const [copiedCmd, setCopiedCmd] = useState(false);
  const [copiedJson, setCopiedJson] = useState(false);

  if (!open) return null;

  const ledger = buildApprovalLedger(records);
  const jsonText = JSON.stringify(ledger, null, 2);
  const cmdText = buildValidateLedgerCommand('benefit-release-approval-ledger.json');

  const handleDownload = () => {
    const blob = new Blob([jsonText], { type: 'application/json;charset=utf-8' });
    const url = URL.createObjectURL(blob);
    const anchor = document.createElement('a');
    anchor.href = url;
    anchor.download = 'benefit-release-approval-ledger.json';
    anchor.click();
    URL.revokeObjectURL(url);
  };

  const handleCopy = async (text: string, which: 'cmd' | 'json') => {
    await navigator.clipboard.writeText(text);
    if (which === 'cmd') {
      setCopiedCmd(true);
      setTimeout(() => setCopiedCmd(false), 1800);
    } else {
      setCopiedJson(true);
      setTimeout(() => setCopiedJson(false), 1800);
    }
  };

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-slate-950/45 p-4 backdrop-blur-[1px]">
      <Card className="flex max-h-[90vh] w-full max-w-3xl flex-col overflow-hidden shadow-xl">
        <CardHeader className="flex-row items-center justify-between">
          <div>
            <div className="flex items-center gap-2">
              <CardTitle className="text-base">승인 원장 내보내기 (`BenefitReleaseApprovalLedger` v1)</CardTitle>
              <Badge tone="blue">{records.length}건</Badge>
            </div>
            <CardDescription>
              `tools/data/validate-benefit-release-approvals.ps1` 계약과 100% 호환되는 JSON을 내려받아 검증을 실행하세요.
            </CardDescription>
          </div>
          <Button variant="ghost" size="sm" onClick={onClose} aria-label="닫기">
            <X className="h-4 w-4" />
          </Button>
        </CardHeader>

        <CardContent className="space-y-4 overflow-y-auto">
          <div className="space-y-1.5">
            <div className="flex items-center justify-between">
              <span className="text-xs font-semibold text-slate-700">1. PowerShell 검증기 실행 명령</span>
              <Button size="sm" variant="outline" onClick={() => handleCopy(cmdText, 'cmd')}>
                {copiedCmd ? <Check className="h-3.5 w-3.5 text-emerald-700" /> : <Copy className="h-3.5 w-3.5" />}
                {copiedCmd ? '복사됨' : '명령 복사'}
              </Button>
            </div>
            <pre className="overflow-x-auto rounded-lg bg-slate-900 p-3 text-xs text-slate-100">{cmdText}</pre>
          </div>

          <div className="space-y-1.5">
            <div className="flex items-center justify-between">
              <span className="text-xs font-semibold text-slate-700">2. 원장 JSON 미리보기</span>
              <Button size="sm" variant="outline" onClick={() => handleCopy(jsonText, 'json')}>
                {copiedJson ? <Check className="h-3.5 w-3.5 text-emerald-700" /> : <Copy className="h-3.5 w-3.5" />}
                {copiedJson ? '복사됨' : 'JSON 복사'}
              </Button>
            </div>
            <pre className="max-h-72 overflow-auto rounded-lg border border-slate-200 bg-slate-50 p-3 font-mono text-xs text-slate-800">
              {jsonText}
            </pre>
          </div>

          <div className="flex flex-wrap items-center justify-between gap-2 border-t border-slate-100 pt-3">
            <Button variant="ghost" size="sm" disabled={records.length === 0} onClick={onClearAll}>
              작성된 원장 전체 비우기
            </Button>
            <div className="flex gap-2">
              <Button variant="outline" onClick={onClose}>
                닫기
              </Button>
              <Button disabled={records.length === 0} onClick={handleDownload}>
                <Download className="h-4 w-4" />
                JSON 파일 다운로드
              </Button>
            </div>
          </div>
        </CardContent>
      </Card>
    </div>
  );
}
