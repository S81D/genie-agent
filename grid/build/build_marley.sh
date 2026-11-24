#!/usr/bin/env bash
#
# One-shot standalone MARLEY v2 build on a DUNE GPVM.
#
#   bash /exp/dune/app/users/doran/grid/GENIE/grid/build/build_marley.sh
#
# Layout it expects / produces under $MARLEYBASE (= /exp/dune/app/users/doran/grid/MARLEY),
# a SIBLING of $GENIEBASE — MARLEY is an independent payload, not a GENIE option:
#   marley/               clone of https://github.com/MARLEY-MC/marley.git, detached
#                         at $MARLEY_REF (default: the v2.1.0 release tag)
#   setup_marley_env.sh   copied from grid/build/ (also goes in the grid tarball)
#   configs/              tokenized job configs (also go in the tarball)
#   MARLEY_REF.txt        the ref that was asked for (tag / branch / SHA, or "keep")
#   MARLEY_COMMIT.txt     the exact SHA this payload was built from (both written
#                         only after a successful build; also marley/build/.built_commit)
#   spack_loaded.txt
#   build.log
#
# Env knobs:
#   MARLEYBASE     install root (default /exp/dune/app/users/doran/grid/MARLEY)
#   MARLEY_REF     tag, branch or SHA to build; default v2.1.0 (= "MARLEY v2").
#                  "keep" builds an existing marley/ exactly as it is (no clone,
#                  fetch or checkout): the uploaded private sign-fix tree,
#                  README_marley.md §5b. Replaces MARLEY_BRANCH (default was main).
#   JOBS           make parallelism, default 4
#   CLEAN          1 to `make clean` first (MARLEY's clean DELETES build/, so a
#                  clean build is a full rebuild — off by default, but forced on
#                  when build/ was not built from the checked-out commit)
set -euo pipefail

: "${MARLEYBASE:=/exp/dune/app/users/doran/grid/MARLEY}"
MARLEY_URL=https://github.com/MARLEY-MC/marley.git
MARLEY_REF="${MARLEY_REF:-v2.1.0}"
JOBS="${JOBS:-4}"
CLEAN="${CLEAN:-0}"
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

if [[ -n "${MARLEY_BRANCH:-}" ]]; then
  echo "ERROR: MARLEY_BRANCH is no longer read; use MARLEY_REF=<tag|branch|sha>" >&2
  echo "  (default v2.1.0), or MARLEY_REF=keep for an uploaded tree." >&2
  exit 1
fi

# The commit each pinned release tag must resolve to. A tag that moves upstream
# is caught here instead of silently changing the physics of a "v2.1.0" payload.
declare -A PINNED_COMMIT=(
  [v2.1.0]=8813f234f496cfcb6fa37311474c4d078b83b0a8
)

mkdir -p "$MARLEYBASE"
# Keep the env script and the job configs next to marley/ so both land at the
# TOP LEVEL of the grid tarball, where the worker looks for them.
cp -f "$HERE/setup_marley_env.sh" "$MARLEYBASE/"
mkdir -p "$MARLEYBASE/configs"
cp -f "$HERE/../configs/"*.js "$MARLEYBASE/configs/"

cd "$MARLEYBASE"

if [[ "$MARLEY_REF" == keep ]]; then
  if [[ ! -d marley ]]; then
    echo "ERROR: MARLEY_REF=keep but there is no $MARLEYBASE/marley" >&2
    exit 1
  fi
  echo ">>> MARLEY_REF=keep: building $MARLEYBASE/marley as it is (no clone/fetch/checkout)"
else
  if [[ ! -d marley ]]; then
    # Full clone (not --depth 1) so any tag or commit can be checked out later.
    git clone "$MARLEY_URL" marley
  fi
  # Only ever move a clone of the public repo whose tracked files are untouched.
  # Anything else (the rsync'd private sign-fix tree, a fork, local edits) is
  # refused here; build it as it is with MARLEY_REF=keep.
  origin="$(git -C marley remote get-url origin 2>/dev/null || echo '<none>')"
  if [[ "${origin%.git}" != "${MARLEY_URL%.git}" ]]; then
    echo "ERROR: $MARLEYBASE/marley is not a clone of $MARLEY_URL (origin: $origin)." >&2
    echo "  To build that tree as it is, rerun with MARLEY_REF=keep." >&2
    exit 1
  fi
  if [[ -n "$(git -C marley status --porcelain --untracked-files=no)" ]]; then
    echo "ERROR: tracked files in $MARLEYBASE/marley have local changes:" >&2
    git -C marley status --short --untracked-files=no >&2
    exit 1
  fi
  if ! git -C marley fetch --tags origin; then
    echo "ERROR: git fetch --tags failed. If git says 'would clobber existing tag'," >&2
    echo "  a local tag differs from upstream's: check it before building." >&2
    exit 1
  fi
  # A branch name means the remote branch's current tip, not a stale local copy.
  target="$MARLEY_REF"
  if git -C marley rev-parse -q --verify "refs/remotes/origin/$MARLEY_REF" >/dev/null; then
    target="origin/$MARLEY_REF"
  fi
  git -C marley -c advice.detachedHead=false checkout --detach "$target"
fi

cd "$MARLEYBASE/marley"
COMMIT="$(git rev-parse HEAD 2>/dev/null || echo unknown)"
if [[ -n "${PINNED_COMMIT[$MARLEY_REF]:-}" && "$COMMIT" != "${PINNED_COMMIT[$MARLEY_REF]}" ]]; then
  echo "ERROR: $MARLEY_REF resolved to $COMMIT, expected ${PINNED_COMMIT[$MARLEY_REF]}." >&2
  echo "  The tag moved upstream: stop and check before building anything." >&2
  exit 1
fi
echo ">>> ref $MARLEY_REF -> commit $COMMIT"
git log -1 --format='%h %ci %s' 2>/dev/null || true

# What build/ was built from: a marker written into build/ only after a
# successful build (build/ is git-ignored). Any other state (the 2026-09 main
# build when moving to v2.1.0, or a build/ left by a failed run) needs a full
# rebuild: the top-level make does not re-run cmake, so the version and git hash
# compiled into marley (and written into every HepMC3 header) would stay stale,
# and the build-tree layout changed at 2.1.
BUILT_COMMIT="$(cat build/.built_commit 2>/dev/null || echo '<no marker>')"
if [[ -d build && "$BUILT_COMMIT" != "$COMMIT" && "$CLEAN" != 1 ]]; then
  echo ">>> build/ is from ${BUILT_COMMIT:0:11}, not ${COMMIT:0:9}: forcing CLEAN=1"
  CLEAN=1
fi

# Sourced AFTER the clone: setup_marley_env.sh hard-errors without marley/.
# MARLEY >= 2.1 generates its setup script only during the build, so tell the
# env script that an unbuilt tree is expected here (gcc + ROOT are all make needs).
MARLEY_ENV_ALLOW_UNBUILT=1 source "$MARLEYBASE/setup_marley_env.sh"

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
# Full path: for MARLEY >= 2.1 the env script could not put build/bin on PATH
# before the build existed.
"$MARLEYBASE/marley/build/bin/marley" version
if [[ -r "$MARLEYBASE/marley/set_marley_path.sh" ]]; then
  # >= 2.1 only: where this binary looks for data (MARLEY_SEARCH_PATH first)
  "$MARLEYBASE/marley/build/bin/marley" info
fi

# Record what was built only now, so a failed run never marks a stale build/
# (or the payload) as current.
echo "$COMMIT" > "$MARLEYBASE/marley/build/.built_commit"
echo "$MARLEY_REF" > "$MARLEYBASE/MARLEY_REF.txt"
echo "$COMMIT" > "$MARLEYBASE/MARLEY_COMMIT.txt"

echo
echo "Build OK.  ref $MARLEY_REF  commit $(cat "$MARLEYBASE/MARLEY_COMMIT.txt")"
echo "Local smoke (fresh shell):  source $MARLEYBASE/setup_marley_env.sh"
echo "  sed -e 's/@SEED@/12345/' -e 's/@NEVENTS@/20/' -e 's/@OUTSTEM@/t/' \\"
echo "      $MARLEYBASE/configs/ve40Ar_fd.js > /tmp/t.js"
echo "  cd /tmp && marley generate /tmp/t.js"
