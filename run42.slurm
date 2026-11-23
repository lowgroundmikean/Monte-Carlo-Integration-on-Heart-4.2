#!/usr/bin/env bash
#SBATCH --job-name=heart_mc
#SBATCH --output=heart_mc_%j.out
#SBATCH --error=heart_mc_%j.err
#SBATCH --partition=short-96core
#SBATCH --nodes=1
#SBATCH --ntasks=64
#SBATCH --time=01:00:00

# ---------------------------------------------------------------------------
# AMS 530 Project 4, Problem 4.2
# Monte Carlo area of a heart: plain vs. stratified sampling
# Michael Guerrero
#
# All three core counts (16, 36, 64) fit inside a single 96-core AMD Milan
# node, so every measurement comes from identical hardware with no traffic
# across the interconnect. That is deliberate: this experiment measures
# statistical error, and inter-node variance would add noise unrelated to the
# quantity being studied.
#
# Runs the nine required tasks at 30 seeds each, then three supplementary
# runs at 200 seeds. Total compute is a couple of minutes; the hour of
# walltime is slack.
#
# Submit with:  sbatch run42.slurm
# ---------------------------------------------------------------------------

set -uo pipefail

cd "$SLURM_SUBMIT_DIR"

. ./mpienv.sh
load_mpi || exit 1

set -e

echo "host      : $(hostname)"
echo "date      : $(date)"
echo "job id    : $SLURM_JOB_ID"
echo "partition : $SLURM_JOB_PARTITION"
echo "compiler  : $(mpicc --version 2>&1 | head -1)"
echo

# No -march=native: the point of this experiment is sample counts, and the
# results should not depend on which node the scheduler happened to pick.
mpicc -O3 -std=c99 -o heart_mc heart_mc.c -lm
echo "build OK"
echo

# --- Pick a launcher -------------------------------------------------------
# mvapich2 and OpenMPI disagree about whether srun or mpirun is the supported
# path inside an allocation, so settle it empirically.
#
# The probe must use more than one rank and must check that the ranks found
# each other. A launcher that starts the processes without wiring up PMI
# leaves every one of them as rank 0 of its own world of size 1, which does
# not fail, it silently produces p copies of a one-rank result. So the test
# is that the program reports the process count it was actually given.
probe_launcher () {
    local reported
    reported=$($1 4 ./heart_mc 200 1 probe 2>/dev/null \
               | awk -F, 'NR==2 {print $3}')
    [ "$reported" = "4" ]
}

LAUNCH=""
for cand in "mpirun -n" "srun --mpi=pmi2 -n" "srun -n"; do
    if probe_launcher "$cand"; then
        LAUNCH="$cand"
        break
    fi
    echo "launcher  : rejected '$cand' (ranks did not form one communicator)"
done

if [ -z "$LAUNCH" ]; then
    echo "ERROR: no launcher produced a working multi-rank communicator." >&2
    exit 1
fi
echo "launcher  : $LAUNCH"
echo

OUT="results_${SLURM_JOB_ID}.csv"
HDR=0

run_task () {                 # run_task <task> <p> <n_per_core> <seeds>
    local task=$1 p=$2 n=$3 s=$4
    echo ">>> task=$task p=$p n=$n seeds=$s   ($(date +%H:%M:%S))"
    if [ "$HDR" -eq 0 ]; then
        $LAUNCH "$p" ./heart_mc "$n" "$s" "$task" >> "$OUT"
        HDR=1
    else
        $LAUNCH "$p" ./heart_mc "$n" "$s" "$task" | tail -n +2 >> "$OUT"
    fi
}

# --- Required experiments, 30 seeds each -----------------------------------
#   Task   p    n per core    total p*n
run_task A1  16     360000  30      # 5.76e6
run_task A2  16    3600000  30      # 5.76e7
run_task A3  16   36000000  30      # 5.76e8

run_task B1  36     160000  30      # 5.76e6
run_task B2  36    1600000  30      # 5.76e7
run_task B3  36   16000000  30      # 5.76e8

# --- Bonus, p = 64 ---------------------------------------------------------
run_task C1  64      90000  30      # 5.76e6
run_task C2  64     900000  30      # 5.76e7
run_task C3  64    9000000  30      # 5.76e8

# --- Supplementary, 200 seeds at the smallest sample count -----------------
# Thirty seeds leaves roughly a 13% standard error on each dispersion
# estimate, which is wider than the gap between plain sampling and vertical
# slices. These runs cost seconds and resolve what the required 30 cannot.
run_task S16 16     360000 200
run_task S36 36     160000 200
run_task S64 64      90000 200

echo
echo "wrote $OUT  ($(wc -l < "$OUT") lines)"
echo "done: $(date)"
