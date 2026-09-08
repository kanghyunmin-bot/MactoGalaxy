package com.mtog.core

data class ReconnectPolicy(
    val maxAttempts: Int,
    val baseDelaySeconds: Int,
    val maximumDelaySeconds: Int
) {
    init {
        require(maxAttempts > 0 && baseDelaySeconds > 0 && maximumDelaySeconds >= baseDelaySeconds)
    }

    fun delaySeconds(attempt: Int): Int? {
        if (attempt !in 1..maxAttempts) return null
        var delay = baseDelaySeconds
        repeat(attempt - 1) {
            if (delay >= maximumDelaySeconds) return maximumDelaySeconds
            delay = (delay * 2).coerceAtMost(maximumDelaySeconds)
        }
        return delay
    }
}
