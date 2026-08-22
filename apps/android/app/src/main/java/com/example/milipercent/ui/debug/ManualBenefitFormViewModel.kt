package com.example.milipercent.ui.debug

import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import com.example.milipercent.data.manual.ManualBenefitAdminRepository
import com.example.milipercent.data.manual.ManualBenefitInput
import com.example.milipercent.data.manual.ManualBenefitRecord
import com.example.milipercent.ui.runCatchingPreservingCancellation
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

data class ManualBenefitFormUiState(
    val isLoading: Boolean,
    val isSaving: Boolean = false,
    val existing: ManualBenefitRecord? = null,
    val savedId: String? = null,
    val errorMessage: String? = null,
)

class ManualBenefitFormViewModel(
    private val benefitId: String?,
    private val repository: ManualBenefitAdminRepository,
) : ViewModel() {
    private val _uiState = MutableStateFlow(
        ManualBenefitFormUiState(isLoading = benefitId != null),
    )
    val uiState: StateFlow<ManualBenefitFormUiState> = _uiState.asStateFlow()

    init {
        if (benefitId != null) observeExisting(benefitId)
    }

    private fun observeExisting(id: String) {
        viewModelScope.launch {
            runCatchingPreservingCancellation {
                repository.observeById(id).collect { record ->
                    _uiState.value = if (record == null) {
                        ManualBenefitFormUiState(
                            isLoading = false,
                            errorMessage = "수정할 MANUAL_LOCAL 혜택을 찾을 수 없습니다.",
                        )
                    } else {
                        _uiState.value.copy(isLoading = false, existing = record)
                    }
                }
            }.onFailure { exception ->
                _uiState.value = ManualBenefitFormUiState(
                    isLoading = false,
                    errorMessage = exception.message ?: "혜택을 불러오지 못했습니다.",
                )
            }
        }
    }

    fun save(input: ManualBenefitInput) {
        if (_uiState.value.isSaving) return
        _uiState.value = _uiState.value.copy(isSaving = true, errorMessage = null)
        viewModelScope.launch {
            runCatchingPreservingCancellation {
                if (benefitId == null) {
                    repository.create(input)
                } else {
                    repository.update(benefitId, input)
                    benefitId
                }
            }.onSuccess { savedId ->
                _uiState.value = _uiState.value.copy(
                    isSaving = false,
                    savedId = savedId,
                )
            }.onFailure { exception ->
                _uiState.value = _uiState.value.copy(
                    isSaving = false,
                    errorMessage = exception.message ?: "저장하지 못했습니다.",
                )
            }
        }
    }

    class Factory(
        private val benefitId: String?,
        private val repository: ManualBenefitAdminRepository,
    ) : ViewModelProvider.Factory {
        @Suppress("UNCHECKED_CAST")
        override fun <T : ViewModel> create(modelClass: Class<T>): T {
            if (modelClass.isAssignableFrom(ManualBenefitFormViewModel::class.java)) {
                return ManualBenefitFormViewModel(benefitId, repository) as T
            }
            throw IllegalArgumentException("지원하지 않는 ViewModel입니다: ${modelClass.name}")
        }
    }
}
