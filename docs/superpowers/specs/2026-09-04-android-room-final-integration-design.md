# Android Room Final Integration Design

## Status

- Date: 2026-09-04
- Status: Approved design draft for implementation planning
- Target: Android application under `apps/android`
- Integration branch: `codex/android-room-final-integration`
- Final destination after all gates and explicit approval: `dev`

This document replaces the incomplete parts of the 2026-08-22 Android Room integration design for the final integration. In particular, account, favorite, administrator, current UI, Naver Map, and live-location behavior are now required scope rather than follow-up work.

## Context and pinned baselines

The repository currently has two useful but incomplete lines of Android work:

| Baseline | Commit | Purpose |
| --- | --- | --- |
| Room integration branch | `af8851a33cc5ba7b595b51992e11250620feaab1` | Room, Repository, ViewModel, UiState, Navigation, API client, and tests |
| Current `dev` | `39a5d3570895bead2fba0de7fa74f9a1731dce9a` | Working product UI, Naver Map, fully geocoded 484-row benefit data, login, favorites, and administrator behavior |
| Local live-location work | `67e34fd2894b7b35157eba6e8125527c1c14fddd` | Foreground live GPS updates and camera-control corrections |
| Original MiliPercent core | `5e3d7331d59979e172a67921fb45acedde11da26` | Historical source of the imported Room architecture |

The Room branch is not safe to merge into `dev` as-is because it does not yet contain every working product feature. The purpose of this integration is to complete that branch without sacrificing behavior that already works.

The pinned `dev` includes PR #11 (`4f8e660`, merged as `39a5d35`). That data-only change preserves all 484 benefit IDs and all non-coordinate fields, adds coordinates to 145 rows, corrects one invalid existing coordinate, and leaves all 484 rows with validated WGS84 map coordinates. Its geocoding script, report, summary, and updated data policy are part of the current-product baseline and must not be lost during integration.

## Goals

- Make Room the only local database used by the Android application.
- Preserve the current visible UI and all existing user-facing behavior.
- Preserve Naver Map, benefit markers, detail navigation, search, filters, login, favorites, and administrator functions.
- include the approved live-device-location behavior from commit `67e34fd`.
- Preserve and reconcile the built-in benefit data and Military Manpower Administration API data.
- Keep the final `applicationId` as `com.example.militarybenefits` so the existing Naver Map registration remains valid.
- Produce a branch that can be compared against current `dev` feature by feature before any GitHub update.
- Require emulator and real-device verification before the final merge.

## Non-goals

- Redesigning the current Compose UI or changing the product flow.
- Adding Firebase, remote authentication, a new backend, or cloud account synchronization.
- Preserving current local test accounts, sessions, or favorite rows during the database transition.
- Expanding the benefit dataset beyond the sources already used by the project.
- Publishing, releasing, deploying, or changing production infrastructure.
- Committing API keys or other secrets.
- Pushing, opening a pull request, or merging before the user reviews the verified result.

## Safety and branch strategy

The integration is isolated from the working application.

1. The working live-location result remains recoverable on `codex/live-location-tracking` at commit `67e34fd`.
2. Final integration occurs only in the separate worktree at:
   `C:\Users\PC\Documents\ChatGPT\MiliSpot 개발\worktrees\android-room-final-integration`
3. Its branch, `codex/android-room-final-integration`, starts from the Room baseline at `af8851a`.
4. Current `dev` features are ported into this branch deliberately. The Android directory is not replaced wholesale in either direction.
5. No force push, destructive reset, or history rewrite is part of the workflow.
6. Nothing is pushed to GitHub, proposed as a pull request, or merged into `dev` until the complete verification report has been reviewed and explicitly approved.
7. If `dev` changes before the final comparison, the new commits are reviewed and integrated, and all affected gates are rerun.

## Target architecture

~~~text
Bundled verified seed ----+
                          |
MMA API ------------------+--> BenefitRepository --> Room --> ViewModel --> UiState --> Compose
                                |                  ^
Administrator edits -----------+                  |
                                                   |
Android location provider --> LocationDataSource --+--> map position and distance state

Room users <--> AccountRepository <--> AccountViewModel <--> login/admin UI
Room favorites <--> FavoriteRepository <--> ViewModel <--> list/detail/map UI
~~~

### Ownership rules

- Room is the single source of truth for benefits, users, and favorites.
- `SQLiteOpenHelper` and `AppController` database ownership must not remain in the final application.
- Repositories own persistence, API synchronization, transactions, and entity-to-domain mapping.
- ViewModels own loading, errors, selected filters, searches, session-facing state, map focus requests, and UI events.
- Composables render state and forward user actions. They do not query the database or call the API directly.
- Android permission and location-provider calls remain behind a small platform boundary such as `LocationDataSource`.
- Activities assemble Android entry points and permission launchers; they do not become state stores.

## Data contract

### Benefit model

The final Room entity and domain mapping must preserve every field currently used by `dev` and the useful provenance already present in the Room branch:

| Field | Requirement |
| --- | --- |
| `id` | Stable string identifier used by navigation and favorites |
| `name`, `address`, `phone` | Current display and search data |
| `latitude`, `longitude` | Nullable coordinates used by map and distance |
| `category` | Product category; distinct from benefit type |
| `benefitType`, `benefitDescription` | Benefit classification and display text |
| `eligibleTarget`, `usageCondition`, `verificationMethod` | Detail information |
| `district` | Seoul district filtering |
| `sourceType`, `sourceLabel` | Data provenance |
| `sourceUrl` | Primary evidence URL |
| `sourceRowNumber` | Optional upstream row provenance |
| `lastVerifiedAt` | Optional last verification date/time |
| `syncedAt` | Local synchronization timestamp |
| `status` | Typed status equivalent to ACTIVE, NEEDS_VERIFICATION, or ENDED |

The Room database advances through an explicit migration from the existing exported schema. Destructive migration fallback is not permitted. Exported schemas and migration tests are updated with the schema.

### Accounts and favorites

Room gains user and favorite tables that reproduce the current local-only behavior.

- A user has a stable ID, unique normalized email, display name, password salt/hash, and administrator flag.
- Plain-text passwords are never stored or logged.
- The first registered local user retains the current administrator semantics.
- A favorite uses the user ID and benefit ID as a unique pair.
- Favorite rows reference both parent tables with foreign keys and are removed when the relevant parent is removed.
- Session state may remain preference-backed if that is the existing minimal mechanism, but persisted user and favorite records belong to Room.
- Existing test users, sessions, and favorites do not need to migrate. The upgrade may start these tables empty.

## Data ingestion and reconciliation

### Bundled data

- The current 484-row bundled benefit dataset is retained together with the Room branch's 12 unique manual rows, producing 496 unique initial rows before a live API refresh.
- All 484 current-product rows keep their PR #11 coordinates. The 12 manual rows may remain without coordinates and therefore do not produce map markers until verified coordinates exist.
- The PR #11 geocoding report, summary, source CSV provenance, script, and data-policy rules remain tracked evidence; integration must not regenerate or silently replace those coordinates.
- The entire bundled file is parsed and validated before database replacement begins.
- A failed parse or validation leaves the last valid Room data untouched.
- Inserts or replacements for a source happen in one Room transaction.
- Invalid required identifiers and malformed coordinates are reported without exposing secrets.

### MMA API

- The existing API URL and service key remain local settings injected through BuildConfig.
- Pagination continues until the service-reported result is completely collected.
- The implementation must not hard-code a permanent expected row count because the upstream data can change.
- An empty or incomplete response is not allowed to replace a valid cache.
- A first-page or later-page failure leaves the last valid Room cache available and surfaces a non-fatal refresh error.
- Network work does not run directly from a Composable.

### Stable identity, deduplication, and enrichment

- An upstream stable source identifier is preferred when it exists.
- Otherwise, normalized business name plus normalized address forms the matching key.
- Normalization covers leading/trailing whitespace, repeated whitespace, and equivalent Seoul address notation used by the current sources.
- A name-only match does not automatically merge rows because separate branches can share a name.
- When matching built-in data and API data describe the same benefit, verified local coordinates and richer details enrich the API-backed row rather than creating a duplicate.
- Conflicting non-empty values are resolved by explicit source priority and recorded in tests; they are never overwritten by iteration order.
- Favorites continue to reference the stable final benefit ID across successful refreshes.
- `ENDED` benefits remain queryable for administration but are excluded from the normal user result stream.

## UI and behavior preservation

The current `dev` UI is the behavioral reference. The integration changes its state source, not its intended presentation.

Required flows are:

- initial list and map loading;
- category and Seoul district filtering;
- Korean name/address search;
- benefit detail display and back navigation;
- list or marker selection opening the correct detail;
- Naver Map markers and external navigation/deep-link action;
- account registration and login;
- per-user favorite toggle and favorite filtering/display;
- administrator creation, editing, status/end, and deletion behavior currently exposed by the app;
- loading, empty, permission-denied, and recoverable-error states.

Any intentional visible change discovered during implementation requires a separate design update and user approval. Architecture work alone does not authorize a redesign.

## Naver Map and live location

### Map requirements

- Keep `applicationId=com.example.militarybenefits`.
- Inject `NAVER_MAP_NCP_KEY_ID` from untracked local properties through the existing safe configuration path.
- Missing or invalid map configuration must not prevent compilation and must not crash list/detail use.
- Only benefits with both latitude and longitude produce markers.
- Marker identity and update detection include ID, name, category, latitude, and longitude so changed coordinates or labels refresh correctly.
- Marker selection resolves the same stable benefit ID used by Room and detail navigation.
- Existing map deep-link/external-navigation behavior is retained.

### Location requirements

- Fine/coarse location permission is requested at the UI boundary and denial is a usable state, not a fatal error.
- Foreground tracking starts when the location-aware screen is active and stops when it leaves the foreground.
- The accepted current behavior uses approximately a 5-second minimum interval and 10-meter minimum displacement, subject to Android provider behavior.
- Passive location updates refresh the blue location marker and displayed distances without repeatedly moving the camera.
- The explicit current-location button recenters the camera, even if the newest coordinate equals the previous coordinate.
- A new search or user-selected map focus cancels a pending automatic location focus so the camera does not jump back unexpectedly.
- A stale last-known location does not suppress subscription to fresh updates.
- Provider-disabled, null-location, and permission-denied states leave the map, search, and benefit browsing operational.
- Emulator testing may use a simulated route. Final acceptance additionally requires an actual Android device to demonstrate movement-driven updates and lifecycle stopping.

## Error handling and security

- `local.properties` and all actual API or map keys remain untracked.
- Secret values, full credential-bearing URLs, passwords, and password hashes are not written to logs or test snapshots.
- MMA API failure preserves cached benefits and shows a recoverable state.
- Seed failure preserves the prior valid dataset.
- Missing Naver Map configuration produces a clear fallback or unavailable state rather than an application crash.
- Room write failures are surfaced through repository/ViewModel error state; they are not silently swallowed.
- Location failure affects only location-dependent features.
- Local password authentication is retained only to preserve the current development app behavior. A backend authentication and secret-proxy design is a separate requirement before a public production release.

## Implementation sequence

The implementation plan must use small reviewable steps in this order:

1. **Baseline reconciliation**
   - Compare Room branch and pinned `dev`.
   - Retain the Room build/test foundation.
   - Restore `com.example.militarybenefits` and required current dependencies/configuration.
2. **Unified benefit data**
   - Finalize entity, domain model, DAO, migration, mapping, seed loader, API synchronization, deduplication, and cache behavior.
3. **Map and live location**
   - Port Naver Map rendering, markers, detail actions, deep links, permission flow, and commit `67e34fd` location semantics into the Room state flow.
4. **Accounts, favorites, and administration**
   - Add Room tables/repositories/ViewModels and restore all current flows with empty test state allowed.
5. **Current UI hookup**
   - Connect the current Compose screens to the new UiState without redesigning them and remove obsolete database paths.
6. **Parity and release-candidate verification**
   - Run automated checks, emulator scenarios, real-device scenarios, diff review, and the complete parity checklist.

Each step begins with tests or a concrete failing verification for the behavior being moved. A later phase does not delete or disable an earlier phase's passing behavior to make progress.

## Verification matrix

### Automated

The minimum Android gate is:

~~~powershell
.\gradlew.bat lintDebug testDebugUnitTest assembleDebug
~~~

Also required where the environment supports it:

~~~powershell
.\gradlew.bat connectedDebugAndroidTest
~~~

Direct tests must cover:

- Room schema migration and exported schema identity;
- entity/domain mapping for every preserved benefit field;
- bundled seed validation and transactional replacement;
- complete MMA pagination and partial-failure cache retention;
- deterministic deduplication/enrichment and stable IDs;
- status filtering;
- user registration/login and first-user administrator behavior;
- favorite uniqueness, per-user isolation, and foreign-key behavior;
- administrator CRUD/status behavior;
- filter/search state and detail-route identity;
- location state transitions, same-coordinate recenter event, search-focus cancellation, and foreground stop;
- marker projection excluding incomplete coordinates and detecting relevant item changes.

### Emulator smoke test

- Fresh install and app start.
- Built-in benefits appear.
- MMA refresh succeeds when configured; a forced failure retains cache.
- List, category, district, and Korean search behave as in `dev`.
- Detail navigation and back navigation work.
- Naver Map renders, markers match data, and marker selection opens the correct detail.
- Simulated GPS movement updates the blue marker and distance without camera chasing.
- Current-location button recenters.
- Permission denial and later grant both recover safely.
- Registration, login, logout, favorites, and administrator operations work.
- Backgrounding the app stops active location updates.

### Real-device acceptance

Before the final merge, a physical Android device must verify:

- Naver Map authentication with the final application ID;
- permission grant, denial, and retry;
- actual current-position acquisition;
- movement updates to marker and distance;
- no unsolicited camera recenter during passive updates;
- explicit recenter button behavior;
- foreground/background subscription lifecycle;
- search, detail, login, favorite, and administrator smoke flows.

## Feature-parity gate

The final branch is not ready while any item below is missing or intentionally bypassed:

- Room is the only application database.
- Current built-in benefit data is present after reconciliation.
- MMA API data refreshes and cache survives failure.
- No unintended duplicate benefits are introduced.
- List, map, search, category filter, and district filter work.
- Detail, marker navigation, and external map/deep-link actions work.
- Naver Map works under `com.example.militarybenefits`.
- Live GPS follows the approved foreground behavior.
- Registration, login, logout, favorites, and administrator features work.
- Existing Compose UI and user flow remain recognizable and functional.
- No actual secret or generated build output is included in Git.
- Lint, unit tests, debug assembly, applicable instrumentation tests, emulator smoke, and real-device checks are recorded.
- Independent code review has no unresolved Critical or Important finding.

## Merge and rollback policy

1. Implementation remains local on `codex/android-room-final-integration` while incomplete.
2. Before publication, fetch current remote state and compare `origin/dev` with the pinned baseline.
3. Integrate any new `dev` work without overwriting the completed Room architecture, then rerun all affected verification.
4. Review the final diff for unrelated changes, secrets, generated files, disabled tests, and obsolete duplicate database code.
5. Present the verification report and remaining limitations to the user.
6. Only after explicit user approval may the branch be pushed and a pull request from the integration branch to `dev` be created.
7. The pull request must pass repository CI and team review before merge.
8. Merge must remain recoverable through normal Git history; force pushes and destructive rewrites are prohibited.

## Risks and mitigations

| Risk | Mitigation |
| --- | --- |
| Porting UI wholesale overwrites Room work | Move behavior by layer in the ordered phases and review each diff |
| Room IDs change after API refresh and break favorites | Define stable identity before favorites and test refresh stability |
| Built-in and MMA data create duplicates | Deterministic matching, explicit source priority, and reconciliation tests |
| Map works locally but fails for teammates | Keep final application ID, document untracked key names, test missing-key behavior |
| GPS continuously moves the camera | Separate passive position updates from explicit camera-focus events |
| Location updates continue in background | Lifecycle-bound subscription and background verification |
| Account schema migration delays work | Reset local test rows while preserving all account/favorite functions |
| New `dev` commits cause late conflicts | Recheck remote `dev` before publication and rerun the complete affected gate |
| Architecture work silently changes UX | Treat current `dev` as the parity reference and require user-visible change approval |

## Acceptance criteria

The integration is complete only when:

1. The application builds from the integration worktree with no secret values in tracked files.
2. Room is the sole database and all required benefit, account, favorite, and administrator behavior uses it.
3. Current `dev` UI and features, plus the approved live GPS behavior, pass the parity gate.
4. Data refresh, cache retention, migration, identity, and deduplication behavior are covered by tests.
5. Emulator and real-device results are recorded.
6. Final review has no unresolved Critical or Important defect.
7. The user reviews the completion report and explicitly authorizes publication or merge.

Until all seven conditions hold, `dev` remains unchanged and the current working application remains the fallback.
