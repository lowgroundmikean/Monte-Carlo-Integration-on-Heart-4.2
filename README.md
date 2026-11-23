# Stratified Monte Carlo Integration of a Planar Heart
 
**Michael Guerrero** · AMS 530: Principles of Parallel Computing · Project 4, Problem 4.2
Department of Applied Mathematics and Statistics, Stony Brook University
 
An MPI study of how much variance stratified sampling removes from a hit-or-miss
Monte Carlo integral, how that gain depends on the orientation of the strata, and
how it scales with the number of strata.
 
---
 
## Results at a glance
 
- **108 experiments**, each over 30 independent random streams, ≈ 2.4 × 10¹¹ sample
  evaluations, 43 seconds of wall time on one Sapphire Rapids node.
- Every estimator converges at **N^(−1/2)**. Stratification shifts the constant,
  never the exponent. Twelve fitted log-log slopes all land within 0.04 of −0.500
  except one three-point fit whose own scatter is comparable.
- Unstratified dispersion matches the closed form **0.62562 · N^(−1/2)** to within
  6%, with no fitted parameters.
- Variance reduction predicted **a priori** from stratum occupancies reproduces the
  measurements to within 10% in eight of nine cases.
| p | | vertical slices | horizontal slices | √p × √p cells |
|---|---|---|---|---|
| 16 | predicted / measured | 1.226 / 1.291 | 1.707 / 1.736 | 1.927 / 2.112 |
| 36 | predicted / measured | 1.234 / 0.986 | 1.738 / 1.619 | 2.751 / 2.769 |
| 64 | predicted / measured | 1.235 / 1.378 | 1.747 / 1.615 | 3.592 / 3.417 |
 
*Variance reduction factor G relative to unstratified sampling.*
 
**Two findings worth the detour:**
 
1. **Slicing is anisotropic.** Horizontal slices remove ~40% more variance than
   vertical ones. The curve contains `x` only through `x²`, so it is symmetric
   left-to-right but not top-to-bottom, and one-dimensional stratification removes
   exactly the variance of the chord profile along the slicing axis.
2. **1-D stratification saturates in p; 2-D stratification does not.** For cells of
   side ∝ p^(−1/2), a boundary of finite length meets a vanishing fraction p^(−1/2)
   of them, so refinement keeps converting mixed strata into pure ones. Every
   vertical slice is cut by the boundary at every p, so refinement purifies nothing.
---
 
## The problem
 
Estimate the area enclosed by the sextic curve
 
```
(x² + y² − 1)³ − x² y³ = 0
```
 
with `A ≈ 3.66197`, inside the bounding box with corners `(−1.13903, −1)` and
`(1.13903, 1.23666)`, of area `B ≈ 5.09525`.
 
Four allocations of a fixed budget of `p × n` samples:
 
| Method | Partition |
|---|---|
| 1 | every rank samples the whole box; the p estimates are averaged |
| 2V | p equal **vertical** slices, one per rank |
| 2H | p equal **horizontal** slices, one per rank |
| 3 | √p × √p equal **cells**, one per rank |
 
Method 2H is not required by the assignment. It exists because the third report
question asks whether vertical and horizontal slices differ, and that cannot be
answered without measuring it.
 
---
 
## Repository contents
 
| File | Purpose |
|---|---|
| `heart_mc.c` | MPI program. All four methods, one `(p, n)` configuration per invocation. |
| `mpienv.sh` | Toolchain discovery, sourced by both the smoke test and the batch job. |
| `smoke.sh` | 30-second login-node check: builds and runs 4 ranks before queueing. |
| `run42.slurm` | Full campaign: tasks A1–A3, B1–B3, C1–C3 at 30 streams, plus three 200-stream supplementary runs. |
| `analyze.py` | CSV → required tables, stratification factors, scaling tables, plot data. Standard library only. |
| `build_report.py` | Generates the report PDF from the raw CSV. |
| `package.sh` | Builds `heart42.tar` for submission. |
| `results_2451063.csv` | Raw per-stream measurements, 3480 rows. |
| `summary.txt` | Full analysis output. |
| `fig_loglog.png` | Convergence figure, one panel per core count. |
| `AMS530_Project4_Problem4.2.pdf` | The report. |
 
---
 
## Reproducing
 
```bash
bash smoke.sh                       # verify toolchain and build
sbatch run42.slurm                  # ~43 s of compute
python3 analyze.py results_*.csv | tee summary.txt
python3 build_report.py             # needs matplotlib + reportlab
```
 
Results are reproducible to the last printed digit. The estimates depend only on
`(method, stream, rank)` through the generator seeding, so they are independent of
core count, node, and launcher.
 
---
 
## Two implementation notes
 
**All four methods share one reduction.** Method 1 averages p whole-box estimates:
 
```
(1/p) Σ_k B · (h_k / n)  =  Σ_k (B/p) · (h_k / n)
```
 
which is precisely the sum the stratified methods form over p strata of area `B/p`.
The methods differ only in the rectangle each rank samples. One `MPI_Reduce` serves
all four, which makes the comparison as controlled as it can be made.
 
**Stream independence is not a formality.** Seeding with `seed + rank` produces
correlated streams, because most generators map nearby seeds to nearby states. The
failure is silent: estimates look reasonable while the across-stream dispersion,
which is the entire object of this study, is biased. Each `(method, stream, rank)`
triple is instead hashed into a 64-bit key and expanded through SplitMix64 into the
state of a xoshiro256++ generator.
 
---
 
## A failure mode worth publishing
 
An early run launched under a resource manager that never established the MPI
communicator left **every process as rank 0 of a singleton world**. No error was
raised. The job completed. The output was plausible: each rank independently sampled
the whole box, so all four methods silently degenerated to Method 1.
 
It was caught only because the output row count was 39× the expected value. A
launcher that starts processes without connecting them produces wrong answers rather
than error messages. `run42.slurm` now probes each candidate launcher with four ranks
and rejects any that does not report back a process count of four.
 
---
 
## Validation
 
| Check | Result |
|---|---|
| Bounding box area from stated corners | 5.095246 vs. 5.09525 |
| Area from an independent 6000² occupancy grid | 3.661977 vs. 3.66197 (7 s.f.) |
| Unstratified dispersion vs. closed form | within 6% |
| Independent serial implementation, different hardware, no MPI | p = 16 results identical to every printed digit |
