#!/usr/bin/env python3
"""N-Queens benchmark — Python 3"""

import os
import time


def n_queens(n):
    def invalid(soln_so_far, row, col):
        return any(
            col == c or abs(row - r) == abs(col - c)
            for r, c in soln_so_far
        )

    def place_on_row(soln_so_far, row):
        result = []
        for col in range(n):
            if not invalid(soln_so_far, row, col):
                result.append(soln_so_far + [(row, col)])
        return result

    solutions = [[(0, col)] for col in range(n)]
    for row in range(1, n):
        next_solutions = []
        for soln in solutions:
            next_solutions.extend(place_on_row(soln, row))
        solutions = next_solutions
    return solutions


nqueen_n = int(os.environ.get("SEED_NQUEEN", "14"))

start = time.monotonic()
result = len(n_queens(nqueen_n))
elapsed = time.monotonic() - start

print(f"{result} solutions")
print(f"    {elapsed:.9f}s elapsed real time")
