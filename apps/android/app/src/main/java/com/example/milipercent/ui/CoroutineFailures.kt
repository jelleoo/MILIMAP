package com.example.milipercent.ui

import kotlinx.coroutines.CancellationException

internal inline fun <T> runCatchingPreservingCancellation(block: () -> T): Result<T> = try {
    Result.success(block())
} catch (exception: CancellationException) {
    throw exception
} catch (exception: Throwable) {
    Result.failure(exception)
}
