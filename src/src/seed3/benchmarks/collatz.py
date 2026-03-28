#!/usr/bin/env python3
"""Collatz benchmark — Python 3"""

import os
import time


def collatz_length(n):
    x, steps = n, 0
    while x != 1:
        if x % 2 == 0:
            x = x // 2
        else:
            x = 3 * x + 1
        steps += 1
    return steps


def find_longest_collatz(limit):
    best_n, best_len = 1, 0
    for i in range(1, limit):
        length = collatz_length(i)
        if length > best_len:
            best_n, best_len = i, length
    return [best_n, best_len]


def count_special(limit):
    count = 0
    for i in range(1, limit):
        div3 = i % 3 == 0
        div7 = i % 7 == 0
        both = div3 and div7
        neither = (not div3) and (not div7)
        if both or neither:
            count += 1
    return count


collatz_limit = int(os.environ.get("SEED_COLLATZ", "20000000"))
special_limit = int(os.environ.get("SEED_SPECIAL", "40000000"))

start = time.monotonic()
print(f"Collatz: {find_longest_collatz(collatz_limit)}")
print(f"Special: {count_special(special_limit)}")
elapsed = time.monotonic() - start
print(f"    {elapsed:.9f}s elapsed real time")
