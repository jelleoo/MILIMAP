# Android Room Final Integration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Complete the Android Room integration without losing the current UI, 496 bundled benefit rows, MMA API refresh, accounts, favorites, administrator tools, Naver Map, or approved live-location behavior.

**Architecture:** Keep `com.example.milipercent` as the Kotlin namespace while installing as `com.example.militarybenefits`. Room v4 is the only database; repositories expose Room-backed flows, `MiliSpotViewModel` combines them into immutable UI state, Compose renders the state, and a lifecycle-bound location adapter emits foreground updates.

**Tech Stack:** Kotlin, Android SDK 37/min SDK 24, JDK 17, Jetpack Compose and Navigation, coroutines/Flow, Room 2.8.4 with KSP, kotlinx.serialization, Naver Maps SDK 3.23.3, JUnit 4, AndroidX instrumentation and Compose UI tests.

**Spec:** `docs/superpowers/specs/2026-09-04-android-room-final-integration-design.md`

## Global Constraints

- Work only in `C:\Users\PC\Documents\ChatGPT\MiliSpot 개발\worktrees\android-room-final-integration` on `codex/android-room-final-integration`.
- Room base: `af8851a33cc5ba7b595b51992e11250620feaab1`.
- Current product/data base: `origin/dev@39a5d3570895bead2fba0de7fa74f9a1731dce9a`.
- Live-location reference: `67e34fd2894b7b35157eba6e8125527c1c14fddd`.
- Keep `namespace = "com.example.milipercent"` and set `applicationId = "com.example.militarybenefits"`.
- Keep compile/target SDK 37, min SDK 24, Gradle daemon JDK 17, and Java target 11.
- Use explicit Room migrations only: v2→v3 completes benefits/seeding; v3→v4 adds users/favorites. Do not use destructive migration fallback.
- Preserve the 484-row current seed and 12 unique Room seed rows. The initial install contains 496 unique rows.
- Preserve all 484 coordinates merged in PR #11, its source/report files, and its data-policy rules.
- Local test accounts, sessions, and favorites may reset; their behavior must remain.
- Keep location foreground-only at 5,000 ms/10 m. Passive updates change marker/distances but not camera.
- Real values stay only in untracked `apps/android/local.properties` and never enter logs.
- Do not push, open a pull request, or merge into `dev` before final verification and explicit user approval.
- Each behavior starts with the listed failing test or verification and ends with its focused test plus a local commit.

## File ownership map

Task file lists use these unambiguous prefixes:

- `model/...` = `apps/android/app/src/main/java/com/example/milipercent/model/...`
- `data/...` = `apps/android/app/src/main/java/com/example/milipercent/data/...`
- `ui/...` = `apps/android/app/src/main/java/com/example/milipercent/ui/...`
- `navigation/...` = `apps/android/app/src/main/java/com/example/milipercent/navigation/...`
- `location/...` = `apps/android/app/src/main/java/com/example/milipercent/location/...`
- `src/test/...` and `src/androidTest/...` are relative to `apps/android/app/`.

- `app/build.gradle.kts`, Version Catalog, manifest, and local-properties example: identity and dependency contract.
- `model/Benefit.kt`, `MmaBenefit.kt`, `BenefitStatus.kt`, `GeoPoint.kt`: product/upstream domain boundary.
- `data/local/*`: Room entities, DAOs, schemas, and migrations.
- `data/seed/*`: two seed formats and versioned all-or-nothing install.
- `data/BenefitReconciler.kt` and `BenefitRepository.kt`: deterministic API/cache reconciliation.
- `data/account/*`, `data/favorite/*`, `data/admin/*`, `data/session/*`: user features.
- `ui/MiliSpotUiState.kt`, `DiscoverState.kt`, `MiliSpotViewModel.kt`: product state and events.
- `navigation/MiliSpotNavHost.kt` and `ui/*Screens.kt`: current visual flow on Compose Navigation.
- `ui/map/*` and `ui/NaverMapPanel.kt`: map projection, marker lifecycle, and deep links.
- `location/*`: Android provider adapter and focus semantics.
- `MainActivity.kt`: dependency assembly, permission launcher, and foreground lifecycle only.

---

### Task 1: Lock application identity and configuration

**Files:**
- Create: `apps/android/app/src/test/java/com/example/milipercent/AppBuildContractTest.kt`
- Modify: `apps/android/app/build.gradle.kts`
- Modify: `apps/android/gradle/libs.versions.toml`
- Modify: `apps/android/app/src/main/AndroidManifest.xml`
- Modify: `apps/android/local.properties.example`

**Interfaces:**
- Consumes: existing BuildConfig generation and Version Catalog.
- Produces: `BuildConfig.APPLICATION_ID`, `NAVER_MAP_NCP_KEY_ID`, `MMA_API_URL`, and `MMA_SERVICE_KEY`.

- [ ] **Step 1: Incorporate the pinned latest dev baseline locally**

~~~powershell
git merge --no-ff origin/dev
~~~

Resolve the expected `benefits.seed.json` modify/delete conflict by retaining the `origin/dev@39a5d35` 484-row blob. Preserve the geocoding script, CSV, reports, data policy, and collaboration documents. Do not restore `AppController` or the old SQLite package tree. Confirm `git status` has no unresolved path before continuing.

- [ ] **Step 2: Write the failing contract test**

~~~kotlin
class AppBuildContractTest {
    @Test
    fun `application id matches registered map package`() {
        assertEquals("com.example.militarybenefits", BuildConfig.APPLICATION_ID)
    }

    @Test
    fun `all local configuration fields exist`() {
        assertNotNull(BuildConfig.NAVER_MAP_NCP_KEY_ID)
        assertNotNull(BuildConfig.MMA_API_URL)
        assertNotNull(BuildConfig.MMA_SERVICE_KEY)
    }
}
~~~

- [ ] **Step 3: Prove the current contract fails**

Run from `apps/android`:

~~~powershell
.\gradlew.bat testDebugUnitTest --tests "com.example.milipercent.AppBuildContractTest"
~~~

Expected: FAIL because the ID is `com.example.milipercent` and the Naver field is missing.

- [ ] **Step 4: Implement the exact build contract**

Keep the existing `buildConfigString` helper and apply:

~~~kotlin
android {
    namespace = "com.example.milipercent"
    defaultConfig {
        applicationId = "com.example.militarybenefits"
        minSdk = 24
        targetSdk = 37
        buildConfigField(
            "String",
            "NAVER_MAP_NCP_KEY_ID",
            buildConfigString(localProperties.getProperty("NAVER_MAP_NCP_KEY_ID", "")),
        )
        manifestPlaceholders["naverMapNcpKeyId"] =
            localProperties.getProperty("NAVER_MAP_NCP_KEY_ID", "MISSING_NCP_KEY_ID")
    }
}
~~~

Add Version Catalog `naverMap = "3.23.3"`, library `com.naver.maps:map-sdk`, and `implementation(libs.naver.map)`.

- [ ] **Step 5: Restore manifest and example settings**

Add coarse/fine location permissions, the `com.nhn.android.nmap` query, and:

~~~xml
<meta-data
    android:name="com.naver.maps.map.NCP_KEY_ID"
    android:value="${naverMapNcpKeyId}" />
~~~

Keep `android:name=".MainActivity"`. Add only this non-secret example line:

~~~properties
NAVER_MAP_NCP_KEY_ID=YOUR_NCP_KEY_ID
~~~

- [ ] **Step 6: Run and commit**

~~~powershell
.\gradlew.bat testDebugUnitTest --tests "com.example.milipercent.AppBuildContractTest"
.\gradlew.bat processDebugMainManifest assembleDebug
git add apps/android
git commit -m "build(android): restore MiliSpot app identity"
~~~

Expected: PASS with blank keys permitted.

### Task 2: Complete the benefit contract and Room v3

**Files:**
- Create: `model/BenefitStatus.kt`, `model/GeoPoint.kt`, `model/MmaBenefit.kt`
- Create: `data/local/SeedStateEntity.kt`, `data/local/SeedStateDao.kt`
- Create: `src/test/.../data/local/BenefitMappersTest.kt`
- Modify: `model/Benefit.kt`, `BenefitCollection.kt`
- Modify: `data/local/BenefitEntity.kt`, `BenefitDao.kt`, `BenefitDatabase.kt`, `BenefitMigrations.kt`, `BenefitMappers.kt`, `BenefitSourceType.kt`
- Modify: parser/analyzer and their tests to consume `MmaBenefit`
- Modify: `src/androidTest/.../BenefitMigrationTest.kt` and `BenefitDaoTest.kt`
- Generate: Room schema `3.json`

**Interfaces:**
- Consumes: Room v2 and current parser records.
- Produces: full `Benefit`, upstream `MmaBenefit`, `SeedStateEntity`, and `MIGRATION_2_3`.

- [ ] **Step 1: Write failing round-trip and migration tests**

The mapper test constructs a `Benefit` with every field non-empty, calls `toEntity(99L).toDomain()`, and asserts equality. Add `migrate2To3PreservesOldFieldsAndAddsFinalContract`, asserting fallback category `기타`, source label `병무청 나라사랑가게 API`, status `NEEDS_VERIFICATION`, and copied `lastVerifiedAt`.

- [ ] **Step 2: Run the focused failing tests**

~~~powershell
.\gradlew.bat testDebugUnitTest --tests "com.example.milipercent.data.local.BenefitMappersTest"
.\gradlew.bat connectedDebugAndroidTest -Pandroid.testInstrumentationRunnerArguments.class=com.example.milipercent.data.local.BenefitMigrationTest
~~~

Expected: model test fails to compile and migration test fails because v3 is absent. If no device is connected, retain the test and execute it in Task 14.

- [ ] **Step 3: Define exact models**

~~~kotlin
enum class BenefitStatus { ACTIVE, NEEDS_VERIFICATION, ENDED }
data class GeoPoint(val latitude: Double, val longitude: Double)
data class MmaBenefit(
    val sourceRowNumber: Int?,
    val name: String,
    val address: String?,
    val phone: String?,
    val benefitType: String?,
)
data class Benefit(
    val id: String,
    val name: String,
    val address: String,
    val latitude: Double?,
    val longitude: Double?,
    val category: String,
    val benefitType: String,
    val benefitDescription: String,
    val phone: String?,
    val eligibleTarget: String?,
    val usageCondition: String?,
    val verificationMethod: String?,
    val sourceType: BenefitSourceType,
    val sourceLabel: String,
    val sourceUrl: String?,
    val lastVerifiedAt: String?,
    val status: BenefitStatus,
    val district: String?,
)
~~~

Change `BenefitCollection`/`BenefitPage` to `List<MmaBenefit>` and update parser/analyzer fixtures without changing pagination semantics.

- [ ] **Step 4: Define the final benefit and seed entities**

~~~kotlin
@Entity(
    tableName = "benefits",
    indices = [
        Index(value = ["sourceType"]),
        Index(value = ["status", "category"]),
        Index(value = ["district"]),
    ],
)
data class BenefitEntity(
    @PrimaryKey val id: String,
    val sourceType: String,
    val sourceRowNumber: Int?,
    val name: String,
    val address: String,
    val latitude: Double?,
    val longitude: Double?,
    val category: String,
    val benefitType: String,
    val benefitDescription: String,
    val phone: String?,
    val eligibleTarget: String?,
    val usageCondition: String?,
    val verificationMethod: String?,
    val sourceLabel: String,
    val sourceUrl: String?,
    val lastVerifiedAt: String?,
    val status: String,
    val district: String?,
    val syncedAt: Long,
)

@Entity(tableName = "seed_state")
data class SeedStateEntity(
    @PrimaryKey val name: String,
    val version: Int,
    val installedAt: Long,
)
~~~

Add `LOCAL_GOV` and `PUBLIC_EVIDENCE` to the existing source enum.

- [ ] **Step 5: Implement `MIGRATION_2_3`**

Rebuild `benefits` with the fields above. Copy v2 rows with:

~~~sql
COALESCE(address, '주소 확인 필요'),
'기타',
COALESCE(benefitType, '할인·우대'),
COALESCE(benefitDescription, '혜택 내용은 업소에 확인'),
CASE sourceType
  WHEN 'MMA_API' THEN '병무청 나라사랑가게 API'
  WHEN 'MANUAL_SEED' THEN '검증된 내장 데이터'
  ELSE '운영팀 직접 확인'
END,
lastVerifiedDate,
COALESCE(status, 'NEEDS_VERIFICATION')
~~~

Create `seed_state` and all three indices. Set database version 3, register migrations 1→2 and 2→3, and expose `seedStateDao()`. Do not use destructive fallback.

- [ ] **Step 6: Implement mappings and DAO reads**

Map all entity/domain fields one-for-one; an unknown stored status maps to `NEEDS_VERIFICATION`. Add `observeAll()`, `getBySource(sourceType)`, `getAllOnce()`, and `countAll()`.

Define seed metadata access explicitly:

~~~kotlin
@Dao
interface SeedStateDao {
    @Query("SELECT version FROM seed_state WHERE name = :name LIMIT 1")
    suspend fun version(name: String): Int?
    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsert(state: SeedStateEntity)
}
~~~

- [ ] **Step 7: Verify and commit**

~~~powershell
.\gradlew.bat testDebugUnitTest --tests "com.example.milipercent.data.local.BenefitMappersTest" --tests "com.example.milipercent.network.BenefitXmlParserTest" --tests "com.example.milipercent.analysis.BenefitAnalyzerTest"
.\gradlew.bat connectedDebugAndroidTest -Pandroid.testInstrumentationRunnerArguments.class=com.example.milipercent.data.local.BenefitMigrationTest
.\gradlew.bat connectedDebugAndroidTest -Pandroid.testInstrumentationRunnerArguments.class=com.example.milipercent.data.local.BenefitDaoTest
git add apps/android/app
git commit -m "refactor(android): complete Room benefit contract"
~~~

Expected: all available tests PASS and schema 3 contains every declared column/index.

### Task 3: Install the 496 bundled rows atomically

**Files:**
- Restore: `app/src/main/assets/benefits.seed.json` from `origin/dev@39a5d35`
- Preserve: `app/src/main/assets/manual_benefits_seed.json`
- Create: `data/seed/LegacyBenefitSeedLoader.kt`, `BundledSeedSynchronizer.kt`
- Create: unit test `LegacyBenefitSeedLoaderTest.kt`
- Create: instrumentation test `BundledSeedSynchronizerTest.kt`
- Modify: `ManualBenefitSeedLoader.kt` and seed tests

**Interfaces:**
- Consumes: two JSON formats, `BenefitDatabase.withTransaction`, and `SeedStateDao`.
- Produces: `BenefitSeedSource.loadAndValidate()` and `synchronizeIfNeeded()`.

- [ ] **Step 1: Restore and verify the new data blob**

Restore the exact tracked file from `origin/dev@39a5d35`. Assert 484 unique IDs, 484 non-null coordinate pairs, source counts 311/159/14, and no non-coordinate drift from its report. Preserve the geocoding script, CSV, reports, and policy when latest `dev` is integrated.

- [ ] **Step 2: Write failing loader/transaction tests**

The legacy loader test rejects blank required fields, invalid enum/date/URL/coordinate, and duplicate trimmed IDs. The real-asset test asserts:

~~~kotlin
assertEquals(496, database.benefitDao().countAll())
assertEquals(1, database.seedStateDao().version(BUNDLED_SEED_NAME))
assertEquals(0, normalizedDuplicateCount(database.benefitDao().getAllOnce()))
assertEquals(484, database.benefitDao().getAllOnce().count {
    it.latitude != null && it.longitude != null
})
~~~

Call synchronization twice; the second call must be a no-op with 496 rows.

- [ ] **Step 3: Run the focused failing tests**

~~~powershell
.\gradlew.bat testDebugUnitTest --tests "com.example.milipercent.data.seed.LegacyBenefitSeedLoaderTest"
.\gradlew.bat connectedDebugAndroidTest -Pandroid.testInstrumentationRunnerArguments.class=com.example.milipercent.data.seed.BundledSeedSynchronizerTest
~~~

- [ ] **Step 4: Implement loaders and versioned install**

~~~kotlin
fun interface SeedJsonSource {
    fun readText(): String
}
class AssetJsonSource(context: Context, private val assetName: String) : SeedJsonSource {
    private val assets = context.applicationContext.assets
    override fun readText(): String =
        assets.open(assetName).bufferedReader(Charsets.UTF_8).use { it.readText() }
}
fun interface BenefitSeedSource {
    fun loadAndValidate(): List<BenefitEntity>
}
const val BUNDLED_SEED_NAME = "benefits"
const val BUNDLED_SEED_VERSION = 1
data class BundledSeedSyncResult(val installed: Boolean, val storedCount: Int)
~~~

The 484-row loader decodes a top-level list and validates every source URL split by `" | "`, latitude in -90..90, longitude in -180..180, and enum fields. The 12-row loader implements the same interface. Parse and validate both lists before opening a Room transaction.

Inside one transaction: if version 1 exists, return unchanged; otherwise reject duplicate IDs/normalized name-address pairs, insert all 496, write seed state version 1, and verify count 496.

- [ ] **Step 5: Verify and commit**

~~~powershell
.\gradlew.bat testDebugUnitTest --tests "com.example.milipercent.data.seed.*"
.\gradlew.bat connectedDebugAndroidTest -Pandroid.testInstrumentationRunnerArguments.class=com.example.milipercent.data.seed.ProductionSeedAssetTest
.\gradlew.bat connectedDebugAndroidTest -Pandroid.testInstrumentationRunnerArguments.class=com.example.milipercent.data.seed.BundledSeedSynchronizerTest
git add apps/android/app/src/main/assets apps/android/app/src/main/java/com/example/milipercent/data/seed apps/android/app/src/test apps/android/app/src/androidTest
git commit -m "feat(android): seed all verified benefit data"
~~~

### Task 4: Reconcile the MMA API without duplicates or cache loss

**Files:**
- Create: `data/BenefitReconciler.kt` and `BenefitReconcilerTest.kt`
- Modify: `data/BenefitRepository.kt`, `data/local/BenefitIdentity.kt`, `BenefitLocalDataSource.kt`, analyzer and repository tests

**Interfaces:**
- Consumes: complete `MmaBenefit` pages and current `MMA_API` Room rows.
- Produces: `ReconciliationResult` and final `BenefitDataRepository`.

- [ ] **Step 1: Write failing behavior cases**

Create named tests for: matched seed retains ID/coordinates/richer text; blank cached phone is filled; repeated refresh produces the same ID; same name at different addresses remains separate; input order does not affect output; empty remote result and conflicting duplicates fail before replacement; later-page failure retains cache.

- [ ] **Step 2: Run the focused failing tests**

~~~powershell
.\gradlew.bat testDebugUnitTest --tests "com.example.milipercent.data.BenefitReconcilerTest" --tests "com.example.milipercent.data.BenefitRepositoryTest"
~~~

- [ ] **Step 3: Implement stable identity**

~~~kotlin
fun normalizedKey(name: String, address: String?): String =
    normalize(name) + "\u0000" + normalizeAddress(address)

fun mmaId(name: String, address: String?): String =
    "mma_" + sha256(normalizedKey(name, address))
~~~

Normalization trims, lowercases, removes whitespace/comma/parentheses, and folds `서울특별시/서울시`, `경기도`, and `인천광역시` to consistent prefixes. Keep the full SHA-256 digest.

- [ ] **Step 4: Implement deterministic reconciliation**

~~~kotlin
data class ReconciliationResult(
    val entities: List<BenefitEntity>,
    val matchedCount: Int,
    val addedCount: Int,
)

class BenefitReconciler {
    fun reconcile(
        existing: List<BenefitEntity>,
        remote: List<MmaBenefit>,
        syncedAt: Long,
    ): ReconciliationResult
}
~~~

Reject empty input. Group by normalized key, reject materially different duplicates, and sort keys before mapping. A matched row keeps its existing ID, coordinates, category, description, eligibility, conditions, evidence label/URL/date, and status; fill only blank phone/type from API. A new row receives deterministic ID, inferred category, MMA provenance, and `NEEDS_VERIFICATION`.

- [ ] **Step 5: Finalize repository flow**

~~~kotlin
interface BenefitDataRepository {
    fun observeBenefits(includeEnded: Boolean = false): Flow<List<Benefit>>
    fun observeBenefitById(id: String): Flow<Benefit?>
    suspend fun refreshBenefits(
        onProgress: (CollectionProgress) -> Unit = {},
    ): BenefitSyncResult
}
~~~

Collect every page, require consistent total/non-empty results, retain current-product API scope (normalized Seoul/Gyeonggi/Incheon), reconcile in memory, replace `MMA_API` once, and verify stored count. Any earlier failure leaves Room unchanged.

- [ ] **Step 6: Verify and commit**

~~~powershell
.\gradlew.bat testDebugUnitTest --tests "com.example.milipercent.data.local.BenefitIdentityTest" --tests "com.example.milipercent.data.BenefitReconcilerTest" --tests "com.example.milipercent.data.BenefitRepositoryTest" --tests "com.example.milipercent.network.*"
git add apps/android/app/src/main/java/com/example/milipercent/data apps/android/app/src/test/java/com/example/milipercent/data
git commit -m "feat(android): reconcile MMA API into Room"
~~~

### Task 5: Add Room v4 users and favorites

**Files:**
- Create: `data/local/UserEntity.kt`, `FavoriteEntity.kt`, `AccountDao.kt`, `FavoriteDao.kt`
- Create: `src/androidTest/.../data/local/AccountFavoriteDaoTest.kt`
- Modify: `BenefitDatabase.kt`, `BenefitMigrations.kt`, `BenefitMigrationTest.kt`
- Generate: Room schema `4.json`

**Interfaces:**
- Consumes: Room v3 benefits.
- Produces: `UserEntity`, `FavoriteEntity`, account/favorite DAOs, and `MIGRATION_3_4`.

- [ ] **Step 1: Write failing migration and DAO tests**

Add `migrate3To4AddsEmptyAccountTablesAndPreservesBenefits`. Assert one v3 benefit survives and users/favorites start empty. DAO tests must prove normalized-email uniqueness, favorite-pair uniqueness, per-user isolation, and cascade deletion from both parents.

- [ ] **Step 2: Run the failing tests**

~~~powershell
.\gradlew.bat connectedDebugAndroidTest -Pandroid.testInstrumentationRunnerArguments.class=com.example.milipercent.data.local.BenefitMigrationTest
.\gradlew.bat connectedDebugAndroidTest -Pandroid.testInstrumentationRunnerArguments.class=com.example.milipercent.data.local.AccountFavoriteDaoTest
~~~

- [ ] **Step 3: Define entities**

~~~kotlin
@Entity(
    tableName = "users",
    indices = [Index(value = ["email"], unique = true)],
)
data class UserEntity(
    @PrimaryKey(autoGenerate = true) val id: Long = 0,
    val email: String,
    val displayName: String,
    val passwordSalt: String,
    val passwordHash: String,
    val isAdmin: Boolean,
)

@Entity(
    tableName = "favorites",
    primaryKeys = ["userId", "benefitId"],
    foreignKeys = [
        ForeignKey(
            entity = UserEntity::class,
            parentColumns = ["id"],
            childColumns = ["userId"],
            onDelete = ForeignKey.CASCADE,
        ),
        ForeignKey(
            entity = BenefitEntity::class,
            parentColumns = ["id"],
            childColumns = ["benefitId"],
            onDelete = ForeignKey.CASCADE,
        ),
    ],
    indices = [Index("userId"), Index("benefitId")],
)
data class FavoriteEntity(
    val userId: Long,
    val benefitId: String,
    val createdAt: Long,
)
~~~

- [ ] **Step 4: Define DAOs**

~~~kotlin
@Dao
interface AccountDao {
    @Query("SELECT COUNT(*) FROM users")
    suspend fun count(): Int
    @Insert
    suspend fun insert(user: UserEntity): Long
    @Query("SELECT * FROM users WHERE email = :email LIMIT 1")
    suspend fun findByEmail(email: String): UserEntity?
    @Query("SELECT * FROM users WHERE id = :id LIMIT 1")
    fun observeById(id: Long): Flow<UserEntity?>
}

@Dao
interface FavoriteDao {
    @Query("SELECT benefitId FROM favorites WHERE userId = :userId ORDER BY createdAt DESC")
    fun observeIds(userId: Long): Flow<List<String>>
    @Query("SELECT EXISTS(SELECT 1 FROM favorites WHERE userId = :userId AND benefitId = :benefitId)")
    suspend fun contains(userId: Long, benefitId: String): Boolean
    @Insert(onConflict = OnConflictStrategy.ABORT)
    suspend fun insert(favorite: FavoriteEntity)
    @Query("DELETE FROM favorites WHERE userId = :userId AND benefitId = :benefitId")
    suspend fun delete(userId: Long, benefitId: String): Int
}
~~~

- [ ] **Step 5: Migrate and verify**

`MIGRATION_3_4` creates both tables, foreign keys, unique index, and child indices. Register all four entities at database version 4 and expose both DAOs. Do not import `military-benefits-v2.db`; the approved reset starts account tables empty.

~~~powershell
.\gradlew.bat connectedDebugAndroidTest -Pandroid.testInstrumentationRunnerArguments.class=com.example.milipercent.data.local.BenefitMigrationTest
.\gradlew.bat connectedDebugAndroidTest -Pandroid.testInstrumentationRunnerArguments.class=com.example.milipercent.data.local.AccountFavoriteDaoTest
.\gradlew.bat assembleDebug
git add apps/android/app
git commit -m "feat(android): add Room accounts and favorites"
~~~

Expected: tests PASS and schema 4 matches the entities.

### Task 6: Implement authentication and session restoration

**Files:**
- Create: `model/LocalUser.kt`
- Create: `data/account/PasswordHasher.kt`, `AccountRepository.kt`
- Create: `data/session/SessionStore.kt`
- Create: `PasswordHasherTest.kt` and `RoomAccountRepositoryTest.kt`

**Interfaces:**
- Consumes: `AccountDao` and SharedPreferences.
- Produces: `LocalUser`, `AccountRepository`, and session user-ID storage.

- [ ] **Step 1: Write failing cases**

Test same-password verification, different-salt hashes, first-user admin, later-user non-admin, trimmed lowercase unique email, invalid email/name/password, indistinguishable wrong-password/unknown-email error, and absence of plaintext password in Room.

- [ ] **Step 2: Run failing tests**

~~~powershell
.\gradlew.bat testDebugUnitTest --tests "com.example.milipercent.data.account.PasswordHasherTest"
.\gradlew.bat connectedDebugAndroidTest -Pandroid.testInstrumentationRunnerArguments.class=com.example.milipercent.data.account.RoomAccountRepositoryTest
~~~

- [ ] **Step 3: Implement user and password contracts**

~~~kotlin
data class LocalUser(
    val id: Long,
    val email: String,
    val displayName: String,
    val isAdmin: Boolean,
)
data class PasswordDigest(val saltHex: String, val hashHex: String)
class PasswordHasher(private val secureRandom: SecureRandom = SecureRandom()) {
    fun create(password: String): PasswordDigest
    fun verify(password: String, saltHex: String, expectedHashHex: String): Boolean
}
~~~

Use a random 16-byte salt, SHA-256 over salt bytes plus UTF-8 password bytes, lowercase hex storage, and `MessageDigest.isEqual` for verification. Password fields never enter `LocalUser`.

- [ ] **Step 4: Implement repository and session**

~~~kotlin
interface AccountRepository {
    fun observeUser(id: Long): Flow<LocalUser?>
    suspend fun register(email: String, displayName: String, password: String): Result<LocalUser>
    suspend fun login(email: String, password: String): Result<LocalUser>
}
~~~

The concrete type is `RoomAccountRepository(database: BenefitDatabase, passwordHasher: PasswordHasher)`.

Normalize email with `trim().lowercase(Locale.ROOT)`. Require `@`, a two-character trimmed name, and six-character password. Wrap count-plus-insert in `database.withTransaction` so only the first account is admin. Map duplicate email to `이미 등록된 이메일입니다.`; unknown email and bad password both map to `이메일 또는 비밀번호를 확인해 주세요.`.

`SessionStore` stores only `user_id` in `local-session` preferences with `userId()`, `save(LocalUser)`, and `clear()`.

- [ ] **Step 5: Verify and commit**

~~~powershell
.\gradlew.bat testDebugUnitTest --tests "com.example.milipercent.data.account.PasswordHasherTest"
.\gradlew.bat connectedDebugAndroidTest -Pandroid.testInstrumentationRunnerArguments.class=com.example.milipercent.data.account.RoomAccountRepositoryTest
git add apps/android/app/src/main/java/com/example/milipercent/model apps/android/app/src/main/java/com/example/milipercent/data/account apps/android/app/src/main/java/com/example/milipercent/data/session apps/android/app/src/test apps/android/app/src/androidTest
git commit -m "feat(android): restore local account sessions"
~~~

### Task 7: Implement favorite and administrator repositories

**Files:**
- Create: `data/favorite/FavoriteRepository.kt`
- Create: `data/admin/AdminBenefitRepository.kt`
- Create: `RoomFavoriteRepositoryTest.kt` and `RoomAdminBenefitRepositoryTest.kt`
- Modify: `BenefitDao.kt`
- Remove after consumers move: `data/manual/ManualBenefitRepository.kt`

**Interfaces:**
- Consumes: favorite/benefit DAOs and full `Benefit`.
- Produces: `FavoriteRepository` and `AdminBenefitRepository`.

- [ ] **Step 1: Write failing repository tests**

Favorite test toggles `seed-1` on/off for user 1 and asserts the emitted set. Admin tests assert create uses `manual_local_` ID/source, update preserves ID/source, end retains the row with `ENDED`, delete accepts only `MANUAL_LOCAL`, validation rejects blank required fields, and admin observation includes ended rows.

- [ ] **Step 2: Run failing tests**

~~~powershell
.\gradlew.bat connectedDebugAndroidTest -Pandroid.testInstrumentationRunnerArguments.class=com.example.milipercent.data.favorite.RoomFavoriteRepositoryTest
.\gradlew.bat connectedDebugAndroidTest -Pandroid.testInstrumentationRunnerArguments.class=com.example.milipercent.data.admin.RoomAdminBenefitRepositoryTest
~~~

- [ ] **Step 3: Implement favorites**

~~~kotlin
interface FavoriteRepository {
    fun observeIds(userId: Long): Flow<Set<String>>
    suspend fun toggle(userId: Long, benefitId: String): Boolean
}
~~~

`RoomFavoriteRepository.toggle` runs contains/delete-or-insert in one database transaction and returns the new favorite state.

- [ ] **Step 4: Implement administrator input and operations**

~~~kotlin
data class AdminBenefitInput(
    val name: String,
    val address: String,
    val latitude: Double?,
    val longitude: Double?,
    val category: String,
    val benefitType: String,
    val benefitDescription: String,
    val phone: String?,
    val eligibleTarget: String?,
    val usageCondition: String?,
    val verificationMethod: String?,
    val sourceLabel: String,
    val sourceUrl: String?,
    val lastVerifiedAt: String?,
    val status: BenefitStatus,
    val district: String?,
)
interface AdminBenefitRepository {
    fun observeAll(): Flow<List<Benefit>>
    suspend fun create(input: AdminBenefitInput): String
    suspend fun update(id: String, input: AdminBenefitInput)
    suspend fun end(id: String)
    suspend fun deleteManual(id: String): Boolean
}
~~~

The concrete type is `RoomAdminBenefitRepository(database: BenefitDatabase)`. Create assigns `manual_local_${UUID.randomUUID()}`. Update retains the existing row's ID/source. End changes only status. Delete requires `MANUAL_LOCAL`. ViewModel authorization is added in Task 8.

- [ ] **Step 5: Verify and commit**

~~~powershell
.\gradlew.bat connectedDebugAndroidTest -Pandroid.testInstrumentationRunnerArguments.class=com.example.milipercent.data.favorite.RoomFavoriteRepositoryTest
.\gradlew.bat connectedDebugAndroidTest -Pandroid.testInstrumentationRunnerArguments.class=com.example.milipercent.data.admin.RoomAdminBenefitRepositoryTest
git add apps/android/app/src/main/java/com/example/milipercent/data apps/android/app/src/androidTest
git commit -m "feat(android): add favorite and admin repositories"
~~~

### Task 8: Build immutable product state and ViewModel

**Files:**
- Create: `ui/MiliSpotUiState.kt`, `ui/DiscoverState.kt`, `ui/MiliSpotViewModel.kt`
- Create: `DiscoverStateTest.kt` and `MiliSpotViewModelTest.kt`
- Modify: `model/BenefitDistrict.kt`

**Interfaces:**
- Consumes: all repositories, `SessionStore`, and `BundledSeedSynchronizer`.
- Produces: `StateFlow<MiliSpotUiState>` and non-Android UI events.

- [ ] **Step 1: Write failing pure-state/ViewModel tests**

Prove category+district filters compose, Korean name/address search works, presets include rows within 8 km, current location controls distance only without active search, ended rows stay hidden, favorites are per user, stale session becomes logged out, missing key still installs seed, and refresh failure keeps cached rows with `refreshFailed=true`.

- [ ] **Step 2: Run failing tests**

~~~powershell
.\gradlew.bat testDebugUnitTest --tests "com.example.milipercent.ui.DiscoverStateTest" --tests "com.example.milipercent.ui.MiliSpotViewModelTest"
~~~

- [ ] **Step 3: Define state**

~~~kotlin
enum class AppDestination { DISCOVER, SAVED, ACCOUNT, ADMIN }
data class BenefitListItem(val benefit: Benefit, val distanceKm: Double?)
data class MiliSpotUiState(
    val destination: AppDestination = AppDestination.DISCOVER,
    val benefits: List<Benefit> = emptyList(),
    val visibleBenefits: List<BenefitListItem> = emptyList(),
    val savedBenefits: List<BenefitListItem> = emptyList(),
    val selectedBenefitId: String? = null,
    val user: LocalUser? = null,
    val favoriteIds: Set<String> = emptySet(),
    val selectedCategory: String = "전체",
    val selectedDistrict: BenefitDistrict = BenefitDistrict.ALL,
    val searchText: String = "",
    val activeSearch: String = "",
    val center: GeoPoint = SEOUL_CENTER,
    val currentLocation: GeoPoint? = null,
    val cameraRequestId: Long = 0,
    val locationLabel: String = "서울 전체",
    val isLoading: Boolean = true,
    val isRefreshing: Boolean = false,
    val refreshFailed: Boolean = false,
    val lastSyncLabel: String = "내장 혜택 DB",
    val transientMessage: String? = null,
)
~~~

Expose `val selectedBenefit: Benefit? get() = selectedBenefitId?.let { id -> benefits.firstOrNull { it.id == id } }` in the state body so a refresh cannot leave detail bound to a stale object.

- [ ] **Step 4: Implement pure display projection**

`createBenefitListItems` filters `ENDED`, category, district, and text/preset radius, maps Haversine distance, then sorts null distance last and name second. It uses current location only when active search is blank. Keep the exact preset labels/coordinates from `67e34fd`.

- [ ] **Step 5: Implement ViewModel orchestration**

~~~kotlin
class MiliSpotViewModel(
    private val benefitRepository: BenefitDataRepository,
    private val accountRepository: AccountRepository,
    private val favoriteRepository: FavoriteRepository,
    private val adminRepository: AdminBenefitRepository,
    private val seedSynchronizer: BundledSeedSynchronizer,
    private val sessionStore: SessionStore,
    private val mmaConfigured: Boolean,
) : ViewModel()
~~~

Initialization observes benefits, installs seed, restores/observes the session user, switches favorite flow with `flatMapLatest`, and refreshes only when MMA settings exist. Expose `navigate`, category/district selection, edit/submit/clear search, preset, select/close detail, refresh, register/login/logout, favorite toggle, admin save/end/delete, and clear-message events. Unauthorized favorite goes to ACCOUNT; unauthorized admin mutation never calls its repository.

Add `MiliSpotViewModel.Factory` with the same seven constructor dependencies so `MainActivity` remains the only composition root.

- [ ] **Step 6: Verify and commit**

~~~powershell
.\gradlew.bat testDebugUnitTest --tests "com.example.milipercent.ui.DiscoverStateTest" --tests "com.example.milipercent.ui.MiliSpotViewModelTest"
git add apps/android/app/src/main/java/com/example/milipercent/ui apps/android/app/src/main/java/com/example/milipercent/model/BenefitDistrict.kt apps/android/app/src/test/java/com/example/milipercent/ui
git commit -m "feat(android): add Room-backed MiliSpot state"
~~~

### Task 9: Restore current navigation, discover, and detail UI

**Files:**
- Modify: `navigation/BenefitRoutes.kt`
- Replace: `navigation/MiliPercentNavHost.kt` with `MiliSpotNavHost.kt`
- Create: `ui/MilitaryBenefitApp.kt` and `ui/AppTheme.kt`
- Modify: `ui/BenefitDetailScreen.kt`
- Modify/create: `BenefitNavigationTest.kt` and `DiscoverScreenTest.kt`

**Interfaces:**
- Consumes: `MiliSpotUiState` and ViewModel events.
- Produces: current visual scaffold plus stable-ID Compose navigation.

- [ ] **Step 1: Capture references and write failing UI tests**

Use `67e34fd:.../MilitaryBenefitApp.kt` and `origin/dev:.../AppTheme.kt` as visual sources, never as instructions to restore `AppController`. Tests assert title, sync label, search, category row, district row, benefit card, current-location button, detail navigation/back, and retention of selected search/category/district.

- [ ] **Step 2: Run failing UI tests**

~~~powershell
.\gradlew.bat connectedDebugAndroidTest -Pandroid.testInstrumentationRunnerArguments.class=com.example.milipercent.ui.DiscoverScreenTest
.\gradlew.bat connectedDebugAndroidTest -Pandroid.testInstrumentationRunnerArguments.class=com.example.milipercent.navigation.BenefitNavigationTest
~~~

- [ ] **Step 3: Define routes**

~~~kotlin
@Serializable data object DiscoverRoute
@Serializable data object SavedRoute
@Serializable data object AccountRoute
@Serializable data object AdminRoute
@Serializable data class BenefitDetailRoute(val benefitId: String)
~~~

Start at Discover; bottom routes use `launchSingleTop` and `restoreState`. Detail resolves the current Room item by stable ID.

- [ ] **Step 4: Port UI as state plus callbacks**

~~~kotlin
@Composable
fun MilitaryBenefitApp(
    state: MiliSpotUiState,
    navController: NavHostController,
    onNavigate: (AppDestination) -> Unit,
    onSearchTextChanged: (String) -> Unit,
    onSearch: () -> Unit,
    onPresetSelected: (String) -> Unit,
    onCategorySelected: (String) -> Unit,
    onDistrictSelected: (BenefitDistrict) -> Unit,
    onBenefitSelected: (String) -> Unit,
    onFavorite: (String) -> Unit,
    onRefresh: () -> Unit,
    onCurrentLocation: () -> Unit,
    onMessageShown: () -> Unit,
)
~~~

Port current colors, typography, spacing, top/bottom bars, hero, presets, category chips, cards, Korean copy, phone/source actions, and detail fields. Add the Room branch's district row below categories; do not redesign or remove the category row.

- [ ] **Step 5: Define complete detail boundary**

~~~kotlin
@Composable
fun BenefitDetailScreen(
    benefit: Benefit,
    isFavorite: Boolean,
    onBack: () -> Unit,
    onFavorite: () -> Unit,
    onOpenNaverMap: () -> Unit,
)
~~~

Display description, address, target, conditions, verification, phone, source/date, status, favorite, telephone, source URL, and map action.

- [ ] **Step 6: Verify and commit**

~~~powershell
.\gradlew.bat connectedDebugAndroidTest -Pandroid.testInstrumentationRunnerArguments.class=com.example.milipercent.ui.DiscoverScreenTest
.\gradlew.bat connectedDebugAndroidTest -Pandroid.testInstrumentationRunnerArguments.class=com.example.milipercent.navigation.BenefitNavigationTest
.\gradlew.bat assembleDebug
git add apps/android/app/src/main/java/com/example/milipercent/navigation apps/android/app/src/main/java/com/example/milipercent/ui apps/android/app/src/androidTest
git commit -m "feat(android): restore MiliSpot discover UI"
~~~

### Task 10: Restore Naver Map, markers, and deep links

**Files:**
- Create: `ui/NaverMapPanel.kt`
- Create: `ui/map/BenefitMapItem.kt`, `BenefitMarkerIcon.kt`, `MarkerSetSignature.kt`, `NaverMapLauncher.kt`, `NaverMapUrl.kt`
- Create/adapt: `MarkerSetSignatureTest.kt` and `NaverMapUrlTest.kt`
- Modify: `ui/MilitaryBenefitApp.kt`

**Interfaces:**
- Consumes: `Benefit`, `GeoPoint`, Naver BuildConfig, and detail callback.
- Produces: `BenefitMapItem`, `BenefitMap`, marker signature, and `Context.openNaverMap`.

- [ ] **Step 1: Write failing map tests**

Test that marker order does not change the signature; coordinate, caption, and category changes do; missing coordinates are excluded; place URL encodes name/coordinates/final app ID; and missing coordinates use search URL.

- [ ] **Step 2: Run failing tests**

~~~powershell
.\gradlew.bat testDebugUnitTest --tests "com.example.milipercent.ui.map.*"
~~~

- [ ] **Step 3: Define projection and fingerprint**

~~~kotlin
data class BenefitMapItem(
    val id: String,
    val name: String,
    val category: String,
    val latitude: Double,
    val longitude: Double,
)
fun Benefit.toMapItemOrNull(): BenefitMapItem? {
    val lat = latitude ?: return null
    val lon = longitude ?: return null
    return BenefitMapItem(id, name, category, lat, lon)
}
internal fun markerSetSignature(items: Iterable<BenefitMapItem>): String =
    items.sortedBy { it.id }.joinToString("|") {
        "${it.id}\u0000${it.name}\u0000${it.category}\u0000${it.latitude}\u0000${it.longitude}"
    }
~~~

- [ ] **Step 4: Port map behavior**

~~~kotlin
@Composable
fun BenefitMap(
    benefits: List<BenefitMapItem>,
    center: GeoPoint,
    currentLocation: GeoPoint?,
    cameraRequestId: Long,
    onSelect: (String) -> Unit,
    modifier: Modifier = Modifier,
)
~~~

Use `67e34fd` as reference. Blank key renders offline coordinate map. The real map releases markers/lifecycle in `DisposableEffect`, updates only the location overlay for passive GPS, moves camera for a changed search center or camera request ID, fingerprints all marker-visible fields, and emits stable ID on click.

- [ ] **Step 5: Port marker icon and launcher**

Adapt the current `dev` marker icon and URL/launcher. Try `com.nhn.android.nmap` first and web search second; use `context.packageName` as `appname`.

- [ ] **Step 6: Verify and commit**

~~~powershell
.\gradlew.bat testDebugUnitTest --tests "com.example.milipercent.ui.map.*"
.\gradlew.bat lintDebug assembleDebug
git add apps/android/app/src/main/java/com/example/milipercent/ui apps/android/app/src/test/java/com/example/milipercent/ui/map
git commit -m "feat(android): restore Naver Map experience"
~~~

### Task 11: Add foreground live device location

**Files:**
- Create: `location/LocationDataSource.kt`, `AndroidLocationDataSource.kt`, `LocationBehavior.kt`
- Create: `LocationBehaviorTest.kt` and `LocationViewModelTest.kt`
- Modify: `MiliSpotUiState.kt` and `MiliSpotViewModel.kt`

**Interfaces:**
- Consumes: Android `LocationManager` and map camera-request contract.
- Produces: `LocationDataSource.updates()` plus ViewModel start/stop/focus events.

- [ ] **Step 1: Port and extend failing behavior tests**

From `67e34fd` retain tests for passive center, live distance origin, pending-focus cancellation, repeated same-coordinate request IDs, and first fresh fix. Add tests that stop cancels the collection job and unavailable provider preserves benefit/search state.

- [ ] **Step 2: Run failing tests**

~~~powershell
.\gradlew.bat testDebugUnitTest --tests "com.example.milipercent.location.LocationBehaviorTest" --tests "com.example.milipercent.ui.LocationViewModelTest"
~~~

- [ ] **Step 3: Define source and constants**

~~~kotlin
sealed interface LocationUpdate {
    data class Position(val point: GeoPoint) : LocationUpdate
    data class Unavailable(val message: String) : LocationUpdate
}
interface LocationDataSource {
    fun updates(): Flow<LocationUpdate>
}
internal const val LOCATION_UPDATE_INTERVAL_MS = 5_000L
internal const val LOCATION_UPDATE_DISTANCE_METERS = 10f
~~~

`AndroidLocationDataSource` uses `callbackFlow`. Register GPS only with fine permission and network with fine/coarse permission. Emit provider failures as `Unavailable`. Always call `removeUpdates` in `awaitClose`. A last-known fix may be emitted but never replaces subscribing to fresh updates.

- [ ] **Step 4: Implement focus state**

~~~kotlin
data class LocationFocusState(
    val latestLocation: GeoPoint? = null,
    val focusPending: Boolean = false,
    val cameraRequestId: Long = 0L,
) {
    fun requestFocus() =
        if (latestLocation == null) copy(focusPending = true)
        else copy(focusPending = false, cameraRequestId = cameraRequestId + 1)
    fun cancelPendingFocus() = copy(focusPending = false)
    fun withLocation(point: GeoPoint) =
        if (focusPending) copy(
            latestLocation = point,
            focusPending = false,
            cameraRequestId = cameraRequestId + 1,
        ) else copy(latestLocation = point)
}
~~~

- [ ] **Step 5: Integrate ViewModel lifecycle events**

Add `startLocationTracking(dataSource)`, `stopLocationTracking()`, `requestCurrentLocationFocus(): Boolean`, and `locationPermissionDenied()`. Only one collection job may exist. Passive position updates set location and recompute distance, not center. A pending explicit focus updates center and increments request ID. Search/preset cancels pending focus.

- [ ] **Step 6: Verify and commit**

~~~powershell
.\gradlew.bat testDebugUnitTest --tests "com.example.milipercent.location.*" --tests "com.example.milipercent.ui.LocationViewModelTest" --tests "com.example.milipercent.ui.DiscoverStateTest"
git add apps/android/app/src/main/java/com/example/milipercent/location apps/android/app/src/main/java/com/example/milipercent/ui apps/android/app/src/test
git commit -m "fix(android): track live device location"
~~~

### Task 12: Restore Saved, Account, and Admin screens

**Files:**
- Create: `ui/AccountAdminScreens.kt` and `AccountAdminScreenTest.kt`
- Modify: `navigation/MiliSpotNavHost.kt`, `MilitaryBenefitApp.kt`, `MiliSpotViewModel.kt`

**Interfaces:**
- Consumes: user/favorite/admin state and Task 8 events.
- Produces: saved, registration/login/logout, and admin CRUD/status UI.

- [ ] **Step 1: Write failing Compose flows**

Cover logged-out favorite→Account, register, login, logout, favorite appearance in Saved, non-admin Admin rejection, admin create/edit/end/manual-delete, ended visibility only in Admin, and per-user favorites.

- [ ] **Step 2: Run failing UI test**

~~~powershell
.\gradlew.bat connectedDebugAndroidTest -Pandroid.testInstrumentationRunnerArguments.class=com.example.milipercent.ui.AccountAdminScreenTest
~~~

- [ ] **Step 3: Port state/callback screens**

~~~kotlin
@Composable
fun SavedScreen(
    items: List<BenefitListItem>,
    favoriteIds: Set<String>,
    onSelect: (String) -> Unit,
    onFavorite: (String) -> Unit,
)
@Composable
fun AccountScreen(
    user: LocalUser?,
    onRegister: suspend (String, String, String) -> Result<LocalUser>,
    onLogin: suspend (String, String) -> Result<LocalUser>,
    onLogout: () -> Unit,
)
@Composable
fun AdminScreen(
    user: LocalUser?,
    benefits: List<Benefit>,
    onSave: (AdminBenefitInput) -> Unit,
    onEnd: (String) -> Unit,
    onDeleteManual: (String) -> Unit,
)
~~~

Port current visual wording/layout from `origin/dev`. Keep form text local; persisted state remains in ViewModel/Room.

- [ ] **Step 4: Enforce UI and ViewModel authorization**

Only an admin sees Admin. Direct non-admin route returns to Account with `관리자 권한이 필요합니다.`. Logged-out favorite uses `찜을 저장하려면 먼저 로그인해 주세요.`. First-account registration message states admin grant; later login uses the normal message.

- [ ] **Step 5: Verify and commit**

~~~powershell
.\gradlew.bat connectedDebugAndroidTest -Pandroid.testInstrumentationRunnerArguments.class=com.example.milipercent.ui.AccountAdminScreenTest
.\gradlew.bat testDebugUnitTest --tests "com.example.milipercent.ui.MiliSpotViewModelTest"
.\gradlew.bat assembleDebug
git add apps/android/app/src/main/java/com/example/milipercent/ui apps/android/app/src/main/java/com/example/milipercent/navigation apps/android/app/src/androidTest
git commit -m "feat(android): restore account and admin flows"
~~~

### Task 13: Wire one app entry point and remove parallel architecture

**Files:**
- Modify: `MainActivity.kt`, strings, and themes
- Delete after replacement compiles: old `BenefitScreen`, `BenefitUiState`, `BenefitViewModel`, `BenefitDetailUiState`, `BenefitDetailViewModel`
- Delete after replacement compiles: `data/manual/ManualBenefitRepository.kt` and `ui/debug/*`
- Update/remove superseded tests only after equivalent new coverage passes

**Interfaces:**
- Consumes: Room v4, all repositories, ViewModel factory, Android location source, and root UI.
- Produces: one database, one state path, and lifecycle-safe launch.

- [ ] **Step 1: Write a failing launch smoke test**

Launch `MainActivity` with `ActivityScenario` and assert target package `com.example.militarybenefits`, non-null Room database, current MiliSpot title, and seed-backed content without an API key.

- [ ] **Step 2: Run before wiring**

~~~powershell
.\gradlew.bat connectedDebugAndroidTest -Pandroid.testInstrumentationRunnerArguments.class=com.example.milipercent.ExampleInstrumentedTest
~~~

- [ ] **Step 3: Assemble dependencies once**

~~~kotlin
val database = BenefitDatabase.getInstance(applicationContext)
val apiClient = BenefitApiClient(
    apiUrl = BuildConfig.MMA_API_URL,
    serviceKey = BuildConfig.MMA_SERVICE_KEY,
    xmlParser = BenefitXmlParser(),
)
val benefitRepository =
    BenefitRepository(apiClient, RoomBenefitLocalDataSource(database.benefitDao()))
val accountRepository = RoomAccountRepository(database, PasswordHasher())
val favoriteRepository = RoomFavoriteRepository(database)
val adminRepository = RoomAdminBenefitRepository(database)
val seedSynchronizer = BundledSeedSynchronizer(
    database,
    listOf(
        LegacyBenefitSeedLoader(AssetJsonSource(applicationContext, "benefits.seed.json")),
        ManualBenefitSeedLoader(AssetJsonSource(applicationContext, "manual_benefits_seed.json")),
    ),
)
val sessionStore = SessionStore(applicationContext)
val locationDataSource = AndroidLocationDataSource(applicationContext)
~~~

Pass these through `MiliSpotViewModel.Factory`; no Composable constructs repositories.

- [ ] **Step 4: Wire permission and foreground lifecycle**

Use `RequestMultiplePermissions`. Any location grant starts tracking; denial calls `locationPermissionDenied`. `onStart` resumes only a previously requested tracker with permission. `onStop` stops tracking before `super.onStop()`. The location button requests focus first, then permission/tracking if no fix exists.

- [ ] **Step 5: Remove obsolete paths and scan**

Delete listed files only after new tests pass. Preserve any old test that covers a behavior absent from the new suite.

~~~powershell
rg -n "SQLiteOpenHelper|AppController|com\.example\.militarybenefits\.(data|ui)" apps/android/app/src
~~~

Expected: no matches. The application ID remains in build/tests/docs, not a second Kotlin package.

- [ ] **Step 6: Run full automation and commit**

~~~powershell
.\gradlew.bat lintDebug testDebugUnitTest assembleDebug
.\gradlew.bat connectedDebugAndroidTest
git add apps/android/app
git commit -m "refactor(android): complete Room app composition"
~~~

Instrumentation unavailability keeps this task open until Task 14.

### Task 14: Prove parity and prepare the local release candidate

**Files:**
- Modify: `apps/android/README.md`, `docs/current-status.md`, `docs/local-development.md`
- Modify when architecture text differs: `docs/architecture.md`
- Create: `docs/verification/2026-09-04-android-room-final-integration.md`

**Interfaces:**
- Consumes: complete integration and current remote `dev`.
- Produces: reproducible evidence and reviewed local candidate; no GitHub mutation.

- [ ] **Step 1: Run the clean automated gate**

~~~powershell
.\gradlew.bat --version
.\gradlew.bat clean lintDebug testDebugUnitTest assembleDebug
.\gradlew.bat connectedDebugAndroidTest
~~~

Record timestamps, commit, Java 17 daemon line, device/API level, and exact outcomes.

- [ ] **Step 2: Verify data/cache on emulator**

After clearing app data, record initial 496 rows; source counts 311 LOCAL_GOV, 159 MMA_API, 14 PUBLIC_EVIDENCE, 12 MANUAL_SEED; 484 coordinate pairs; no-key browsing; full configured pagination; forced later-page cache retention; repeat-refresh deduplication; category, district, Korean, and radius search.

- [ ] **Step 3: Verify map/GPS on emulator**

Record Naver authentication under final app ID, 484 initial markers subject to display cap, stable-ID click/detail, app/web deep link, simulated movement, passive no-camera-chase, repeated recenter, delayed-fix search protection, background stop/foreground resume, denial and later grant.

- [ ] **Step 4: Verify user features on emulator**

Record first-admin/later-user registration, duplicate/bad-login messages, logout/stale session, per-user favorite persistence, admin create/edit/end/manual-delete, ended filtering, and favorite cascade.

- [ ] **Step 5: Verify a physical device**

Record model, OS/API, commit, map authentication, permission deny/grant/retry, actual position, movement-driven marker/distance, passive camera stability, same-position recenter, lifecycle stop/resume, and search/detail/login/favorite/admin smoke flows. Emulator coordinates cannot satisfy this gate.

- [ ] **Step 6: Update accurate documentation**

Document Room v4 as sole database, app ID, both local key names, 496 initial rows/484 coordinates, integrated map/location/account/favorite/admin features, and the server-proxy requirement before public release.

- [ ] **Step 7: Inspect hygiene**

~~~powershell
git status --short
git diff --check origin/feature/android-room-integration...HEAD
git ls-files apps/android/local.properties apps/android/app/build apps/android/.gradle
rg -n "MMA_SERVICE_KEY=.{12,}|NAVER_MAP_NCP_KEY_ID=.{12,}" apps/android docs
rg -n "SQLiteOpenHelper|AppController" apps/android/app/src
~~~

Expected: no tracked secrets/build output, obsolete paths, or whitespace errors.

- [ ] **Step 8: Recheck remote dev**

~~~powershell
git fetch origin
git log --oneline 39a5d3570895bead2fba0de7fa74f9a1731dce9a..origin/dev
~~~

If commits appear, inspect each Android/data change, merge `origin/dev` locally while preserving both feature sets, and repeat affected gates. If none appear, record `39a5d35` as current.

- [ ] **Step 9: Obtain independent review**

Invoke `superpowers:requesting-code-review` on the full branch diff. Fix every Critical or Important finding with a focused failing test, rerun its gate, then rerun the full automated gate.

- [ ] **Step 10: Commit evidence and stop before GitHub**

~~~powershell
git add apps/android/README.md docs/current-status.md docs/local-development.md docs/verification/2026-09-04-android-room-final-integration.md
git commit -m "docs: record Android Room integration verification"
~~~

Include `docs/architecture.md` only when changed. Present commit range, tests, device results, data counts, review findings, limitations, and confirmation that no push/PR/`dev` merge occurred. Wait for explicit user authorization before any GitHub mutation.
