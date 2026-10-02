#!/usr/bin/env bash
#
# One-shot GENIE v3.8 (rc-v380) build on a DUNE GPVM.
#
#   bash /exp/dune/app/users/doran/grid/GENIE/grid/build/build_genie.sh
#
# Layout it expects / produces under $GENIEBASE (= /exp/dune/app/users/doran/grid/GENIE):
#   Generator/         git clone -b rc-v380 https://github.com/GENIE-MC/Generator.git
#   data/              XSECSPLINEDIR (created here)
#   setup_env.sh       copied from grid/build/ (also goes in the grid tarball)
#   do_configure.sh    copied from grid/build/
#   GENIE_COMMIT.txt   the exact rc-v380 SHA
#   build.log
#   grid/              this script's tree (build/, workers/, README.md)
#
# Env knobs:
#   GENIEBASE     install root (default /exp/dune/app/users/doran/grid/GENIE)
#   GENIE_BRANCH  default rc-v380
#   JOBS          make parallelism, default 4 (use 1 if the build races)
set -euo pipefail

: "${GENIEBASE:=/exp/dune/app/users/doran/grid/GENIE}"
GENIE_BRANCH="${GENIE_BRANCH:-rc-v380}"
JOBS="${JOBS:-4}"
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

mkdir -p "$GENIEBASE"
# Keep the env + configure scripts next to Generator/ so setup_env.sh lands in
# the grid tarball and the worker can source it.
cp "$HERE/setup_env.sh" "$HERE/do_configure.sh" "$GENIEBASE/"

cd "$GENIEBASE"
if [[ ! -d Generator ]]; then
  # Full clone (not --depth 1) so a specific commit can be checked out later to
  # freeze a production campaign.
  git clone -b "$GENIE_BRANCH" https://github.com/GENIE-MC/Generator.git
fi

cd "$GENIEBASE/Generator"
export GENIE="$PWD"
git rev-parse HEAD | tee "$GENIEBASE/GENIE_COMMIT.txt"
git log -1 --format='%h %ci %s'

# Wipe any prior build state (e.g. a failed pythia6 attempt) before reconfiguring.
if make clean >/dev/null 2>&1; then echo ">>> cleaned prior build"; fi

source "$GENIEBASE/setup_env.sh"

echo ">>> loaded Spack packages (all prefixes should be under /cvmfs/.../spack-fnal-v1.1.0)"
spack find --loaded --format '  {name}@{version}  {prefix}' | tee "$GENIEBASE/spack_loaded.txt"

bash "$GENIEBASE/do_configure.sh"

echo ">>> make -j$JOBS  (log: $GENIEBASE/build.log)"
make -j"$JOBS" 2>&1 | tee "$GENIEBASE/build.log"

mkdir -p "$GENIEBASE/data"   # XSECSPLINEDIR (splines are written here / by -o)

echo ">>> sanity check"
missing=0
for b in gmkspl gevgen gntpc gspladd gspl2root; do
  if [[ -x "$GENIE/bin/$b" ]]; then echo "  ok   $b"; else echo "  MISS $b"; missing=1; fi
done
[[ $missing -eq 0 ]] || { echo "build incomplete" >&2; exit 1; }

echo
echo "Build OK.  commit $(cat "$GENIEBASE/GENIE_COMMIT.txt")"
echo "Local smoke:  gmkspl -p 14 -t 1000060120 --tune AR23_20i_00_000 \\"
echo "                     --event-generator-list CCQE -e 5 -n 20 -o /tmp/t.xml"
