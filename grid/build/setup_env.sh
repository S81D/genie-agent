#!/usr/bin/env bash
#
# GENIE v3.8 (rc-v380) minimal Spack environment — DUNE GPVM + grid worker.
#
# Adapted from the GENIE+MARLEY project's setup_env.sh, stripped to a minimal
# build: PYTHIA8 + LHAPDF6, no INCL++ / MARLEY / HepMC3. rc-v380 defaults the DIS
# hadronizer to Pythia8 (config/AGKY2019.xml) and its pythia6-only build path is
# broken (missing #ifdef guard in Pythia8Decayer2023.cxx), so PYTHIA8 it is. The
# v3.8 DUNE tunes (AR23_20*, AR25_20*, G18_02a, G18_10a-d) use the built-in hA/hN
# cascades, so nothing here needs the INCL library.
#
# DUAL USE — the same file is sourced in two places:
#   * on the GPVM to build      : GENIEBASE = the install root you cloned into
#   * on a grid worker to run   : GENIEBASE = the unpacked RCDS/CVMFS payload dir
# GENIEBASE therefore drives every derived path (GENIE, XSECSPLINEDIR,
# LD_LIBRARY_PATH); export it before sourcing, or it defaults to this file's dir.
#
# Examples:
#   export GENIEBASE=/exp/dune/app/users/doran/grid/GENIE
#   source $GENIEBASE/setup_env.sh
#   SPACK_ROOT_SPEC=root@6.28.12 source $GENIEBASE/setup_env.sh   # pin a spec
#
# The Spack specs are deliberately overrideable (SPACK_*_SPEC): pin/repin them
# if a build hiccup or the post-build `spack find --loaded` check calls for it.

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  echo "Usage: source $0" >&2
  exit 1
fi

# Re-sourcing in the same shell re-prepends PATH/LD_LIBRARY_PATH and re-runs
# every 'spack load', growing the environment until 'spack' itself fails to exec
# ("Argument list too long"). Guard against it — open a fresh shell to reload.
if [[ -n "${GENIE_V38_ENV_SOURCED:-}" ]]; then
  echo "setup_env.sh already sourced in this shell; skipping (open a new shell" >&2
  echo "to reload with different overrides)." >&2
  return 0
fi
export GENIE_V38_ENV_SOURCED=1

SETUP_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

# ── Spack bootstrap ──────────────────────────────────────────────────────────
# Pinned to spack-fnal-v1.1.0 (what /cvmfs/.../setup-env.sh currently resolves
# to) so 'spack load' picks the SAME concretizations on the build host and the
# worker, and stays fixed even when "current" advances. All listed instances
# carry pythia8; the fallbacks only matter if v1.1.0 is ever pruned from CVMFS.
# Override with SPACK_SETUP=... (v1.1.0's script nests under spack_env/).
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
# GLIBCXX_3.4.30 and fails to link ROOT. pythia8/libxml2 each have several builds
# in v1.1.0 — pinned to remove 'spack load --first' ambiguity.
# If GENIE won't compile against pythia8@8.313, try SPACK_PYTHIA8_SPEC=pythia8@8.317.
: "${SPACK_GCC_SPEC:=gcc@12.5.0}"
: "${SPACK_ROOT_SPEC:=root@6.28.12}"
: "${SPACK_PYTHIA8_SPEC:=pythia8@8.313}"
: "${SPACK_LOG4CPP_SPEC:=log4cpp@1.1.3}"
: "${SPACK_LHAPDF_SPEC:=lhapdf@6.5.5}"
: "${SPACK_LIBXML2_SPEC:=libxml2@2.9.13}"
: "${SPACK_GSL_SPEC:=gsl@2.8}"

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

for spec in \
  "$SPACK_GCC_SPEC" "$SPACK_ROOT_SPEC" "$SPACK_PYTHIA8_SPEC" \
  "$SPACK_LOG4CPP_SPEC" "$SPACK_LHAPDF_SPEC" "$SPACK_LIBXML2_SPEC" \
  "$SPACK_GSL_SPEC"
do
  spack_load_first "$spec" || return 1
done

spack_root() {
  # Install prefix of a currently-loaded package. Keep name@version (so a query
  # like 'gcc' can't also match the /usr gcc@11.5.0 if the env pre-loads it);
  # drop any /<hash> and ' +variant' tail. --loaded scopes to this shell.
  local q="${1%%/*}"; q="${q%% *}"
  spack find --loaded --format '{prefix}' "$q" | head -n 1
}

# ── GENIE + dependency paths (names 'configure' expects) ─────────────────────
export GENIEBASE="${GENIEBASE:-$SETUP_DIR}"
export GENIE="${GENIE:-$GENIEBASE/Generator}"
export XSECSPLINEDIR="${XSECSPLINEDIR:-$GENIEBASE/data}"

export GCC_PATH="$(spack_root "$SPACK_GCC_SPEC")"
# GENIE's Make.include hard-codes `CXX = g++` (ignores $CXX), so the compiler is
# whatever `spack load` put first on PATH. Catch a wrong/absent gcc now, before
# a 40-min build links against the system libstdc++ and dies on GLIBCXX_3.4.30.
if [[ -z "$GCC_PATH" || "$GCC_PATH" == /usr || "$GCC_PATH" == /usr/* ]]; then
  echo "ERROR: gcc resolved to '${GCC_PATH:-<empty>}', not the Spack gcc." >&2
  echo "  root@6.28.12 needs gcc@12.5.0 — set SPACK_GCC_SPEC=gcc@12.5.0 (or the" >&2
  echo "  version from: spack find --format '{name}@{version} %{compiler}' root@6.28.12)" >&2
  return 1
fi
export ROOTSYS="$(spack_root "$SPACK_ROOT_SPEC")"
export PYTHIA8="$(spack_root "$SPACK_PYTHIA8_SPEC")"
export LOG4CPP="$(spack_root "$SPACK_LOG4CPP_SPEC")"
export LHAPDF6="$(spack_root "$SPACK_LHAPDF_SPEC")"
export LIBXML2="$(spack_root "$SPACK_LIBXML2_SPEC")"
export GSL_PATH="$(spack_root "$SPACK_GSL_SPEC")"

# PYTHIA8: 'configure' wants the dir holding libpythia8.so and the one holding
# Pythia8/Pythia.h; Pythia8 itself reads its xmldoc via $PYTHIA8DATA at runtime.
export PYTHIA8_LIB="$PYTHIA8/lib"
[[ -e "$PYTHIA8/lib64/libpythia8.so" ]] && export PYTHIA8_LIB="$PYTHIA8/lib64"
export PYTHIA8_INC="$PYTHIA8/include"
for d in "$PYTHIA8/share/Pythia8/xmldoc" "$PYTHIA8/share/pythia8/xmldoc"; do
  [[ -d "$d" ]] && export PYTHIA8DATA="$d"
done

export LHAPDF_INC="$LHAPDF6/include"
export LHAPDF_LIB="$LHAPDF6/lib"
export LOG4CPP_INC="$LOG4CPP/include"
export LOG4CPP_LIB="$LOG4CPP/lib"
export LIBXML2_INC="$LIBXML2/include/libxml2"
export LIBXML2_LIB="$LIBXML2/lib"

# thisroot.sh sets ROOTSYS/PATH/LD_LIBRARY_PATH/PYTHONPATH for ROOT cleanly and
# puts root-config (which 'configure' needs) on PATH.
[[ -r "$ROOTSYS/bin/thisroot.sh" ]] && source "$ROOTSYS/bin/thisroot.sh"

export PATH="$GCC_PATH/bin:$ROOTSYS/bin:$LHAPDF6/bin:$GSL_PATH/bin:$GENIE/bin:$PATH"
export CC="${CC:-$GCC_PATH/bin/gcc}"
export CXX="${CXX:-$GCC_PATH/bin/g++}"
export LD_LIBRARY_PATH="$GENIE/lib:$LOG4CPP_LIB:$PYTHIA8_LIB:$GSL_PATH/lib:$LHAPDF_LIB:$LIBXML2_LIB:$GCC_PATH/lib64:${LD_LIBRARY_PATH:-}"

echo "GENIEBASE=$GENIEBASE"
echo "GENIE=$GENIE"
echo "XSECSPLINEDIR=$XSECSPLINEDIR"
echo "ROOTSYS=$ROOTSYS"
echo "PYTHIA8=$PYTHIA8   PYTHIA8DATA=${PYTHIA8DATA:-<unset>}"
echo "GCC_PATH=$GCC_PATH"
