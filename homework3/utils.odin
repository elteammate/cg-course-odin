package main

dynamic_into_slice :: proc(data: [dynamic]$T) -> []T {
    result := make([]T, len(data))
    copy(result, data[:])
    delete(data)
    return result
}

sqr :: proc(x: $T) -> T {
    return x * x
}
