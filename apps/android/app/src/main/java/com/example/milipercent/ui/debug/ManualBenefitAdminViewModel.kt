package com.example.milipercent.ui.debug

import android.util.Log
import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import com.example.milipercent.data.manual.ManualBenefitAdminRepository
import com.example.milipercent.data.manual.ManualBenefitRecord
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

data class ManualBenefitAdminUiState(
    val isLoading: Boolean = true,
    val benefits: List<ManualBenefitRecord> = emptyList(),
    val errorMessage: String? = null,
)

class ManualBenefitAdminViewModel(
    private val repository: ManualBenefitAdminRepository,
) : ViewModel() {
    private val _uiState = MutableStateFlow(ManualBenefitAdminUiState())
    val uiState: StateFlow<ManualBenefitAdminUiState> = _uiState.asStateFlow()

    init {
        Log.d(TAG, "MANUAL_LOCAL 관리자 목록 관찰 시작")
        viewModelScope.launch {
            runCatching {
                repository.observeAll().collect { benefits ->
                    Log.d(TAG, "MANUAL_LOCAL 관리자 목록: ${benefits.size}건")
                    _uiState.value = ManualBenefitAdminUiState(
                        isLoading = false,
                        benefits = benefits,
                    )
                }
            }.onFailure { exception ->
                Log.e(TAG, "MANUAL_LOCAL 관리자 목록 실패", exception)
                _uiState.value = ManualBenefitAdminUiState(
                    isLoading = false,
                    errorMessage = exception.message ?: "MANUAL_LOCAL 목록을 불러오지 못했습니다.",
                )
            }
        }
    }

    fun delete(id: String) {
        viewModelScope.launch {
            runCatching { repository.delete(id) }
                .onFailure { exception ->
                    _uiState.value = _uiState.value.copy(
                        errorMessage = exception.message ?: "삭제하지 못했습니다.",
                    )
                }
        }
    }

    class Factory(
        private val repository: ManualBenefitAdminRepository,
    ) : ViewModelProvider.Factory {
        @Suppress("UNCHECKED_CAST")
        override fun <T : ViewModel> create(modelClass: Class<T>): T {
            if (modelClass.isAssignableFrom(ManualBenefitAdminViewModel::class.java)) {
                return ManualBenefitAdminViewModel(repository) as T
            }
            throw IllegalArgumentException("지원하지 않는 ViewModel입니다: ${modelClass.name}")
        }
    }

    private companion object {
        const val TAG = "ManualBenefitAdminVM"
    }
}
