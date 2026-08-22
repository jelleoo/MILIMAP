package com.example.milipercent.ui

import android.util.Log
import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import com.example.milipercent.data.BenefitDataRepository
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

class BenefitDetailViewModel(
    private val benefitId: String,
    private val repository: BenefitDataRepository,
) : ViewModel() {
    private val _uiState = MutableStateFlow<BenefitDetailUiState>(
        BenefitDetailUiState.Loading,
    )
    val uiState: StateFlow<BenefitDetailUiState> = _uiState.asStateFlow()

    init {
        observeBenefit()
    }

    private fun observeBenefit() {
        if (benefitId.isBlank()) {
            _uiState.value = BenefitDetailUiState.NotFound
            return
        }

        viewModelScope.launch {
            try {
                repository.observeBenefitById(benefitId).collect { benefit ->
                    _uiState.value = createBenefitDetailUiState(benefit)
                }
            } catch (exception: CancellationException) {
                throw exception
            } catch (exception: Exception) {
                Log.e(TAG, "Room 상세 관찰 실패: ${exception.javaClass.simpleName}")
                _uiState.value = BenefitDetailUiState.Error
            }
        }
    }

    class Factory(
        private val benefitId: String,
        private val repository: BenefitDataRepository,
    ) : ViewModelProvider.Factory {
        @Suppress("UNCHECKED_CAST")
        override fun <T : ViewModel> create(modelClass: Class<T>): T {
            if (modelClass.isAssignableFrom(BenefitDetailViewModel::class.java)) {
                return BenefitDetailViewModel(
                    benefitId = benefitId,
                    repository = repository,
                ) as T
            }
            throw IllegalArgumentException("지원하지 않는 ViewModel입니다: ${modelClass.name}")
        }
    }

    private companion object {
        const val TAG = "BenefitDetailVM"
    }
}
