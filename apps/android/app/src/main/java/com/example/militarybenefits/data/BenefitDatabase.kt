package com.example.militarybenefits.data

import android.content.ContentValues
import android.content.Context
import android.database.Cursor
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper
import org.json.JSONArray
import java.security.MessageDigest
import java.security.SecureRandom
import java.util.UUID

class BenefitDatabase(private val appContext: Context) :
    SQLiteOpenHelper(appContext, "military-benefits-v2.db", null, 2) {

    private val mmaCoordinateIndex by lazy { MmaCoordinateIndex.fromAssets(appContext) }

    override fun onCreate(db: SQLiteDatabase) {
        db.execSQL(
            """CREATE TABLE benefits(
                id TEXT PRIMARY KEY, name TEXT NOT NULL, address TEXT NOT NULL,
                latitude REAL, longitude REAL, category TEXT NOT NULL,
                benefit_type TEXT NOT NULL, benefit_description TEXT NOT NULL,
                phone TEXT, eligible_target TEXT, usage_condition TEXT,
                verification_method TEXT, source_type TEXT NOT NULL,
                source_label TEXT NOT NULL, source_url TEXT, last_verified_at TEXT,
                status TEXT NOT NULL, district TEXT
            )""".trimIndent(),
        )
        db.execSQL(
            """CREATE TABLE users(
                id INTEGER PRIMARY KEY AUTOINCREMENT, email TEXT UNIQUE NOT NULL,
                display_name TEXT NOT NULL, password_salt TEXT NOT NULL,
                password_hash TEXT NOT NULL, is_admin INTEGER NOT NULL DEFAULT 0
            )""".trimIndent(),
        )
        db.execSQL(
            """CREATE TABLE favorites(
                user_id INTEGER NOT NULL, benefit_id TEXT NOT NULL,
                created_at INTEGER NOT NULL,
                PRIMARY KEY(user_id, benefit_id),
                FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE,
                FOREIGN KEY(benefit_id) REFERENCES benefits(id) ON DELETE CASCADE
            )""".trimIndent(),
        )
        db.execSQL("CREATE INDEX idx_benefit_status_category ON benefits(status, category)")
        db.execSQL("CREATE INDEX idx_favorite_user ON favorites(user_id, created_at)")
        seedBenefits(db)
    }

    override fun onUpgrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) {
        if (oldVersion < 2) backfillMmaCoordinates(db)
    }

    fun allBenefits(includeEnded: Boolean = false): List<Benefit> {
        val where = if (includeEnded) null else "status != ?"
        val args = if (includeEnded) null else arrayOf(BenefitStatus.ENDED.name)
        return readableDatabase.query(
            "benefits", null, where, args, null, null,
            "CASE status WHEN 'ACTIVE' THEN 0 ELSE 1 END, name COLLATE NOCASE",
        ).use { cursor -> buildList { while (cursor.moveToNext()) add(cursor.toBenefit()) } }
    }

    fun benefit(id: String): Benefit? = readableDatabase.query(
        "benefits", null, "id = ?", arrayOf(id), null, null, null, "1",
    ).use { if (it.moveToFirst()) it.toBenefit() else null }

    fun createBenefit(benefit: Benefit) {
        writableDatabase.insertOrThrow("benefits", null, benefit.values())
    }

    fun updateBenefit(benefit: Benefit) {
        writableDatabase.update("benefits", benefit.values(includeId = false), "id = ?", arrayOf(benefit.id))
    }

    fun endBenefit(id: String) {
        writableDatabase.update(
            "benefits",
            ContentValues().apply { put("status", BenefitStatus.ENDED.name) },
            "id = ?",
            arrayOf(id),
        )
    }

    fun mergeMmaStores(stores: List<MmaStore>): Pair<Int, Int> {
        val capitalArea = stores.filter { store ->
            store.address.startsWith("서울") || store.address.startsWith("경기") ||
                store.address.startsWith("인천")
        }
        val existing = allBenefits(includeEnded = true)
            .associateBy { normalizedBenefitKey(it.name, it.address) }
        val knownKeys = existing.keys.toMutableSet()
        var added = 0
        var matched = 0
        writableDatabase.beginTransaction()
        try {
            capitalArea.forEach { store ->
                val key = normalizedBenefitKey(store.name, store.address)
                val local = existing[key]
                val cachedCoordinate = mmaCoordinateIndex.find(store.name, store.address)
                if (local != null) {
                    matched += 1
                    val values = ContentValues()
                    if (local.phone.isNullOrBlank() && !store.phone.isNullOrBlank()) {
                        values.put("phone", store.phone)
                    }
                    if ((local.latitude == null || local.longitude == null) && cachedCoordinate != null) {
                        values.put("latitude", cachedCoordinate.latitude)
                        values.put("longitude", cachedCoordinate.longitude)
                    }
                    if (values.size() > 0) {
                        writableDatabase.update(
                            "benefits",
                            values,
                            "id = ?",
                            arrayOf(local.id),
                        )
                    }
                } else if (knownKeys.add(key)) {
                    val identity = "mma|${store.rowNumber}|${store.name}|${store.address}"
                    val id = "mma-${MessageDigest.getInstance("SHA-256")
                        .digest(identity.toByteArray()).toHex().take(12)}"
                    val benefit = Benefit(
                        id = id,
                        name = store.name,
                        address = store.address.ifBlank { "주소 확인 필요" },
                        latitude = cachedCoordinate?.latitude,
                        longitude = cachedCoordinate?.longitude,
                        category = inferCategory(store.benefitGroup, store.name),
                        benefitType = store.benefitGroup ?: "나라사랑가게 우대",
                        benefitDescription = store.benefitGroup?.let { "$it 분야 나라사랑가게 우대" }
                            ?: "나라사랑가게 우대 혜택 — 세부 내용은 업소에 확인",
                        phone = store.phone,
                        eligibleTarget = "병역이행자(현역병·사회복무요원·동원훈련 이수자·병역명문가 등)",
                        usageCondition = "세부 혜택과 적용 조건은 방문 전 업소에 확인",
                        verificationMethod = "복무확인서 등 병역이행 확인자료",
                        sourceType = "MMA_API",
                        sourceLabel = "병무청 나라사랑가게 API",
                        sourceUrl = "https://www.mma.go.kr/about/udgg/list.do?mc=mma0003357",
                        lastVerifiedAt = java.time.LocalDate.now().toString(),
                        status = BenefitStatus.NEEDS_VERIFICATION,
                        district = extractRegion(store.address),
                    )
                    writableDatabase.insertWithOnConflict(
                        "benefits", null, benefit.values(), SQLiteDatabase.CONFLICT_IGNORE,
                    )
                    added += 1
                }
            }
            writableDatabase.setTransactionSuccessful()
        } finally {
            writableDatabase.endTransaction()
        }
        return added to matched
    }

    fun favoriteIds(userId: Long): Set<String> = readableDatabase.query(
        "favorites", arrayOf("benefit_id"), "user_id = ?", arrayOf(userId.toString()),
        null, null, "created_at DESC",
    ).use { cursor -> buildSet { while (cursor.moveToNext()) add(cursor.getString(0)) } }

    fun toggleFavorite(userId: Long, benefitId: String): Boolean {
        val exists = readableDatabase.rawQuery(
            "SELECT 1 FROM favorites WHERE user_id = ? AND benefit_id = ?",
            arrayOf(userId.toString(), benefitId),
        ).use { it.moveToFirst() }
        if (exists) {
            writableDatabase.delete(
                "favorites", "user_id = ? AND benefit_id = ?",
                arrayOf(userId.toString(), benefitId),
            )
            return false
        }
        writableDatabase.insertOrThrow(
            "favorites", null, ContentValues().apply {
                put("user_id", userId)
                put("benefit_id", benefitId)
                put("created_at", System.currentTimeMillis())
            },
        )
        return true
    }

    fun register(email: String, displayName: String, password: String): Result<LocalUser> = runCatching {
        require(email.contains("@")) { "올바른 이메일을 입력해 주세요." }
        require(displayName.trim().length >= 2) { "이름을 2자 이상 입력해 주세요." }
        require(password.length >= 6) { "비밀번호를 6자 이상 입력해 주세요." }
        val firstAccount = readableDatabase.rawQuery("SELECT COUNT(*) FROM users", null).use {
            it.moveToFirst(); it.getLong(0) == 0L
        }
        val salt = ByteArray(16).also(SecureRandom()::nextBytes).toHex()
        val id = writableDatabase.insertOrThrow(
            "users", null, ContentValues().apply {
                put("email", email.trim().lowercase())
                put("display_name", displayName.trim())
                put("password_salt", salt)
                put("password_hash", hashPassword(password, salt))
                put("is_admin", if (firstAccount) 1 else 0)
            },
        )
        LocalUser(id, email.trim().lowercase(), displayName.trim(), firstAccount)
    }.recoverCatching { error ->
        if (error.message?.contains("UNIQUE") == true) {
            throw IllegalArgumentException("이미 등록된 이메일입니다.")
        }
        throw error
    }

    fun login(email: String, password: String): Result<LocalUser> = runCatching {
        readableDatabase.query(
            "users", null, "email = ?", arrayOf(email.trim().lowercase()),
            null, null, null, "1",
        ).use { cursor ->
            require(cursor.moveToFirst()) { "이메일 또는 비밀번호를 확인해 주세요." }
            val salt = cursor.text("password_salt")
            require(cursor.text("password_hash") == hashPassword(password, salt)) {
                "이메일 또는 비밀번호를 확인해 주세요."
            }
            cursor.toUser()
        }
    }

    fun user(id: Long): LocalUser? = readableDatabase.query(
        "users", null, "id = ?", arrayOf(id.toString()), null, null, null, "1",
    ).use { if (it.moveToFirst()) it.toUser() else null }

    private fun seedBenefits(db: SQLiteDatabase) {
        val json = appContext.assets.open("benefits.seed.json").bufferedReader().use { it.readText() }
        val array = JSONArray(json)
        db.beginTransaction()
        try {
            for (index in 0 until array.length()) {
                val item = array.getJSONObject(index)
                db.insertOrThrow(
                    "benefits", null, ContentValues().apply {
                        put("id", item.getString("id"))
                        put("name", item.getString("name"))
                        put("address", item.getString("address"))
                        putNullableDouble("latitude", item, "latitude")
                        putNullableDouble("longitude", item, "longitude")
                        put("category", item.getString("category"))
                        put("benefit_type", item.optString("benefitType", "할인"))
                        put("benefit_description", item.getString("benefitDescription"))
                        putNullable("phone", item, "phone")
                        putNullable("eligible_target", item, "eligibleTarget")
                        putNullable("usage_condition", item, "usageCondition")
                        putNullable("verification_method", item, "verificationMethod")
                        put("source_type", item.optString("sourceType", "MANUAL"))
                        put("source_label", item.optString("sourceLabel", "운영팀 직접 확인"))
                        putNullable("source_url", item, "sourceUrl")
                        putNullable("last_verified_at", item, "lastVerifiedAt")
                        put("status", item.optString("status", BenefitStatus.NEEDS_VERIFICATION.name))
                        putNullable("district", item, "district")
                    },
                )
            }
            db.setTransactionSuccessful()
        } finally {
            db.endTransaction()
        }
    }

    private fun backfillMmaCoordinates(db: SQLiteDatabase) {
        val updates = buildList {
            db.query(
                "benefits",
                arrayOf("id", "name", "address"),
                "source_type = ? AND (latitude IS NULL OR longitude IS NULL)",
                arrayOf("MMA_API"),
                null,
                null,
                null,
            ).use { cursor ->
                while (cursor.moveToNext()) {
                    val coordinate = mmaCoordinateIndex.find(cursor.text("name"), cursor.text("address"))
                        ?: continue
                    add(Triple(cursor.text("id"), coordinate.latitude, coordinate.longitude))
                }
            }
        }
        if (updates.isEmpty()) return
        updates.forEach { (id, latitude, longitude) ->
            db.update(
                "benefits",
                ContentValues().apply {
                    put("latitude", latitude)
                    put("longitude", longitude)
                },
                "id = ?",
                arrayOf(id),
            )
        }
    }

    companion object {
        fun newManualBenefit(): Benefit = Benefit(
            id = "manual-${UUID.randomUUID()}", name = "", address = "",
            latitude = null, longitude = null, category = "음식", benefitType = "할인",
            benefitDescription = "", phone = null, eligibleTarget = "현역 군인",
            usageCondition = null, verificationMethod = "군인 신분 확인자료",
            sourceType = "MANUAL", sourceLabel = "운영팀 직접 확인", sourceUrl = null,
            lastVerifiedAt = java.time.LocalDate.now().toString(),
            status = BenefitStatus.NEEDS_VERIFICATION, district = null,
        )
    }
}

private fun ContentValues.putNullable(column: String, item: org.json.JSONObject, key: String) {
    if (item.isNull(key) || item.optString(key).isBlank()) putNull(column) else put(column, item.optString(key))
}

private fun ContentValues.putNullableDouble(column: String, item: org.json.JSONObject, key: String) {
    if (item.isNull(key)) putNull(column) else put(column, item.optDouble(key))
}

private fun Benefit.values(includeId: Boolean = true) = ContentValues().apply {
    if (includeId) put("id", id)
    put("name", name); put("address", address)
    if (latitude == null) putNull("latitude") else put("latitude", latitude)
    if (longitude == null) putNull("longitude") else put("longitude", longitude)
    put("category", category); put("benefit_type", benefitType)
    put("benefit_description", benefitDescription)
    putOrNull("phone", phone); putOrNull("eligible_target", eligibleTarget)
    putOrNull("usage_condition", usageCondition); putOrNull("verification_method", verificationMethod)
    put("source_type", sourceType); put("source_label", sourceLabel)
    putOrNull("source_url", sourceUrl); putOrNull("last_verified_at", lastVerifiedAt)
    put("status", status.name); putOrNull("district", district)
}

private fun ContentValues.putOrNull(key: String, value: String?) {
    if (value.isNullOrBlank()) putNull(key) else put(key, value)
}

private fun Cursor.toBenefit() = Benefit(
    id = text("id"), name = text("name"), address = text("address"),
    latitude = nullableDouble("latitude"), longitude = nullableDouble("longitude"),
    category = text("category"), benefitType = text("benefit_type"),
    benefitDescription = text("benefit_description"), phone = nullableText("phone"),
    eligibleTarget = nullableText("eligible_target"), usageCondition = nullableText("usage_condition"),
    verificationMethod = nullableText("verification_method"), sourceType = text("source_type"),
    sourceLabel = text("source_label"), sourceUrl = nullableText("source_url"),
    lastVerifiedAt = nullableText("last_verified_at"),
    status = runCatching { BenefitStatus.valueOf(text("status")) }.getOrDefault(BenefitStatus.NEEDS_VERIFICATION),
    district = nullableText("district"),
)

private fun Cursor.toUser() = LocalUser(
    id = getLong(getColumnIndexOrThrow("id")), email = text("email"),
    displayName = text("display_name"), isAdmin = getInt(getColumnIndexOrThrow("is_admin")) == 1,
)

private fun Cursor.text(name: String) = getString(getColumnIndexOrThrow(name))
private fun Cursor.nullableText(name: String): String? = getColumnIndexOrThrow(name).let { if (isNull(it)) null else getString(it) }
private fun Cursor.nullableDouble(name: String): Double? = getColumnIndexOrThrow(name).let { if (isNull(it)) null else getDouble(it) }
private fun ByteArray.toHex() = joinToString("") { "%02x".format(it) }
private fun hashPassword(password: String, salt: String) = MessageDigest.getInstance("SHA-256")
    .digest("$salt:$password".toByteArray()).toHex()

private fun inferCategory(group: String?, name: String): String {
    val value = "${group.orEmpty()} $name"
    return when {
        Regex("음식|외식|식당|고기|치킨|피자|분식").containsMatchIn(value) -> "음식"
        Regex("카페|커피|제과|베이커리").containsMatchIn(value) -> "카페"
        Regex("미용|이발|헤어|뷰티").containsMatchIn(value) -> "미용·뷰티"
        Regex("숙박|호텔|펜션|모텔").containsMatchIn(value) -> "숙박"
        Regex("병원|의원|약국|안경|의료").containsMatchIn(value) -> "병원"
        Regex("영화|문화|스포츠|여가").containsMatchIn(value) -> "문화·여가"
        else -> "기타"
    }
}

private fun extractRegion(address: String): String? = Regex(
    "(?:서울(?:특별시)?|경기(?:도)?|인천(?:광역시)?)\\s+([^\\s]+(?:구|시|군))",
).find(address)?.groupValues?.getOrNull(1)
