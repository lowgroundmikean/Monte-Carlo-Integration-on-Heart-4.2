# ---------------------------------------------------------------------------
# mpienv.sh - locate a WORKING MPI compiler on SeaWulf's Milan nodes.
#
# Sourced by both smoke.sh and run42.slurm so the interactive check and the
# batch job cannot disagree about which toolchain they use.
#
# Note on why this is more careful than it looks: an mpicc inherited from the
# retired Xeon login nodes stays on PATH but fails at runtime with
#
#     error while loading shared libraries: libpmix.so.2
#
# because its runtime is not installed on the AMD nodes. Testing for the
# presence of mpicc is therefore not enough; it has to be executed.
#
# Deliberately does NOT run "module purge": on SeaWulf that can strip the
# Slurm commands out of the environment and the job dies before it starts.
# ---------------------------------------------------------------------------

# True only if mpicc both exists and can actually execute.
mpicc_works () {
    command -v mpicc >/dev/null 2>&1 && mpicc --version >/dev/null 2>&1
}

load_mpi () {
    # Discovery probes are expected to fail, so relax error handling.
    set +e

    # Some non-interactive shells do not define "module" until the profile
    # script has been sourced.
    if ! command -v module >/dev/null 2>&1; then
        for init in /etc/profile.d/modules.sh \
                    /usr/share/Modules/init/bash \
                    /etc/profile.d/lmod.sh; do
            [ -f "$init" ] && . "$init" && break
        done
    fi

    if mpicc_works; then
        echo "mpienv: working mpicc already on PATH -> $(command -v mpicc)"
        set -e
        return 0
    fi

    # Shed any MPI module inherited from the retired login nodes. Leaving it
    # loaded keeps its lib paths in LD_LIBRARY_PATH, where they can shadow
    # the module we are about to load.
    if command -v mpicc >/dev/null 2>&1; then
        echo "mpienv: mpicc on PATH is broken, clearing stale MPI modules"
        for s in $(module list 2>&1 | tr ' ,' '\n\n' \
                   | grep -iE '^(mvapich|openmpi|mpich|intel-oneapi-mpi|impi)'); do
            echo "mpienv:   unloading $s"
            module unload "$s" >/dev/null 2>&1
        done
    fi

    MPI_CANDIDATES="mvapich2 openmpi mpich intel-oneapi-mpi impi"
    CC_CANDIDATES="gcc gcc/12.1.0 gcc/11.2.0 intel-oneapi-compilers"

    # Bare names first: the module system resolves each to its default build.
    for mpi in $MPI_CANDIDATES; do
        module load "$mpi" >/dev/null 2>&1
        if mpicc_works; then
            echo "mpienv: loaded $mpi"
            set -e
            return 0
        fi
        module unload "$mpi" >/dev/null 2>&1
    done

    # Several stacks need a compiler module present first.
    for cc in $CC_CANDIDATES; do
        module load "$cc" >/dev/null 2>&1 || continue
        for mpi in $MPI_CANDIDATES; do
            module load "$mpi" >/dev/null 2>&1
            if mpicc_works; then
                echo "mpienv: loaded $cc + $mpi"
                set -e
                return 0
            fi
            module unload "$mpi" >/dev/null 2>&1
        done
        module unload "$cc" >/dev/null 2>&1
    done

    # Last resort: every specific versioned MPI module the system advertises.
    for mpi in $(module avail 2>&1 \
                 | tr ' ' '\n' \
                 | grep -iE '^(mvapich|openmpi|mpich|intel-oneapi-mpi|impi)[-/]' \
                 | sed 's/(default)//' | sort -u | head -20); do
        module load "$mpi" >/dev/null 2>&1
        if mpicc_works; then
            echo "mpienv: loaded $mpi"
            set -e
            return 0
        fi
        module unload "$mpi" >/dev/null 2>&1
    done

    set -e
    echo "mpienv: FAILED to find a working mpicc." >&2
    echo "--- module list ---" >&2
    module list 2>&1 >&2
    echo "--- MPI modules available ---" >&2
    module avail 2>&1 \
        | grep -iE 'mvapich|openmpi|mpich|intel|gcc' >&2
    echo "Send the two blocks above." >&2
    return 1
}
