#!/usr/bin/env bash
#
# One-shot standalone MARLEY v2 build on a DUNE GPVM.
#
#   bash /exp/dune/app/users/doran/grid/GENIE/grid/build/build_marley.sh
#
# Layout it expects / produces under $MARLEYBASE (= /exp/dune/app/users/doran/grid/MARLEY),
# a SIBLING of $GENIEBASE — MARLEY is an independent payload, not a GENIE option:
#   marley/               git clone -b main https://github.com/MARLEY-MC/marley.git
#   setup_marley_env.sh   copied from grid/build/ (also goes in the grid tarball)
#   configs/              tokenized job configs (also go in the tarball)
#   MARLEY_COMMIT.txt     the exact main SHA this payload was built from
#   spack_loaded.txt
#   build.log
#
# Env knobs:
#   MARLEYBASE     install root (default /exp/dune/app/users/doran/grid/MARLEY)
#   MARLEY_BRANCH  default main
#   JOBS           make parallelism, default 4
#   CLEAN          1 to `make clean` first (MARLEY's clean DELETES build/, so a
#                  clean build is a full rebuild — off by default)
set -euo pipefail

: "${MARLEYBASE:=/exp/dune/app/users/doran/grid/MARLEY}"
MARLEY_BRANCH="${MARLEY_BRANCH:-main}"
JOBS="${JOBS:-4}"
CLEAN="${CLEAN:-0}"
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

mkdir -p "$MARLEYBASE"
# Keep the env script and the job configs next to marley/ so both land at the
# TOP LEVEL of the grid tarball, where the worker looks for them.
cp -f "$HERE/setup_marley_env.sh" "$MARLEYBASE/"
mkdir -p "$MARLEYBASE/configs"
cp -f "$HERE/../configs/"*.js "$MARLEYBASE/configs/"

cd "$MARLEYBASE"
if [[ ! -d marley ]]; then
  # Full clone (not --depth 1) so a specific commit can be checked out later to
  # freeze a production campaign.
  git clone -b "$MARLEY_BRANCH" https://github.com/MARLEY-MC/marley.git
fi

cd "$MARLEYBASE/marley"
git rev-parse HEAD | tee "$MARLEYBASE/MARLEY_COMMIT.txt"
git log -1 --format='%h %ci %s'

# Sourced AFTER the clone: setup_marley_env.sh hard-errors without marley/.
source "$MARLEYBASE/setup_marley_env.sh"

echo ">>> loaded Spack packages (all prefixes should be under /cvmfs/.../spack-fnal-v1.1.0)"
spack find --loaded --format '  {name}@{version}  {prefix}' | tee "$MARLEYBASE/spack_loaded.txt"

if [[ "$CLEAN" == "1" ]]; then
  echo ">>> make clean (removes build/ entirely)"
  make clean
fi

# IGNORE_ROOT is deliberately NOT set: MARLEY's build auto-enables its ROOT
# interface when root-config is on PATH (thisroot.sh put it there), and we need
# it for the "root" event output format and `marley summarize`.
# IGNORE_GSL/IGNORE_HEPMC3 force MARLEY's bundled copies instead of Spack ones,
# so the shipped payload carries no extra runtime deps.
#
# The top-level Makefile uses CMake when it finds it and falls back to
# make/build.mk otherwise; add IGNORE_CMAKE=1 here if this GPVM's cmake is
# missing or too old. CMake caches these flags under build/CMakeFiles, so
# changing them later needs `make reconfigure`.
echo ">>> make -j$JOBS  (log: $MARLEYBASE/build.log)"
make -j"$JOBS" IGNORE_GSL=1 IGNORE_HEPMC3=1 2>&1 | tee "$MARLEYBASE/build.log"

echo ">>> sanity check"
if [[ ! -x "$MARLEYBASE/marley/build/bin/marley" ]]; then
  echo "  MISS marley  — build incomplete" >&2
  exit 1
fi
echo "  ok   marley"
marley version

echo
echo "Build OK.  commit $(cat "$MARLEYBASE/MARLEY_COMMIT.txt")"
echo "Local smoke:  sed -e 's/@SEED@/12345/' -e 's/@NEVENTS@/20/' -e 's/@OUTSTEM@/t/' \\"
echo "                  $MARLEYBASE/configs/ve40Ar_fd.js > /tmp/t.js"
echo "              cd /tmp && marley generate /tmp/t.js"
