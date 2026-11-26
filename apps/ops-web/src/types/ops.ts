export type OperatorBucket = 'DOMAIN_REVIEW' | 'FAST_REVIEW' | 'DIAGNOSTIC_HOLD';
export type ReviewDomain = 'BENEFIT' | 'LOCATION';
export type BenefitDecision = 'APPROVE_ACTIVE' | 'HOLD_NEEDS_VERIFICATION' | 'APPROVE_ENDED';
export type CoordinateDecision = 'KEEP_PIN' | 'SUPPRESS_PIN';

export interface BenefitReleaseSeedManifest {
  manifestVersion: number;
  seedName: string;
  seedVersion: number;
  hashAlgorithm: string;
  generatedAt: string;
  canonicalCsvSha256: string;
  totalCount: number;
  exactPinCount: number;
  unconfirmedCoordinateCount: number;
  seedSha256: string;
  manualSeedCount: number;
  manualSeedSha256: string;
}

export interface WeeklyDriftSource {
  id: string;
  name: string;
  status: string;
  officialCount: number | null;
  canonicalCount: number | null;
  detail: string;
  error: string;
}

export type WeeklyDriftReviewCategory =
  | 'CONTENT_CHANGED'
  | 'MISSING_IN_OFFICIAL'
  | 'DETAIL_RECHECK'
  | 'ADDRESS_RECHECK'
  | 'ATTACHMENT_CHANGED';

export interface WeeklyDriftReviewItem {
  id: string;
  sourceId: string;
  sourceName: string;
  category: WeeklyDriftReviewCategory;
  categoryLabel: string;
  severity: 'amber' | 'red';
  businessId?: string | null;
  canonicalRowNumber?: number | null;
  businessName: string;
  district?: string | null;
  roadAddress?: string | null;
  reasonSummary: string;
  canonicalDetail?: string | null;
  officialDetail?: string | null;
  sourceUrls: string[];
}

export interface WeeklyDriftNewCandidate {
  id: string;
  sourceId: string;
  sourceName: string;
  institutionCode: string;
  businessName: string;
  roadAddress: string;
  phone: string;
  category: string;
  regionalOffice: string;
  sourceUrls: string[];
}

export interface WeeklyBenefitDriftSummary {
  contractType: 'WeeklyBenefitDriftSummary';
  contractVersion: number;
  generatedAtUtc: string;
  canonicalRowCount: number;
  automaticCanonicalMutation: boolean;
  productionAction?: string;
  sources: WeeklyDriftSource[];
  reviewItems?: WeeklyDriftReviewItem[];
  newCandidates?: WeeklyDriftNewCandidate[];
}

export type CanonicalBacklogGroup =
  | 'UNPINNED_IN_APP'
  | 'COORD_RECHECK'
  | 'OUTDATED_OR_OCR'
  | 'UNOFFICIAL_SOURCE';

export interface CanonicalBacklogItem {
  id: string;
  backlogGroup: CanonicalBacklogGroup;
  backlogLabel: string;
  severity: 'amber' | 'red';
  businessId?: string | null;
  canonicalRowNumber?: number | null;
  businessName: string;
  sido?: string | null;
  district?: string | null;
  roadAddress?: string | null;
  category?: string | null;
  benefitDescription?: string | null;
  sourceType?: string | null;
  benefitStatus?: string | null;
  coordStatus?: string | null;
  lastVerifiedAt?: string | null;
  reasonDetail: string;
  sourceUrls: string[];
}

export interface CanonicalBacklogSummary {
  CanonicalTotalCount: number;
  SeedActiveCount: number;
  ExactPinCount: number;
  UnpinnedInAppCount: number;
  HeldCount: number;
  CoordRecheckCount: number;
  OutdatedOrOcrCount: number;
  UnofficialSourceCount: number;
  TotalBacklogCount: number;
}

export interface CanonicalBacklog {
  Summary: CanonicalBacklogSummary;
  Items: CanonicalBacklogItem[];
}

export interface ValidatedClaimSummary {
  ClaimType?: string;
  Value?: string | null;
  EvidenceText?: string | null;
  EvidenceReference?: string | null;
  SourceUrl?: string | null;
}

export interface ReviewQueueSummary {
  CommittedRunCount?: number;
  CommittedObservationCount?: number;
  CommittedComparisonCount?: number;
  IgnoredUncommittedRecordCount?: number;
  DomainFilter?: string;
  IncludeSuperseded?: boolean;
  SupersededExcludedCount?: number;
  ExportedItemCount: number;
  FastReviewCount: number;
  DomainReviewCount: number;
  DiagnosticHoldCount: number;
  BenefitItemCount: number;
  LocationItemCount: number;
  ApprovalRequired: boolean;
  ProductionAction: string;
}

export interface ReviewQueueItem {
  OperatorBucket: OperatorBucket;
  BusinessId: string;
  CanonicalRowNumber?: number | null;
  BusinessName?: string | null;
  District?: string | null;
  RoadAddress?: string | null;
  CanonicalBenefitStatus?: string | null;
  CanonicalCoordinateStatus?: string | null;
  CanonicalSourceUrl?: string | null;
  CanonicalLastVerifiedAt?: string | null;
  Domain: ReviewDomain;
  ReviewKey: string;
  RunId: string;
  ObservedAt?: string | null;
  CurrentObservationId: string;
  PreviousObservationId?: string | null;
  ComparisonId?: string | null;
  ReviewRoute: string;
  OperationalStatus: string;
  Comparable: boolean;
  SemanticProjectionAvailable?: boolean;
  DeltaDimensions?: string[];
  ChangeCandidates?: string[];
  ReasonCodes?: string[];
  AuditFlags?: string[];
  DiagnosticReasons?: string[];
  BenefitState?: string | null;
  ReviewClass?: string | null;
  BusinessPresence?: string | null;
  AbsenceEligible?: boolean | null;
  ValidatedClaims?: ValidatedClaimSummary[];
  SourceUrls?: string[];
  SourceFormats?: string[];
  SourceContentHashes?: string[];
  SourceLocationStatuses?: string[];
  LocationEvaluationStatus?: string | null;
  LocationClassification?: string | null;
  LocationSelectionStatus?: string | null;
  LocationSelectedLatitude?: number | null;
  LocationSelectedLongitude?: number | null;
  MaterialReasonCodes?: string[];
  ConflictCodes?: string[];
  ApprovalRequired?: boolean;
  ProductionAction: string;
}

export interface Phase5ReviewQueueExport {
  ContractType: 'Phase5ReviewQueueExport';
  ContractVersion: number;
  ExportedAt: string;
  Summary: ReviewQueueSummary;
  Items: ReviewQueueItem[];
}

export interface OpsDashboardSnapshot {
  ContractType: 'OpsDashboardSnapshot';
  ContractVersion: number;
  GeneratedAtUtc: string;
  ProductionAction: 'NONE' | string;
  SeedBaseline: BenefitReleaseSeedManifest;
  WeeklyDrift: WeeklyBenefitDriftSummary | null;
  ReviewQueue: Phase5ReviewQueueExport | null;
  CanonicalBacklog?: CanonicalBacklog | null;
}

export interface BenefitReleaseApprovalRecord {
  businessId: string;
  canonicalRowNumber?: number;
  reviewKey: string;
  targetRunId: string;
  observationId: string;
  locationObservationId?: string;
  benefitDecision: BenefitDecision;
  coordinateDecision: CoordinateDecision;
  verifiedSourceUrl: string;
  verifiedOn: string;
  approvedBy: string;
  approvedAt: string;
  rationale: string;
}

export interface BenefitReleaseApprovalLedger {
  ContractType: 'BenefitReleaseApprovalLedger';
  ContractVersion: 1;
  Records: BenefitReleaseApprovalRecord[];
}
