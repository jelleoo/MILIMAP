# Android Core Baseline Integration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace only MILIMAP's `apps/android` baseline with the exact MiliPercent Room/Repository/ViewModel implementation while keeping the monorepo, CI location, provenance, rollback point, and a buildable application.

**Architecture:** MiliPercent provides the complete Android Core baseline at one pinned commit. MILIMAP keeps its repository root and collaboration infrastructure. This phase establishes Room as the sole local database and deliberately defers Naver Map, location, 484-row data reconciliation, login, favorites, and product UI integration.

**Tech Stack:** Kotlin, Jetpack Compose, Room 2.8.4, Navigation Compose 2.9.8, AGP 9.3.1, Gradle 9.5.0, JDK 17 runtime, Java 11 bytecode target, PowerShell, GitHub Actions

**Spec:** `docs/superpowers/specs/2026-08-22-android-room-integration-design.md`

## Global Constraints

- Do not execute Task 1 until `docs/adr/0001-android-room-integration.md` is merged into `dev` with status `Accepted` and Issue #4 records team approval.
- Use MILIMAP source baseline `dev@8e7b47a285f742faaa8d527fa34e31905de575e6` for Android behavior comparison; create the integration branch from the latest `dev` after the documentation PR merges.
- Import MiliPercent only from `main@5e3d7331d59979e172a67921fb45acedde11da26`.
- Keep `com.example.milipercent`, compile/target SDK 37, min SDK 24, Gradle 9.5.0, AGP 9.3.1, JDK 17 runtime, and Java 11 compile target unchanged in this phase.
- Never import `.git`, `.idea`, `.gradle`, root `build`, `app/build`, or `local.properties` as tracked source from MiliPercent. The already-configured `local.properties` may be copied afterward as an ignored local-only build input.
- Never use `git merge --allow-unrelated-histories`, retain SQLiteOpenHelper beside Room, or retain AppController beside the MiliPercent ViewModels.
- Keep MILIMAP root `.github`, `data`, `docs`, `infra`, `packages`, `services`, and `tools` except for the exact documentation updates named below.
- Do not add Naver Map, location permissions, the 484-row Seed, login, favorites, Firebase, package rename, or UI redesign in this plan.
- Do not push secrets. Repository examples contain placeholders only.
- Every product-code commit must pass `lintDebug`, `testDebugUnitTest`, and `assembleDebug` before review.

---

### Task 1: Accept the architecture and establish rollback points

**Files:**
- Modify through the documentation PR: `docs/adr/0001-android-room-integration.md`
- Reference: `docs/superpowers/specs/2026-08-22-android-room-integration-design.md`
- No Android product files

**Interfaces:**
- Consumes: Issue #4 approval and merged documentation PR SHA
- Produces: accepted architecture, immutable pre-integration tag, shared integration branch

- [ ] **Step 1: Confirm the approval gate**

Open Issue #4 and the documentation PR. Verify that another team member approved the architecture, the ADR status is exactly `Accepted`, and the documentation PR is merged into `dev`.

Expected: all three conditions are true. If any condition is false, stop without creating the integration branch.

- [ ] **Step 2: Fetch without rewriting local history**

Run from the clean MILIMAP clone:

```powershell
git fetch origin --prune
git switch dev
git pull --ff-only origin dev
git status --short --branch
```

Expected: `dev` matches `origin/dev` and the worktree is clean.

- [ ] **Step 3: Verify the exact Android backup target**

```powershell
$integrationRepoRoot = (git rev-parse --show-toplevel).Trim()
$integrationAndroidPath = [System.IO.Path]::GetFullPath(
    (Join-Path $integrationRepoRoot 'apps\android')
)
if ($integrationAndroidPath -ne [System.IO.Path]::GetFullPath(
    'C:\Users\PC\Documents\ChatGPT\MiliSpot 개발\MILIMAP\apps\android'
)) {
    throw "Unexpected Android target: $integrationAndroidPath"
}
git rev-parse HEAD
git log -1 --oneline
```

Expected: the repository path is the dedicated MILIMAP clone and HEAD is the documentation-merged `dev` commit.

- [ ] **Step 4: Create and push the annotated rollback tag**

First verify that the name is unused:

```powershell
git tag --list android-mvp-before-room-integration-20260822
git ls-remote --tags origin android-mvp-before-room-integration-20260822
```

Expected: both commands return no tag. Then run:

```powershell
git tag -a android-mvp-before-room-integration-20260822 `
    -m "Backup before MiliPercent Room Android integration"
git push origin android-mvp-before-room-integration-20260822
```

Expected: the remote tag resolves to the current documentation-merged `dev` commit. Do not move or recreate the tag later.

- [ ] **Step 5: Create and publish the shared integration branch**

```powershell
git switch -c feature/android-room-integration
git push -u origin feature/android-room-integration
```

Expected: the branch exists locally and remotely at the same commit as the accepted ADR.

---

### Task 2: Verify both source baselines before copying files

**Files:**
- No tracked file changes
- Read-only source: `C:/Users/PC/AndroidStudioProjects/MiliPercent2`
- Read-only target baseline: rollback tag worktree or clean `dev` checkout

**Interfaces:**
- Consumes: accepted ADR, backup tag, MiliPercent commit `5e3d7331d59979e172a67921fb45acedde11da26`
- Produces: unambiguous pre-copy build/test evidence for the core PR description

- [ ] **Step 1: Verify the MiliPercent source commit and clean state**

```powershell
$miliPercentSource = 'C:\Users\PC\AndroidStudioProjects\MiliPercent2'
git -c safe.directory='C:/Users/PC/AndroidStudioProjects/MiliPercent2' `
    -C $miliPercentSource rev-parse HEAD
git -c safe.directory='C:/Users/PC/AndroidStudioProjects/MiliPercent2' `
    -C $miliPercentSource status --short --branch
```

Expected: HEAD is `5e3d7331d59979e172a67921fb45acedde11da26`. If tracked changes exist, do not import the working tree; the later archive step still imports only the pinned commit.

- [ ] **Step 2: Run the MiliPercent automatic baseline gate**

```powershell
Set-Location 'C:\Users\PC\AndroidStudioProjects\MiliPercent2'
.\gradlew.bat lintDebug testDebugUnitTest assembleDebug --stacktrace
```

Expected: `BUILD SUCCESSFUL`. The live API integration test is skipped unless `RUN_MMA_API_TEST=true`.

- [ ] **Step 3: Run the current MILIMAP automatic baseline gate**

Use a temporary detached worktree of `android-mvp-before-room-integration-20260822`, not the future replacement directory:

```powershell
Set-Location 'C:\Users\PC\Documents\ChatGPT\MiliSpot 개발\MILIMAP'
$baselineWorktree = Join-Path `
    ([System.IO.Path]::GetTempPath()) `
    ("milimap-baseline-" + [guid]::NewGuid().ToString('N'))
git worktree add --detach $baselineWorktree `
    android-mvp-before-room-integration-20260822
Set-Location (Join-Path $baselineWorktree 'apps\android')
.\gradlew.bat lintDebug testDebugUnitTest assembleDebug --stacktrace
```

Expected: `BUILD SUCCESSFUL`. Return to the integration clone and remove only the verified temporary worktree:

```powershell
Set-Location 'C:\Users\PC\Documents\ChatGPT\MiliSpot 개발\MILIMAP'
$resolvedBaselineWorktree = [System.IO.Path]::GetFullPath($baselineWorktree)
$resolvedTempRoot = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
if (-not $resolvedBaselineWorktree.StartsWith($resolvedTempRoot)) {
    throw "Refusing to remove non-temp worktree: $resolvedBaselineWorktree"
}
git worktree remove --force $resolvedBaselineWorktree
```

- [ ] **Step 4: Record actual evidence outside product files**

Record these exact results in the Core PR description:

Record the literal `git rev-parse` outputs and these successful commands: MiliPercent `lintDebug`, `testDebugUnitTest`, `assembleDebug`; MILIMAP backup-tag `lintDebug`, `testDebugUnitTest`, `assembleDebug`.

If either baseline fails, stop and report the failure before copying files.

---

### Task 3: Import the pinned MiliPercent Android Core

**Files:**
- Replace: `apps/android/app/**`
- Replace: `apps/android/gradle/**`
- Replace: `apps/android/build.gradle.kts`
- Replace: `apps/android/settings.gradle.kts`
- Replace: `apps/android/gradle.properties`
- Replace: `apps/android/gradlew`
- Replace: `apps/android/gradlew.bat`
- Preserve for Task 4 recreation: `apps/android/README.md`
- Preserve for Task 4 recreation: `apps/android/local.properties.example`
- Do not copy: MiliPercent `.idea/**`, `.gitignore`, `.git/**`, `.gradle/**`, `build/**`, `local.properties`

The imported `app/**` tree includes the exact pinned Room schemas, main sources, unit tests, Android tests, resources, and `manual_benefits_seed.json` from MiliPercent commit `5e3d7331d59979e172a67921fb45acedde11da26`.

**Interfaces:**
- Consumes: MiliPercent tracked allowlist at the pinned commit
- Produces: buildable Room/Repository/ViewModel Android app in `apps/android`

- [ ] **Step 1: Create the phase branch from the shared integration branch**

```powershell
Set-Location 'C:\Users\PC\Documents\ChatGPT\MiliSpot 개발\MILIMAP'
git switch feature/android-room-integration
git pull --ff-only origin feature/android-room-integration
git switch -c chore/android-core-baseline
git status --short --branch
```

Expected: clean `chore/android-core-baseline` at the shared branch commit.

- [ ] **Step 2: Export only the pinned source commit to a unique staging directory**

```powershell
$miliPercentSource = 'C:\Users\PC\AndroidStudioProjects\MiliPercent2'
$miliPercentCommit = '5e3d7331d59979e172a67921fb45acedde11da26'
$integrationStaging = Join-Path `
    ([System.IO.Path]::GetTempPath()) `
    ("milipercent-core-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $integrationStaging | Out-Null
$integrationArchive = Join-Path $integrationStaging 'source.zip'
git -c safe.directory='C:/Users/PC/AndroidStudioProjects/MiliPercent2' `
    -C $miliPercentSource archive `
    --format=zip `
    --output=$integrationArchive `
    $miliPercentCommit
Expand-Archive -LiteralPath $integrationArchive `
    -DestinationPath (Join-Path $integrationStaging 'source')
```

Expected: the staging directory contains the pinned commit, including tracked `.idea` files that will be excluded by the allowlist.

- [ ] **Step 3: Verify exact destructive target before removal**

```powershell
$integrationRepoRoot = (git rev-parse --show-toplevel).Trim()
$integrationAndroidPath = [System.IO.Path]::GetFullPath(
    (Join-Path $integrationRepoRoot 'apps\android')
)
$expectedAndroidPath = [System.IO.Path]::GetFullPath(
    'C:\Users\PC\Documents\ChatGPT\MiliSpot 개발\MILIMAP\apps\android'
)
if ($integrationAndroidPath -ne $expectedAndroidPath) {
    throw "Refusing to remove unexpected path: $integrationAndroidPath"
}
git status --short --branch
```

Expected: exact path match and clean branch. Then remove only the tracked Android subtree:

```powershell
git rm -r -- apps/android
New-Item -ItemType Directory -Path $integrationAndroidPath | Out-Null
```

- [ ] **Step 4: Copy the explicit allowlist**

```powershell
$integrationSourceRoot = Join-Path $integrationStaging 'source'
$integrationAllowlist = @(
    'app',
    'gradle',
    'build.gradle.kts',
    'settings.gradle.kts',
    'gradle.properties',
    'gradlew',
    'gradlew.bat'
)
foreach ($integrationRelativePath in $integrationAllowlist) {
    $integrationSourcePath = Join-Path $integrationSourceRoot $integrationRelativePath
    if (-not (Test-Path -LiteralPath $integrationSourcePath)) {
        throw "Missing pinned source path: $integrationRelativePath"
    }
    Copy-Item -LiteralPath $integrationSourcePath `
        -Destination $integrationAndroidPath `
        -Recurse
}
```

Expected: `apps/android` contains only the allowlisted MiliPercent project plus the documentation files created in Task 4. It does not contain `.idea`, `.gradle`, `build`, or `local.properties`.

- [ ] **Step 5: Verify the import boundary before staging**

```powershell
$forbiddenImportPaths = @(
    'apps\android\.idea',
    'apps\android\.gradle',
    'apps\android\build',
    'apps\android\local.properties'
)
foreach ($forbiddenImportPath in $forbiddenImportPaths) {
    if (Test-Path -LiteralPath $forbiddenImportPath) {
        throw "Forbidden import exists: $forbiddenImportPath"
    }
}
git status --short
```

Expected: Android replacement changes only; monorepo root directories remain.

- [ ] **Step 6: Restore ignored local-only build configuration**

Copy the user's already-configured MiliPercent file without printing its contents:

```powershell
Copy-Item -LiteralPath `
    'C:\Users\PC\AndroidStudioProjects\MiliPercent2\local.properties' `
    -Destination '.\apps\android\local.properties'
git status --short -- 'apps/android/local.properties'
```

Expected: the destination exists and `git status` prints nothing because `local.properties` is ignored. Never add this file with `git add -f`.

- [ ] **Step 7: Run the imported baseline tests before documentation edits**

```powershell
Set-Location '.\apps\android'
.\gradlew.bat lintDebug testDebugUnitTest assembleDebug --stacktrace
```

Expected: `BUILD SUCCESSFUL`. If this differs from Task 2's MiliPercent baseline, stop and diagnose the copy or monorepo integration before continuing.

- [ ] **Step 8: Stage exact imported files and preserve executable mode**

```powershell
Set-Location 'C:\Users\PC\Documents\ChatGPT\MiliSpot 개발\MILIMAP'
git add -- apps/android
git update-index --chmod=+x apps/android/gradlew
git ls-files --stage apps/android/gradlew
git diff --cached --check
```

Expected: `apps/android/gradlew` has mode `100755` and diff check is clean.

- [ ] **Step 9: Commit the working Core baseline**

```powershell
git commit -m "android: Room 기반 Core 기준선 이식"
```

Expected: one commit contains the Android baseline replacement and no root monorepo deletion.

---

### Task 4: Restore repository-local setup and accurate handover documentation

**Files:**
- Create: `apps/android/local.properties.example`
- Create: `apps/android/README.md`
- Modify: `docs/current-status.md`
- Verify only: `.github/workflows/android-ci.yml`

**Interfaces:**
- Consumes: imported MiliPercent build configuration and existing MILIMAP CI working directory
- Produces: secret-free local setup instructions and current-status documentation that matches the new baseline

- [ ] **Step 1: Add the failing setup contract check**

Before creating the example file, verify it is absent:

```powershell
Test-Path '.\apps\android\local.properties.example'
```

Expected: `False`.

- [ ] **Step 2: Create the secret-free local properties example**

Use `apply_patch` to create exactly:

```properties
sdk.dir=C\:\\Users\\YOUR_NAME\\AppData\\Local\\Android\\Sdk
MMA_API_URL=https://apis.data.go.kr/1300000/JwctMmaUdhygigwan/getjwctMmaUdhygigwan
MMA_SERVICE_KEY=YOUR_DATA_GO_KR_SERVICE_KEY
```

Do not include `NAVER_MAP_NCP_KEY_ID` until the separate secret-preparation phase.

- [ ] **Step 3: Verify the setup contract**

```powershell
$integrationExample = Get-Content -LiteralPath `
    '.\apps\android\local.properties.example'
$requiredNames = @('sdk.dir', 'MMA_API_URL', 'MMA_SERVICE_KEY')
foreach ($requiredName in $requiredNames) {
    if (-not ($integrationExample -match ('^' + [regex]::Escape($requiredName) + '='))) {
        throw "Missing example property: $requiredName"
    }
}
if ($integrationExample -match 'NAVER_MAP_NCP_KEY_ID') {
    throw 'Naver key belongs to a later phase.'
}
```

Expected: all MMA setup names exist and no Naver property exists.

- [ ] **Step 4: Create the Android README**

Use `apply_patch` to create `apps/android/README.md` with these exact sections and facts:

```markdown
# MILIMAP Android

현재 Android Core 기준선은 MiliPercent의 Room/Repository/ViewModel 구현입니다.

## Source baseline

- MiliPercent source: `5e3d7331d59979e172a67921fb45acedde11da26`
- Package/applicationId: `com.example.milipercent`
- Room database: version 2

## Open in Android Studio

Repository root가 아니라 `apps/android`를 엽니다. JDK 17과 Android SDK 37을 사용합니다.

## Local configuration

`local.properties.example`을 `local.properties`로 복사하고 개인 SDK 경로와 MMA 값을 설정합니다. 실제 key는 commit하지 않습니다. Key가 없으면 API 갱신은 실패할 수 있지만 기존 Room/Seed 목록은 유지됩니다.

## Verification

```powershell
.\gradlew.bat lintDebug testDebugUnitTest assembleDebug
```

Emulator가 준비된 경우:

```powershell
.\gradlew.bat connectedDebugAndroidTest
```

## Current phase

목록, 서울 25개 구 필터, 검색, 상세, MMA 동기화, Room cache, Manual Seed와 Debug 전용 MANUAL_LOCAL 관리가 포함됩니다. Naver Map, 현재 위치, 검증 데이터 통합, 로그인과 즐겨찾기는 후속 Issue에서 진행합니다.
```

- [ ] **Step 5: Update current status without rewriting unrelated sections**

In `docs/current-status.md`, replace only stale Android implementation bullets with these facts:

```markdown
- Android Core source: MiliPercent `5e3d7331d59979e172a67921fb45acedde11da26`
- Room v2 is the single local database; schema v1/v2 and `MIGRATION_1_2` are retained.
- Data flow is Repository -> ViewModel -> UiState -> Compose.
- Current integrated features are list, Seoul district filter, name/address search, detail, MMA pagination/retry/cache, Manual Seed 12 rows, and Debug-only MANUAL_LOCAL CRUD.
- Naver Map, current location, MILIMAP 484-row reconciliation, login, and favorites are deferred on the integration branch and are not yet restored.
```

Keep server, iOS, security, data-policy, and Pending sections unless a statement directly contradicts the new Android baseline.

- [ ] **Step 6: Verify CI compatibility and docs**

```powershell
rg -n 'working-directory: apps/android|java-version: "17"|lintDebug testDebugUnitTest assembleDebug' `
    '.\.github\workflows\android-ci.yml'
rg -n '5e3d7331d59979e172a67921fb45acedde11da26|Room database: version 2' `
    '.\apps\android\README.md'
git diff --check
```

Expected: CI still points at `apps/android`, uses JDK 17, runs the full automatic gate, and documentation contains the pinned source.

- [ ] **Step 7: Run the full automatic gate again**

```powershell
Set-Location '.\apps\android'
.\gradlew.bat lintDebug testDebugUnitTest assembleDebug --stacktrace
```

Expected: `BUILD SUCCESSFUL`.

- [ ] **Step 8: Commit setup and handover documentation**

```powershell
Set-Location 'C:\Users\PC\Documents\ChatGPT\MiliSpot 개발\MILIMAP'
git add -- `
    apps/android/local.properties.example `
    apps/android/README.md `
    docs/current-status.md
git diff --cached --check
git commit -m "docs: Android Core 기준선 안내 갱신"
```

Expected: the documentation commit contains no secret values and no product code.

---

### Task 5: Validate the integrated baseline and open the Core PR

**Files:**
- Test: `apps/android/app/src/test/**`
- Test: `apps/android/app/src/androidTest/**`
- Verify: all changes from Tasks 3 and 4
- External record: Core PR targeting `feature/android-room-integration`

**Interfaces:**
- Consumes: imported Core commit and documentation commit
- Produces: reviewed Android Core baseline in the shared integration branch

- [ ] **Step 1: Run targeted unit tests**

```powershell
Set-Location 'C:\Users\PC\Documents\ChatGPT\MiliSpot 개발\MILIMAP\apps\android'
.\gradlew.bat testDebugUnitTest --tests `
    "com.example.milipercent.data.BenefitRepositoryTest" `
    --tests "com.example.milipercent.data.seed.ManualBenefitSeedLoaderTest" `
    --tests "com.example.milipercent.ui.BenefitDistrictStateTest" `
    --tests "com.example.milipercent.ui.BenefitDetailUiStateTest" `
    --stacktrace
```

Expected: all selected tests pass.

- [ ] **Step 2: Run the complete automatic gate**

```powershell
.\gradlew.bat lintDebug testDebugUnitTest assembleDebug --stacktrace
```

Expected: `BUILD SUCCESSFUL`.

- [ ] **Step 3: Run instrumentation tests on the already-started emulator**

```powershell
adb devices
.\gradlew.bat connectedDebugAndroidTest --stacktrace
```

Expected: one authorized emulator/device and all instrumentation tests pass. If no authorized emulator exists, record the omission and do not claim it passed.

- [ ] **Step 4: Run the opt-in live MMA integration test**

Only run when the local `MMA_API_URL` and `MMA_SERVICE_KEY` are set. Do not print either value.

```powershell
$previousRunMmaApiTest = $env:RUN_MMA_API_TEST
try {
    $env:RUN_MMA_API_TEST = 'true'
    .\gradlew.bat testDebugUnitTest `
        --tests "com.example.milipercent.network.BenefitApiIntegrationTest" `
        --stacktrace
} finally {
    $env:RUN_MMA_API_TEST = $previousRunMmaApiTest
}
```

Expected: the API test passes without logging the service key. If the public API is unavailable, record the external failure separately from the deterministic gate.

- [ ] **Step 5: Perform a secret and boundary audit**

```powershell
Set-Location 'C:\Users\PC\Documents\ChatGPT\MiliSpot 개발\MILIMAP'
git diff feature/android-room-integration...HEAD --check
git diff --name-only feature/android-room-integration...HEAD
git status --short --branch
git ls-files --stage apps/android/gradlew
git grep -n -I -E '(serviceKey|MMA_SERVICE_KEY|NAVER_MAP_NCP_KEY_ID)=' -- `
    ':!apps/android/local.properties.example' `
    ':!docs/**'
```

Expected:

- no whitespace errors;
- changes are limited to `apps/android` and named documentation files;
- clean worktree;
- `gradlew` mode `100755`;
- secret scan prints no committed value assignment.

- [ ] **Step 6: Push the phase branch and open a PR**

```powershell
git push -u origin chore/android-core-baseline
```

Open a PR with:

```text
Base: feature/android-room-integration
Head: chore/android-core-baseline
Title: [Android] Replace Core baseline with Room/ViewModel architecture
Issue: #4
```

The PR body must include both source SHAs, exact included/excluded scope, baseline and post-copy command results, instrumentation/API test results or omissions, the rollback tag, secret audit result, and a statement that Map/Location/data parity is intentionally deferred within the integration branch.

- [ ] **Step 7: Require review and CI before merge**

Expected before merge:

- another team member approves;
- Android CI passes;
- no unresolved review comment;
- no accidental `.idea`, `local.properties`, build output, SQLiteOpenHelper, AppController, or SessionStore remains in the new Android baseline.

Merge the phase PR into `feature/android-room-integration`, not `dev`. Do not delete the shared integration branch.

---

## Phase Completion Boundary

This plan ends when the reviewed Core PR is merged into `feature/android-room-integration`. It does not merge the shared integration branch into `dev`.

Create separate implementation plans for:

1. package/secret preparation;
2. Naver Map and marker navigation;
3. current location;
4. Room v3 trust-field contract;
5. data reconciliation and enrichment;
6. final parity verification and `dev` integration.
