package com.example.milipercent.data.account

import androidx.room.withTransaction
import com.example.milipercent.data.local.BenefitDatabase
import com.example.milipercent.data.local.UserEntity
import com.example.milipercent.model.LocalUser
import java.util.Locale
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map

interface AccountRepository {
    fun observeUser(id: Long): Flow<LocalUser?>

    suspend fun register(email: String, displayName: String, password: String): Result<LocalUser>

    suspend fun login(email: String, password: String): Result<LocalUser>
}

class RoomAccountRepository(
    private val database: BenefitDatabase,
    private val passwordHasher: PasswordHasher,
) : AccountRepository {
    override fun observeUser(id: Long): Flow<LocalUser?> =
        database.accountDao().observeById(id).map { user -> user?.toLocalUser() }

    override suspend fun register(
        email: String,
        displayName: String,
        password: String,
    ): Result<LocalUser> = runCatching {
        val normalizedEmail = normalizeEmail(email)
        val normalizedName = displayName.trim()
        validateRegistration(normalizedEmail, normalizedName, password)
        database.withTransaction {
            val dao = database.accountDao()
            if (dao.findByEmail(normalizedEmail) != null) {
                throw AccountValidationException(DUPLICATE_EMAIL_MESSAGE)
            }
            val digest = passwordHasher.create(password)
            val isAdmin = dao.count() == 0
            val id = dao.insert(
                UserEntity(
                    email = normalizedEmail,
                    displayName = normalizedName,
                    passwordSalt = digest.saltHex,
                    passwordHash = digest.hashHex,
                    isAdmin = isAdmin,
                ),
            )
            LocalUser(id, normalizedEmail, normalizedName, isAdmin)
        }
    }

    override suspend fun login(email: String, password: String): Result<LocalUser> = runCatching {
        val user = database.accountDao().findByEmail(normalizeEmail(email))
        if (user == null || !passwordHasher.verify(password, user.passwordSalt, user.passwordHash)) {
            throw AccountValidationException(INVALID_CREDENTIALS_MESSAGE)
        }
        user.toLocalUser()
    }

    private fun validateRegistration(email: String, displayName: String, password: String) {
        if (!email.contains('@')) throw AccountValidationException("올바른 이메일을 입력해 주세요.")
        if (displayName.length < 2) throw AccountValidationException("이름은 두 글자 이상 입력해 주세요.")
        if (password.length < 6) throw AccountValidationException("비밀번호는 여섯 글자 이상 입력해 주세요.")
    }

    private fun normalizeEmail(email: String): String = email.trim().lowercase(Locale.ROOT)

    private fun UserEntity.toLocalUser() = LocalUser(id, email, displayName, isAdmin)

    private companion object {
        const val DUPLICATE_EMAIL_MESSAGE = "이미 등록된 이메일입니다."
        const val INVALID_CREDENTIALS_MESSAGE = "이메일 또는 비밀번호를 확인해 주세요."
    }
}

class AccountValidationException(message: String) : IllegalArgumentException(message)
