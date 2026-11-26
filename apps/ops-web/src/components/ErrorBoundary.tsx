import { Component, type ErrorInfo, type ReactNode } from 'react';

interface ErrorBoundaryProps {
  children: ReactNode;
}

interface ErrorBoundaryState {
  hasError: boolean;
  errorMessage: string;
}

const OPS_STORAGE_KEYS = [
  'milimap_ops_approval_records_v1',
  'milimap_ops_approver_v1',
  'milimap_ops_drift_checks_v1',
];

export class ErrorBoundary extends Component<ErrorBoundaryProps, ErrorBoundaryState> {
  state: ErrorBoundaryState = {
    hasError: false,
    errorMessage: '',
  };

  static getDerivedStateFromError(error: Error): ErrorBoundaryState {
    return {
      hasError: true,
      errorMessage: error.message || '알 수 없는 화면 오류가 발생했습니다.',
    };
  }

  componentDidCatch(error: Error, info: ErrorInfo) {
    console.error('MILIMAP Ops Console ErrorBoundary caught error:', error, info);
  }

  private handleResetAndReload = () => {
    try {
      for (const key of OPS_STORAGE_KEYS) {
        localStorage.removeItem(key);
      }
    } catch {
      // Ignore storage errors when recovering.
    }
    window.location.reload();
  };

  render() {
    if (this.state.hasError) {
      return (
        <div className="flex min-h-screen items-center justify-center bg-slate-50 p-6 text-slate-900">
          <div className="w-full max-w-lg rounded-xl border border-red-200 bg-white p-6 shadow-sm">
            <h1 className="text-base font-semibold text-red-900">화면 렌더링 중 오류가 발생했습니다</h1>
            <p className="mt-2 text-xs text-slate-600">
              잘못 저장된 임시 데이터나 예기치 않은 JSON 형식으로 인해 화면을 표시할 수 없습니다.
            </p>
            <pre className="mt-3 overflow-x-auto rounded-lg bg-slate-100 p-3 text-[11px] text-slate-800">
              {this.state.errorMessage}
            </pre>
            <div className="mt-4 flex flex-wrap gap-2">
              <button
                type="button"
                onClick={() => window.location.reload()}
                className="rounded-lg border border-slate-300 bg-white px-3.5 py-2 text-xs font-medium text-slate-800 hover:bg-slate-50 cursor-pointer"
              >
                다시 불러오기
              </button>
              <button
                type="button"
                onClick={this.handleResetAndReload}
                className="rounded-lg bg-slate-900 px-3.5 py-2 text-xs font-medium text-white hover:bg-slate-800 cursor-pointer"
              >
                로컬 임시저장 초기화 후 새로고침
              </button>
            </div>
          </div>
        </div>
      );
    }

    return this.props.children;
  }
}
