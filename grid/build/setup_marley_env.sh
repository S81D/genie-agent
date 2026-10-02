#!/usr/bin/env bash
#
# Standalone MARLEY v2 Spack environment — DUNE GPVM + grid worker.
#
# Companion to setup_env.sh (GENIE), but a SEPARATE payload: rc-v380's
# ./configure has no --enable-marley (that flag was fork-only), so MARLEY here
# is the upstream standalone generator — its own clone, its own tarball, its own
# label in the shared .jobsub catalog.
#
# Only two Spack packages are needed. GSL and HepMC3 come from MARLEY's own
# bundled copies (build_marley.sh passes IGNORE_GSL=1 IGNORE_HEPMC3=1), so they
# are deliberately NOT loaded — that keeps the payload's runtime deps down to
# the gcc runtime plus ROOT.
#
# DUAL USE — the same file is sourced in two places:
#   * on the GPVM to build     : MARLEY_ROOT = $MARLEYBASE/marley
#   * on a grid worker to run   : MARLEY_ROOT = <RCDS payload dir>/marley
# Both derive from this script's own location, so neither needs an export.
#
# Examples:
#   source /exp/dune/app/users/doran/grid/MARLEY/setup_marley_env.sh
#   SPACK_ROOT_SPEC=root@6.30.02 source .../setup_marley_env.sh   # repin a spec

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  echo "Usage: source $0" >&2
  exit 1
fi

# Re-sourcing in the same shell re-prepends PATH/LD_LIBRARY_PATH and re-runs
# every 'spack load', growing the environment until 'spack' itself fails to exec
# ("Argument list too long"). Guard against it — open a fresh shell to reload.
# Distinct from GENIE's GENIE_V38_ENV_SOURCED so one shell could hold both.
if [[ -n "${MARLEY_V2_ENV_SOURCED:-}" ]]; then
  echo "setup_marley_env.sh already sourced in this shell; skipping (open a new" >&2
  echo "shell to reload with different overrides)." >&2
  return 0
fi
export MARLEY_V2_ENV_SOURCED=1

SETUP_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

# ── Spack bootstrap ──────────────────────────────────────────────────────────
# Same pin as setup_env.sh (spack-fnal-v1.1.0) so 'spack load' picks the SAME
# concretizations on the build host and the worker. Override with SPACK_SETUP=...
# (v1.1.0's script nests under spack_env/).
if [[ -z "${SPACK_SETUP:-}" ]]; then
  for candidate in \
    /cvmfs/larsoft.opensciencegrid.org/spack-fnal-v1.1.0/spack_env/setup-env.sh \
    /cvmfs/larsoft.opensciencegrid.org/spack-fnal-v1.1.1/setup-env.sh \
    /cvmfs/larsoft.opensciencegrid.org/spack-fnal-v1.0.0/setup-env.sh
  do
    [[ -r "$candidate" ]] && { SPACK_SETUP="$candidate"; break; }
  done
fi
if [[ -z "${SPACK_SETUP:-}" || ! -r "$SPACK_SETUP" ]]; then
  echo "Could not find a usable Spack setup-env.sh; set SPACK_SETUP=..." >&2
  return 1
fi
echo "Sourcing $SPACK_SETUP"
source "$SPACK_SETUP"

# ── Dependency specs (@version-pinned against spack-fnal-v1.1.0) ─────────────
# gcc MUST be @12.5.0 — the compiler root@6.28.12 was built with. Bare 'gcc'
# resolves to the AL9 system gcc@11.5.0 (external, /usr), whose libstdc++ lacks
# GLIBCXX_3.4.30. MARLEY needs C++17, which both satisfy; the pin is about
# matching ROOT's ABI, not about the language standard.
: "${SPACK_GCC_SPEC:=gcc@12.5.0}"
: "${SPACK_ROOT_SPEC:=root@6.28.12}"

spack_load_first() {
  # --first: pick any one concretization. Plain 'spack load <name>' aborts when
  # the DB holds several builds of that package (common on CVMFS).
  local spec="$1"
  echo "spack load --first $spec"
  if ! spack load --first "$spec"; then
    echo "Failed to load '$spec' — override its spec, e.g. SPACK_ROOT_SPEC=root@<v>" >&2
    return 1
  fi
}

for spec in "$SPACK_GCC_SPEC" "$SPACK_ROOT_SPEC"; do
  spack_load_first "$spec" || return 1
done

spack_root() {
  # Install prefix of a currently-loaded package. Keep name@version (so a query
  # like 'gcc' can't also match the /usr gcc@11.5.0 if the env pre-loads it);
  # drop any /<hash> and ' +variant' tail. --loaded scopes to this shell.
  local q="${1%%/*}"; q="${q%% *}"
  spack find --loaded --format '{prefix}' "$q" | head -n 1
}

export GCC_PATH="$(spack_root "$SPACK_GCC_SPEC")"
# Catch a wrong/absent gcc now rather than at link time (or, worse, at runtime
# on a worker) — same GLIBCXX_3.4.30 failure mode setup_env.sh guards against.
if [[ -z "$GCC_PATH" || "$GCC_PATH" == /usr || "$GCC_PATH" == /usr/* ]]; then
  echo "ERROR: gcc resolved to '${GCC_PATH:-<empty>}', not the Spack gcc." >&2
  echo "  root@6.28.12 needs gcc@12.5.0 — set SPACK_GCC_SPEC=gcc@12.5.0 (or the" >&2
  echo "  version from: spack find --format '{name}@{version} %{compiler}' root@6.28.12)" >&2
  return 1
fi
export ROOTSYS="$(spack_root "$SPACK_ROOT_SPEC")"

# thisroot.sh sets ROOTSYS/PATH/LD_LIBRARY_PATH cleanly and puts root-config on
# PATH — which is exactly how MARLEY's build auto-detects the ROOT interface.
[[ -r "$ROOTSYS/bin/thisroot.sh" ]] && source "$ROOTSYS/bin/thisroot.sh"

# ── MARLEY ───────────────────────────────────────────────────────────────────
export MARLEY_ROOT="${MARLEY_ROOT:-$SETUP_DIR/marley}"
if [[ ! -r "$MARLEY_ROOT/setup_marley.sh" ]]; then
  echo "ERROR: no setup_marley.sh under '$MARLEY_ROOT'." >&2
  echo "  Expected the MARLEY clone at \$SETUP_DIR/marley; run build_marley.sh" >&2
  echo "  first, or export MARLEY_ROOT=<clone> before sourcing this script." >&2
  return 1
fi

# MARLEY ships its own relocatable setup script: it derives $MARLEY from
# BASH_SOURCE, so it is already correct at whatever path RCDS unpacked the
# payload to — no GENIEBASE-style override needed. It sets MARLEY, and appends
# build/bin to PATH and build/lib to LD_LIBRARY_PATH.
#
# setup_marley.sh appends with an UNGUARDED ${VAR} (ROOT_INCLUDE_PATH in
# particular, which thisroot.sh does not set), so it aborts under `set -u` —
# which build_marley.sh uses. Seed everything it touches before sourcing it.
export LD_LIBRARY_PATH="${LD_LIBRARY_PATH:-}"
export DYLD_LIBRARY_PATH="${DYLD_LIBRARY_PATH:-}"
export ROOT_INCLUDE_PATH="${ROOT_INCLUDE_PATH:-}"
export CMAKE_PREFIX_PATH="${CMAKE_PREFIX_PATH:-}"

source "$MARLEY_ROOT/setup_marley.sh"

# ...but it APPENDS where GENIE's setup_env.sh prepends. Harmless for MARLEY's
# own build/lib, yet it means the Spack gcc runtime must be pushed to the front
# by hand: otherwise the worker's /usr/lib64/libstdc++ is found first and
# `marley` dies on GLIBCXX_3.4.30, since it is built %gcc@12.5.0 against ROOT.
export PATH="$GCC_PATH/bin:$PATH"
export LD_LIBRARY_PATH="$GCC_PATH/lib64:${LD_LIBRARY_PATH:-}"

export CC="${CC:-$GCC_PATH/bin/gcc}"
export CXX="${CXX:-$GCC_PATH/bin/g++}"

echo "MARLEY=$MARLEY"
echo "MARLEY_ROOT=$MARLEY_ROOT"
echo "ROOTSYS=$ROOTSYS"
echo "GCC_PATH=$GCC_PATH"
