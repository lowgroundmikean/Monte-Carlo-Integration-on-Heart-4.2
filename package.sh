#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# package.sh - build the source tarball the Common Projects Instructions ask
# for, the same way psor.tar was built for Project 3.
#
# Includes source, scripts and raw measurements, so the results in the report
# can be regenerated from the archive alone. Excludes the compiled binary,
# which is machine specific and would not run anywhere else anyway.
#
# Usage:  bash package.sh
# ---------------------------------------------------------------------------

set -euo pipefail

cd "$(dirname "$0")"

TAR=heart42.tar

rm -f "$TAR"

FILES="heart_mc.c mpienv.sh smoke.sh run42.slurm analyze.py package.sh"

for f in $FILES; do
    [ -f "$f" ] || { echo "missing: $f" >&2; exit 1; }
done

tar -cf "$TAR" $FILES

# Raw per-seed measurements and job logs, if the run has happened.
for f in results_*.csv heart_mc_*.out heart_mc_*.err summary.txt \
         fig_loglog.png; do
    [ -f "$f" ] && tar -rf "$TAR" "$f"
done

echo "wrote $TAR"
tar -tf "$TAR"
