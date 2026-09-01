package com.mtog.core

class LatestValueQueue<T>(val capacity: Int) {
    init { require(capacity > 0) }

    private val storage = ArrayDeque<T>()
    val values: List<T> get() = storage.toList()

    fun append(value: T): T? {
        val dropped = if (storage.size == capacity) storage.removeFirst() else null
        storage.addLast(value)
        return dropped
    }

    fun removeFirstOrNull(): T? = if (storage.isEmpty()) null else storage.removeFirst()
}
