/*
 * Problem 4.2 - Monte Carlo area of a heart: plain vs. stratified sampling.
 *
 * AMS 530 Parallel Computing, Project 4
 * Michael Guerrero
 *
 * The planar heart is the zero set of
 *
 *     F(x,y) = (x^2 + y^2 - 1)^3 - x^2 y^3,
 *
 * with the interior given by F < 0 (F(0,0) = -1). Its area is estimated by
 * hit-or-miss sampling inside the bounding box
 *
 *     [-1.13903, 1.13903] x [-1, 1.23666],   area B = 5.09525.
 *
 * Four allocations of the same p*n total samples are compared:
 *
 *   METHOD 1  every rank samples the whole box; the p estimates are averaged.
 *   METHOD 2V the box is cut into p equal vertical slices, one per rank.
 *   METHOD 2H the box is cut into p equal horizontal slices, one per rank.
 *   METHOD 3  the box is cut into sqrt(p) x sqrt(p) equal cells, one per rank.
 *
 * Method 2H is not required by the assignment; it is included because the
 * report asks whether vertical and horizontal slices give the same error,
 * and the cheapest way to answer that is to measure it.
 *
 * A convenient identity: method 1 averages p whole-box estimates,
 *
 *     (1/p) * sum_k B * (h_k / n) = sum_k (B/p) * (h_k / n),
 *
 * which is exactly the sum the stratified methods form over their p equal
 * strata. So all four methods reduce with the same expression, and only the
 * sampling region differs between them. One MPI_Reduce serves all four.
 *
 * Usage:  mpirun -n <p> ./heart_mc <n_per_core> <n_seeds> [task]
 * Output: CSV on stdout from rank 0, one row per (method, seed):
 *   task,method,p,n_per_core,total_samples,seed,estimate,rel_error,seconds
 */

#include <mpi.h>
#include <math.h>
#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

/* ------------------------------------------------------------------ */
/* Geometry                                                            */
/* ------------------------------------------------------------------ */

#define XLO (-1.13903)
#define XHI ( 1.13903)
#define YLO (-1.00000)
#define YHI ( 1.23666)

/* Reference area of the heart, supplied with the assignment. */
#define A_REF 3.66197

#define N_METHODS 4

static const char *METHOD_NAME[N_METHODS] = {
    "1_whole_box", "2V_vertical_slices", "2H_horizontal_slices", "3_cells"
};

/*
 * Returns nonzero when (x,y) lies inside the heart.
 *
 * Evaluating (x^2+y^2-1) once and cubing it by two multiplications keeps the
 * kernel at ten floating point operations, which matters only because this
 * test is executed 2.3e11 times over the full experiment.
 */
static inline int inside_heart(double x, double y)
{
    double t  = x * x + y * y - 1.0;
    double yy = y * y;
    return (t * t * t - x * x * yy * y) < 0.0;
}

/* ------------------------------------------------------------------ */
/* Random number generation                                            */
/* ------------------------------------------------------------------ */

/*
 * Parallel Monte Carlo is only as trustworthy as the independence of its
 * streams. Seeding a library generator with seed+rank is the classic error:
 * neighbouring seeds produce streams whose early output is correlated, which
 * silently biases the across-seed statistics this experiment is built on.
 *
 * Instead each (method, seed, rank) triple is hashed into a 64-bit key, and
 * that key is expanded through SplitMix64 into the 256-bit state of a
 * xoshiro256++ generator. SplitMix64 is the seeding procedure its authors
 * recommend precisely because it decorrelates nearby keys.
 */

typedef struct { uint64_t s[4]; } rng_t;

static uint64_t splitmix64(uint64_t *state)
{
    uint64_t z = (*state += 0x9E3779B97F4A7C15ULL);
    z = (z ^ (z >> 30)) * 0xBF58476D1CE4E5B9ULL;
    z = (z ^ (z >> 27)) * 0x94D049BB133111EBULL;
    return z ^ (z >> 31);
}

static void rng_init(rng_t *r, int method, int seed, int rank)
{
    uint64_t key = (uint64_t)(seed   + 1) * 0x9E3779B97F4A7C15ULL
                 ^ (uint64_t)(rank   + 1) * 0xBF58476D1CE4E5B9ULL
                 ^ (uint64_t)(method + 1) * 0x94D049BB133111EBULL;

    for (int i = 0; i < 4; i++) {
        r->s[i] = splitmix64(&key);
    }
}

static inline uint64_t rotl64(uint64_t x, int k)
{
    return (x << k) | (x >> (64 - k));
}

static inline uint64_t rng_next(rng_t *r)
{
    uint64_t *s = r->s;
    uint64_t result = rotl64(s[0] + s[3], 23) + s[0];
    uint64_t t = s[1] << 17;

    s[2] ^= s[0];
    s[3] ^= s[1];
    s[1] ^= s[2];
    s[0] ^= s[3];
    s[2] ^= t;
    s[3] = rotl64(s[3], 45);

    return result;
}

/* Uniform on [0,1), using the top 53 bits so every double is reachable. */
static inline double rng_u01(rng_t *r)
{
    return (double)(rng_next(r) >> 11) * 0x1.0p-53;
}

/* ------------------------------------------------------------------ */
/* Stratum assignment                                                  */
/* ------------------------------------------------------------------ */

/*
 * Computes this rank's sampling rectangle for the given method.
 *
 * Preconditions: for method 3, p must be a perfect square.
 * Postcondition: [*x0,*x1] x [*y0,*y1] is this rank's region. The p regions
 * partition the bounding box for methods 2V, 2H and 3, and each equals the
 * whole box for method 1.
 */
static void stratum(int method, int rank, int p,
                    double *x0, double *x1, double *y0, double *y1)
{
    double w = XHI - XLO;
    double h = YHI - YLO;

    switch (method) {
    case 0:                                   /* whole box */
        *x0 = XLO; *x1 = XHI;
        *y0 = YLO; *y1 = YHI;
        break;

    case 1:                                   /* vertical slices */
        *x0 = XLO + w *  rank      / p;
        *x1 = XLO + w * (rank + 1) / p;
        *y0 = YLO; *y1 = YHI;
        break;

    case 2:                                   /* horizontal slices */
        *x0 = XLO; *x1 = XHI;
        *y0 = YLO + h *  rank      / p;
        *y1 = YLO + h * (rank + 1) / p;
        break;

    default: {                                /* sqrt(p) x sqrt(p) cells */
        int m = (int)(sqrt((double)p) + 0.5);
        int i = rank % m;
        int j = rank / m;

        *x0 = XLO + w *  i      / m;
        *x1 = XLO + w * (i + 1) / m;
        *y0 = YLO + h *  j      / m;
        *y1 = YLO + h * (j + 1) / m;
        break;
    }
    }
}

/* ------------------------------------------------------------------ */
/* Main                                                                */
/* ------------------------------------------------------------------ */

int main(int argc, char **argv)
{
    int rank, p;

    MPI_Init(&argc, &argv);
    MPI_Comm_rank(MPI_COMM_WORLD, &rank);
    MPI_Comm_size(MPI_COMM_WORLD, &p);

    if (argc < 3) {
        if (rank == 0) {
            fprintf(stderr,
                    "usage: %s <n_per_core> <n_seeds> [tag]\n", argv[0]);
        }
        MPI_Finalize();
        return 1;
    }

    long n_per_core = atol(argv[1]);
    int  n_seeds    = atoi(argv[2]);
    const char *tag = (argc > 3) ? argv[3] : "run";

    int m = (int)(sqrt((double)p) + 0.5);

    if (m * m != p) {
        if (rank == 0) {
            fprintf(stderr,
                    "error: p = %d is not a perfect square, so method 3 "
                    "cannot tile the box.\n", p);
        }
        MPI_Finalize();
        return 1;
    }

    double box_area = (XHI - XLO) * (YHI - YLO);

    if (rank == 0) {
        fprintf(stderr, "# tag=%s p=%d n_per_core=%ld total=%.6g seeds=%d\n",
                tag, p, n_per_core, (double)p * (double)n_per_core, n_seeds);
        printf("task,method,p,n_per_core,total_samples,seed,estimate,"
               "rel_error,seconds\n");
    }

    for (int method = 0; method < N_METHODS; method++) {

        double x0, x1, y0, y1;
        stratum(method, rank, p, &x0, &x1, &y0, &y1);

        double dx = x1 - x0;
        double dy = y1 - y0;

        for (int seed = 0; seed < n_seeds; seed++) {

            rng_t r;
            rng_init(&r, method, seed, rank);

            MPI_Barrier(MPI_COMM_WORLD);
            double t_start = MPI_Wtime();

            long hits = 0;

            for (long i = 0; i < n_per_core; i++) {
                double x = x0 + dx * rng_u01(&r);
                double y = y0 + dy * rng_u01(&r);

                hits += inside_heart(x, y);
            }

            /*
             * Every method contributes (B/p) * (hits/n) from each rank: the
             * stratified methods because each stratum has area B/p, and
             * method 1 because averaging p whole-box estimates divides each
             * by p. One reduction therefore covers all four.
             */
            double local = (box_area / p) * ((double)hits / (double)n_per_core);
            double total = 0.0;

            MPI_Reduce(&local, &total, 1, MPI_DOUBLE, MPI_SUM, 0,
                       MPI_COMM_WORLD);

            double t_end = MPI_Wtime();

            if (rank == 0) {
                double rel_err = fabs(total - A_REF) / A_REF;

                printf("%s,%s,%d,%ld,%.0f,%d,%.10f,%.6e,%.4f\n",
                       tag, METHOD_NAME[method], p, n_per_core,
                       (double)p * (double)n_per_core, seed,
                       total, rel_err, t_end - t_start);
                fflush(stdout);
            }
        }
    }

    MPI_Finalize();
    return 0;
}
