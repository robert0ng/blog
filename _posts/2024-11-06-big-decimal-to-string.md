---
author: robertwang
layout: post
title:  Things about calling toString on BigDecimal 
date:   2024-11-06
tags: 
  - BigDeciaml
  - Bank

---

# The Trade-offs Between toString() and toPlainString() in BigDecimal

## Introduction

In financial applications, precise decimal representation is crucial. Recently, our team debated the use of `toString()` versus `toPlainString()` when working with BigDecimal values. This article explores the performance implications and practical considerations of both methods.

## Performance Analysis

To quantify the performance difference, we conducted a benchmark comparing both methods across various number types:

```kotlin
val numbers = listOf(
    BigDecimal("12345.56789"),             // Regular number
    BigDecimal("1234567890.0123456789"),   // Regular number with high precision
    BigDecimal("1E20"),                    // Very large number
    BigDecimal("1E-8"),                    // Very small number
    BigDecimal("999999999999999999.999999999999999999") // Large precision
)

val iterations = 1_000_000

numbers.forEach { number ->
    println("\nTesting with number: $number")
    
    val toStringTime = measureNanoTime {
        repeat(iterations) {
            number.toString()
        }
    }

    val toPlainStringTime = measureNanoTime {
        repeat(iterations) {
            number.toPlainString()
        }
    }

    println("toString() took: ${toStringTime / iterations} ns per call")
    println("toPlainString() took: ${toPlainStringTime / iterations} ns per call")
    println("toPlainString() is ${toPlainStringTime.toFloat() / toStringTime.toFloat()}x slower")
}
```

### Results

The performance difference is significant and varies based on the number of digits:

```
Testing with number: 12345.56789
toString() took: 3 ns per call
toPlainString() took: 44 ns per call
toPlainString() is 11.48x slower

Testing with number: 1234567890.0123456789
toString() took: 3 ns per call
toPlainString() took: 241 ns per call
toPlainString() is 63.91x slower

Testing with number: 1E+20
toString() took: 1 ns per call
toPlainString() took: 61 ns per call
toPlainString() is 48.25x slower
```

## Real-world Implications

In our banking application, we frequently need to display the difference between two BigDecimal values, typically for scenarios like:
- Showing account balance
- Calculating required additional deposits for purchases
- Displaying transaction amounts

### Edge Case Analysis

We tested various scenarios to understand when scientific notation might appear:

```kotlin
val a = BigDecimal("1")
val b = BigDecimal("0.00000000000000100001")
val result = a - b
println("1 - 0.00000000000000100001 = ${result.toString()} (Plain: ${result.toPlainString()})")

val largeA = BigDecimal("1000000000000000000000")
val largeB = BigDecimal("999999999999999999999")
val largeResult = largeA - largeB
println("Large number subtraction = ${largeResult.toString()} (Plain: ${largeResult.toPlainString()})")
```

Our tests revealed that `toString()` produces scientific notation primarily with very small differences:
```
Very small difference:
1.000000000000000000001 - 1 = 1E-21 (Plain: 0.000000000000000000001)
```

## The Solution

To balance performance with user experience, we implemented a hybrid approach:

```kotlin
fun BigDecimal.toStringWithoutE(): String {
    val asString = this.toString()
    return if (asString.contains('E')) {
        this.toPlainString()
    } else {
        asString
    }
}
```

This solution:
1. Initially uses the faster `toString()`
2. Falls back to `toPlainString()` only when scientific notation is detected
3. Ensures readable output for users while maintaining optimal performance in most cases

## Conclusion

While `toPlainString()` is significantly slower than `toString()`, the hybrid approach provides an excellent balance between performance and usability. For financial applications where user experience is crucial, this compromise ensures both efficient processing and clear, understandable number representation.

