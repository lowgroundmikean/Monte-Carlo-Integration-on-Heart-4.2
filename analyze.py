#!/usr/bin/env python3
"""
analyze.py - turn the raw per-seed CSV into the tables Project 4 asks for.

Written against the standard library alone, because matplotlib is not
reliably importable on SeaWulf's compute nodes. If matplotlib does happen to
be present it also writes the log-log figure; otherwise it prints the plot
data in a block that can be pasted elsewhere to draw it.

Usage:  python3 analyze.py results_<jobid>.csv
"""

import csv
import math
import sys
from collections import defaultdict

A_REF = 3.66197

# The three methods the assignment requires. Horizontal slices are an
# addition of ours, reported separately as the evidence for Report Q3.
REQUIRED = ["1_whole_box", "2V_vertical_slices", "3_cells"]
EXTRA = "2H_horizontal_slices"
ALL_METHODS = REQUIRED + [EXTRA]

LABEL = {
    "1_whole_box": "M1 whole box",
    "2V_vertical_slices": "M2 vertical",
    "2H_horizontal_slices": "M2 horizontal",
    "3_cells": "M3 cells",
}

REQUIRED_TASKS = ["A1", "A2", "A3", "B1", "B2", "B3"]
BONUS_TASKS = ["C1", "C2", "C3"]
SUPP_TASKS = ["S16", "S36", "S64"]

NAN = float("nan")


def stats(values):
    """Mean, sample standard deviation, and RMS of a list of numbers."""
    n = len(values)
    if n == 0:
        return NAN, NAN, NAN
    mean = sum(values) / n
    var = sum((v - mean) ** 2 for v in values) / (n - 1) if n > 1 else 0.0
    rms = math.sqrt(sum(v * v for v in values) / n)
    return mean, math.sqrt(var), rms


def load(path):
    """Read the CSV into per-(task, method) error lists plus task metadata."""
    err = defaultdict(list)
    total = {}
    pcount = {}

    with open(path, newline="") as fh:
        for row in csv.DictReader(fh):
            task = row["task"]
            key = (task, row["method"])
            err[key].append(float(row["rel_error"]))
            total[key] = float(row["total_samples"])
            pcount[task] = int(row["p"])

    return err, total, pcount


def main(path):
    err, total, pcount = load(path)
    seen = {t for t, _ in err}

    def table(title, task_list, methods):
        print()
        print(title)
        print("-" * len(title))
        print(f"{'task':<5} {'p':>4} {'total N':>11} {'method':<16}"
              f"{'mean rel err':>14} {'std':>12} {'RMS':>12} {'seeds':>7}")
        for t in task_list:
            if t not in seen:
                continue
            for mth in methods:
                key = (t, mth)
                if key not in err:
                    continue
                mean, sd, rms = stats(err[key])
                print(f"{t:<5} {pcount[t]:>4} {total[key]:>11.3g} "
                      f"{LABEL[mth]:<16}{mean:>14.4e} {sd:>12.3e} "
                      f"{rms:>12.4e} {len(err[key]):>7}")

    print("=" * 80)
    print("PROBLEM 4.2  Monte Carlo area of a heart: plain vs. stratified")
    print(f"reference area A = {A_REF}")
    print("=" * 80)

    table("REQUIRED: 18 data points (6 tasks x 3 methods), 30 seeds each",
          REQUIRED_TASKS, REQUIRED)

    table("BONUS: 9 data points (3 tasks x 3 methods), 30 seeds each",
          BONUS_TASKS, REQUIRED)

    table("SUPPLEMENTARY: horizontal slices, evidence for Report Q3",
          REQUIRED_TASKS + BONUS_TASKS, [EXTRA])

    table("SUPPLEMENTARY: 200 seeds at N = 5.76e6, to resolve close methods",
          SUPP_TASKS, ALL_METHODS)

    # ---- Report Q2: does stratification reduce the error, by what factor --
    print()
    print("Q2  STRATIFICATION GAIN: RMS relative error / Method 1's")
    print("-" * 62)
    print(f"{'task':<6}{'M2 vertical':>14}{'M2 horizontal':>16}"
          f"{'M3 cells':>12}")
    for t in REQUIRED_TASKS + BONUS_TASKS + SUPP_TASKS:
        base_key = (t, "1_whole_box")
        if base_key not in err:
            continue
        base = stats(err[base_key])[2]
        if not base:
            continue
        ratios = []
        for mth in ["2V_vertical_slices", EXTRA, "3_cells"]:
            key = (t, mth)
            ratios.append(stats(err[key])[2] / base if key in err else NAN)
        print(f"{t:<6}{ratios[0]:>14.3f}{ratios[1]:>16.3f}"
              f"{ratios[2]:>12.3f}")
    print()
    print("Below 1 means the method beat plain Monte Carlo.")
    print("Square these to get the variance reduction factor.")

    # ---- Report Q4: scaling in p at fixed N -------------------------------
    print()
    print("Q4  BONUS: RMS relative error at fixed total N, as p grows")
    print("-" * 62)
    groups = ((["A1", "B1", "C1"], "N = 5.76e6, 30 seeds"),
              (["A2", "B2", "C2"], "N = 5.76e7, 30 seeds"),
              (["A3", "B3", "C3"], "N = 5.76e8, 30 seeds"),
              (SUPP_TASKS, "N = 5.76e6, 200 seeds"))
    for group, label in groups:
        if not any(t in seen for t in group):
            continue
        print()
        print(f"  {label}")
        header = "".join(f"{'p=' + str(pcount.get(t, '?')):>15}"
                         for t in group)
        print(f"  {'method':<16}{header}")
        for mth in ALL_METHODS:
            cells = "".join(
                f"{stats(err[(t, mth)])[2]:>15.4e}" if (t, mth) in err
                else f"{'-':>15}" for t in group)
            print(f"  {LABEL[mth]:<16}{cells}")
    print()
    print("Prediction: Method 3 scales as N^(-1/2) p^(-1/4); Methods 1 and 2")
    print("carry no p dependence once N is held fixed.")

    # ---- plot data --------------------------------------------------------
    panels = ((16, ["A1", "A2", "A3"]),
              (36, ["B1", "B2", "B3"]),
              (64, ["C1", "C2", "C3"]))

    print()
    print("PLOT DATA  (mean relative error vs total samples, log-log)")
    print("-" * 62)
    print("p,method,total_samples,mean_rel_err,rms_rel_err")
    for p_val, group in panels:
        for mth in ALL_METHODS:
            for t in group:
                key = (t, mth)
                if key not in err:
                    continue
                mean, _, rms = stats(err[key])
                print(f"{p_val},{LABEL[mth]},{total[key]:.0f},"
                      f"{mean:.6e},{rms:.6e}")

    try:
        import matplotlib
        matplotlib.use("Agg")
        import matplotlib.pyplot as plt
    except Exception as exc:
        print()
        print(f"[matplotlib unavailable: {exc}]")
        print("[paste the PLOT DATA block above to draw the figure elsewhere]")
        return

    fig, axes = plt.subplots(1, 3, figsize=(15, 4.6), sharey=True)
    for ax, (p_val, group) in zip(axes, panels):
        anchor_x, anchor_y = [], []
        for mth in ALL_METHODS:
            xs, ys = [], []
            for t in group:
                key = (t, mth)
                if key in err:
                    xs.append(total[key])
                    ys.append(stats(err[key])[0])
            if xs:
                ax.loglog(xs, ys, "o-", label=LABEL[mth])
                if not anchor_x:
                    anchor_x, anchor_y = xs, ys
        if anchor_x:
            x0, x1 = min(anchor_x), max(anchor_x)
            y0 = anchor_y[0]
            ax.loglog([x0, x1], [y0, y0 * (x0 / x1) ** 0.5],
                      "k--", lw=1, label="slope $-1/2$")
        ax.set_title(f"$p = {p_val}$")
        ax.set_xlabel("total samples $N = p\\,n$")
        ax.grid(True, which="both", alpha=0.3)
    axes[0].set_ylabel(r"mean $|\hat{A} - A| / A$")
    axes[0].legend(fontsize=8)
    fig.tight_layout()
    fig.savefig("fig_loglog.png", dpi=200)
    print()
    print("wrote fig_loglog.png")


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(1)
    main(sys.argv[1])
