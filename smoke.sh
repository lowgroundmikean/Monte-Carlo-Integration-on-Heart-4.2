#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# smoke.sh - sixty-second check on the login node before committing to sbatch.
#
# Builds the program and runs the smallest possible case on 4 cores. If this
# passes, the batch job will build and run; if it fails, it fails here in a
# second instead of after sitting in the queue.
#
# Usage:  bash smoke.sh
# ---------------------------------------------------------------------------

set -uo pipefail

cd "$(dirname "$0")"

. ./mpienv.sh
load_mpi || exit 1

set -e

echo
echo "compiler: $(mpicc --version 2>&1 | head -1)"
echo

mpicc -O3 -std=c99 -o heart_mc heart_mc.c -lm
echo "build OK"
echo

# Four ranks, ten thousand points each, two seeds. Runs instantly.
# p = 4 is a perfect square, which Method 3 requires.
echo "--- 4 ranks, n=10000, 2 seeds ---"
mpirun -n 4 ./heart_mc 10000 2 smoke

echo
echo "If the estimates above sit near 3.66 and the relative errors are small,"
echo "everything works. Submit with:  sbatch run42.slurm"
