# Phase 4 P4-3 Scanned Korean OCR Deferral (Option A) & Phase 4 Digital Closeout

- **Date:** 2026-11-20
- **Baseline:** `dev@e013e3b980d25318c50941ec13778b961ec02d18` (post PR [#162](https://github.com/jelleoo/MILIMAP/pull/162))
- **Related Issue:** [#125](https://github.com/jelleoo/MILIMAP/issues/125) (`Phase 4 P4-3: Evaluate bounded PaddleOCR Korean fidelity`)
- **Decision Scope:** Documentation closeout only (zero edits to code, canonical CSV, seed JSONs, Android app, or Room schema `v4`)

---

## 1. Decision Summary (Option A — Approved)

1. **Scanned Korean PDF OCR (`P4-3` / `P4-3B` / Issue [#125](https://github.com/jelleoo/MILIMAP/issues/125)) is formally DEFERRED out of current MVP scope.**
   - Current runtime policy: `OCR dependency = NOT_APPROVED`, `P4-3B = BLOCKED`, `ProductionAction = NONE`, `LiveHTTP = NOT_AUTHORIZED`.
2. **Phase 4 Digital Multi-Source Adapters are closed out as COMPLETE within their bounded contracts:**
   - `P4-0`: Document Adapter Foundation (PR #112)
   - `P4-1`: Bounded Native HWPX Adapter (`SCOPED_HWPX_CELL`, PR #114)
   - `P4-2B`: Bounded Native PDF Ruled-Grid Adapter (`.NET 8` isolated PdfPig `0.1.16`, `SCOPED_PDF_CELL`, Issue #117 / PR #118)
3. **Operational handling for scanned PDFs (`3.6%` of canonical data):**
   - Rare scanned PDF updates are handled via human manual transcription into canonical/review records, verified through `BenefitReleaseApprovalLedger` (`validate-benefit-release-approvals.ps1`, PR [#158](https://github.com/jelleoo/MILIMAP/pull/158)) and the PR-based governance rules in [`docs/data-policy.md`](../data-policy.md).

---

## 2. Canonical Population & Risk Justification (`496` Rows)

Direct inspection of `data/canonical/capital-area-military-benefits.csv` (`496` rows total) establishes that scanned PDFs are a small, bounded subset:

| Source Family / Host | Canonical Rows | Share | Current Coverage / Path |
| :--- | ---: | ---: | :--- |
| `지자체 공식 자료` (`www.paju.go.kr`) | 187 | 37.7% | Scoped HTML adapter + C-Lite `RAW=0` (PR #162) |
| `공공데이터` (`www.mma.go.kr`) | 159 | 32.1% | MMA JSONP list/detail adapter (`LEGACY` profile preserved) |
| `지자체 공식 자료` (`www.ddc.go.kr`) | 74 | 14.9% | Scoped HTML adapter + C-Lite `RAW=0` (PR #162) |
| `지자체 공식 자료` (`www.yangju.go.kr`) | 32 | 6.5% | BBS / XLSX scoped adapter (`LEGACY` profile preserved) |
| **Official Core Subtotal** | **452** | **91.1%** | **Covered by Phase 2~5 & C-Lite verification pipeline** |
| `지자체 공식 자료` (`www.suwon.go.kr` PDF) | 18 | 3.6% | Single file (`4e5d92bd-...pdf`); Native `P4-2B` or manual transcription + PR #158 ledger |
| Unofficial Web / SNS (`instagram`, `blog.naver`, `tripadvisor`, `daangn`) | 26 | 5.2% | Discovery-only (`Phase 6` scope) |
| **Total** | **496** | **100.0%** | — |

Introducing heavy multi-hundred-megabyte Python/PaddleOCR or native OCR runtimes into CI/local environments to automate at most 18 static PDF rows (`3.6%`) poses disproportionate maintenance, non-determinism, and binary supply risk compared to fail-closed human transcription under PR #158 approval ledger validation.

---

## 3. Preserved Historical OCR Rejection Records

All prior empirical OCR evaluation verdicts remain intact as permanent technical records (no threshold relaxation or synthetic rescue):

- **P4-3A (`REJECTED`, 2026-10-05):** Windows Tesseract 5.5.3 bounded Gray/RGB matrix (`16` OCR runs, `80` threshold checks) produced `0` usable positives (`PSM 3/4/6` containment failures; `PSM 11` same-cell bbox overlap). See [P4-3A handover](2026-10-05-phase4-p4-3a-ocr-technical-evaluation.md).
- **P4-3A2 (`P4_3A2_REJECTED`, 2026-10-05):** `GATE_A_CONFIDENCE_REJECTED`; mild degraded Gray failed from threshold `0` with `CONFLICTING` overlaps, proving confidence thresholds cannot separate unsafe Korean reconstructions. See [P4-3A2 handover](2026-10-05-phase4-p4-3a2-overlap-safety-evaluation.md).
- **P4-3 Redesign 2 (`P4_3_REDESIGN2_REJECTED`, 2026-10-06):** `GATE_A2_TEXT_FIDELITY_REJECTED`; structural `Gate A1` passed, but clear Gray/RGB matched only `6/8` mandatory cells (`주소` -> `즈 ㅅ\n구수`, `전화번호` -> `전 화 번 호`). See [Redesign 2 handover](2026-10-06-phase4-p4-3-redesign2-structural-trust-evaluation.md).
- **P4-3 Redesign 3A (`P4_3_REDESIGN3A_REJECTED`, 2026-10-09):** `GATE_C_CLEAR_FIDELITY_FAILED` on per-cell crops (`PSM 6`: `5/8` mandatory / `7/12` all cells; `PSM 11`: `6/8` mandatory / `8/12` all cells across Gray and RGB repeats). See [`tools/data/evaluation/p4-3-redesign3a-ocr/README.md`](../../tools/data/evaluation/p4-3-redesign3a-ocr/README.md).
- **P4-3 Redesign 3B (`P4_3_REDESIGN3B_REJECTED`, 2026-10-10 KST):** `GATE_B1_CLEAR_GRAY_FIDELITY_FAILED` with pinned `tessdata_best 4.1.0` (`PSM 6`: `5/8` mandatory / `7/12` all; `PSM 11`: `6/8` mandatory / `8/12` all; mandatory `주소` -> `즈 ㅅ\n수소` / `전화번호` -> `전 화 번호`). See [`tools/data/evaluation/p4-3-redesign3b-ocr/README.md`](../../tools/data/evaluation/p4-3-redesign3b-ocr/README.md).

---

## 4. Re-opening Criteria

Any future reconsideration of Korean OCR fallback (`P4-3` / `P4-3B`) requires:
1. A significant expansion of scanned image/PDF canonical rows beyond current `<= 18` rows where manual transcription becomes an operational bottleneck, AND
2. A new approved design spec & isolated supply/determinism/cell-fidelity evaluation proving `8/8` mandatory exact Korean cell fidelity without relaxing containment, overlap, or approval safety gates.
