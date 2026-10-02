#!/bin/bash
#
# marley_worker.sh — production MARLEY event generation on the grid:
#   marley generate   (N events from a tokenized config)
#     -> marley summarize   (flat "mst" TTree beside the event file)
#
# Production sibling of marley_smoke.sh. Two differences from that script:
#
#   1. The payload arrives as a TARBALL via `jobsub -f`, not as an RCDS/CVMFS
#      directory. This build comes from MARLEY-MC/marley-private, and RCDS
#      publishes to a world-readable /cvmfs/fifeuser* repo — so the tarball is
#      staged to the user's own /pnfs area instead and unpacked here.
#   2. `-t <tag>` names the output stem, so the four campaign cells
#      (127I/208Pb x v2/AA) never collide in a shared output tree.
#
# Submit (note: NO -R @TAR_DIR@ — there is no CVMFS payload dir to point at):
#   python3 $SKILL/scripts/jobsub.py submit --worker grid/workers/marley_worker.sh \
#       -N 10 --runtype marley_dar -f /pnfs/.../marley_v2_0_1_signfix.tar \
#       --memory 4000MB --expected-lifetime 8h --disk 10GB --output-suffix .root \
#       --pnfs-out /pnfs/dune/scratch/users/$USER/marley_dar/208Pb/v2 \
#       -- -O @PNFS_OUT@ -c configs/pb-dar-v2.js -n 50000 -t Pb-dar-v2
#
#   A config NOT in the tarball: add a second `-f /pnfs/.../ar-dar-v2.js` and
#   pass the bare name, `-c ar-dar-v2.js` (see README_marley.md §6).
#
# Conventions from worker_skeleton.sh (jobsub-lite monitor relies on them):
#   seed = CLUSTER*100000 + PROCESS ; outputs -> <PNFS>/<%04d>/ ; final line = DONE
set -e
date; hostname; uname -r

PAYLOAD_OVERRIDE=""; PNFS_OUTPUT_DIR=""
CONFIG=""; NEVENTS="50000"; TAG=""
while getopts "R:O:c:n:t:" opt; do
  case $opt in
    R) PAYLOAD_OVERRIDE=$OPTARG ;;  # pre-unpacked payload dir (debugging)
    O) PNFS_OUTPUT_DIR=$OPTARG ;;
    c) CONFIG=$OPTARG ;;            # payload-relative, absolute, or a bare -f staged name
    n) NEVENTS=$OPTARG ;;           # events to generate
    t) TAG=$OPTARG ;;               # output stem tag, e.g. Pb-dar-v2
    *) echo "bad flag: $opt" >&2; exit 2 ;;
  esac
done
[ -n "${PNFS_OUTPUT_DIR}" ] || { echo "-O <pnfs_output_dir> is required" >&2; exit 2; }
[ -n "${CONFIG}" ] || { echo "-c <config> is required" >&2; exit 2; }
[ -n "${TAG}" ]    || { echo "-t <tag> is required (output stem)" >&2; exit 2; }

PROCESS_STR=$(printf "%04d" "${PROCESS:-0}")
# MARLEY's "seed" key takes a nonnegative 63-bit integer, so the ~1e12-1e13 this
# produces is safe — no int32 truncation to worry about here. Unique across
# submissions, so all cells of the campaign draw disjoint RNG streams.
SEED=$((CLUSTER * 100000 + PROCESS))
echo "CLUSTER=${CLUSTER} PROCESS=${PROCESS} SEED=${SEED} TAG=${TAG}"

# ── ifdh, then payload env ───────────────────────────────────────────────────
source /cvmfs/larsoft.opensciencegrid.org/setup-env.sh
spack load --first ifdhc

# ── Locate + unpack the payload ──────────────────────────────────────────────
if [ -n "${PAYLOAD_OVERRIDE}" ]; then
  PAYLOAD="${PAYLOAD_OVERRIDE%/}"
else
  # `jobsub -f` dropped the tarball in $CONDOR_DIR_INPUT; unpack into job
  # scratch. Its top-level members are marley/, setup_marley_env.sh, configs/ —
  # the same layout RCDS produced, so setup_marley_env.sh needs no changes.
  TAR=$(ls "${CONDOR_DIR_INPUT:-/nonexistent}"/*.tar 2>/dev/null | head -1)
  [ -n "${TAR}" ] \
    || { echo "no payload tarball in CONDOR_DIR_INPUT=${CONDOR_DIR_INPUT:-<unset>}" >&2; exit 3; }
  echo "unpacking $(ls -lh "${TAR}" | awk '{print $5, $9}')"
  mkdir -p "${PWD}/payload"
  tar -xf "${TAR}" -C "${PWD}/payload" || { echo "tar -xf failed" >&2; exit 3; }
  PAYLOAD="${PWD}/payload"
fi
echo "PAYLOAD=${PAYLOAD}"
[ -f "${PAYLOAD}/setup_marley_env.sh" ] \
  || { echo "no setup_marley_env.sh under ${PAYLOAD}" >&2; exit 3; }

source "${PAYLOAD}/setup_marley_env.sh" \
  || { echo "payload setup_marley_env.sh failed" >&2; exit 5; }
for b in marley ifdh; do
  command -v "$b" >/dev/null || { echo "$b not on PATH after env setup" >&2; exit 5; }
done

# ── Build this process's config ──────────────────────────────────────────────
# A config staged with `jobsub -f` lands in $CONDOR_DIR_INPUT, whose path is only
# known here on the worker — so it is passed as a bare file name (no "/"). Case
# patterns are globs tried in order; the first match wins.
case "${CONFIG}" in
  /*)  CONFIG_PATH="${CONFIG}" ;;                              # absolute path
  */*) CONFIG_PATH="${PAYLOAD}/${CONFIG}" ;;                   # e.g. configs/pb-dar-v2.js
  *)   CONFIG_PATH="${CONDOR_DIR_INPUT:-/nonexistent}/${CONFIG}" ;;  # e.g. ar-dar-v2.js via -f
esac
[ -f "${CONFIG_PATH}" ] || { echo "config not found: ${CONFIG_PATH}" >&2; exit 2; }

STEM="${TAG}_p${PROCESS_STR}_c${CLUSTER}"
JOB_CFG="${PWD}/job_config.js"
sed -e "s|@SEED@|${SEED}|g" \
    -e "s|@NEVENTS@|${NEVENTS}|g" \
    -e "s|@OUTSTEM@|${STEM}|g" \
    "${CONFIG_PATH}" > "${JOB_CFG}"

# A token this worker doesn't know would otherwise reach MARLEY as a syntax
# error hundreds of lines into the JSON — fail here with a clear message.
if grep -q '@[A-Z_]\{1,\}@' "${JOB_CFG}"; then
  echo "ERROR: unsubstituted token(s) left in ${JOB_CFG}:" >&2
  grep -n '@[A-Z_]\{1,\}@' "${JOB_CFG}" >&2
  exit 2
fi
echo "--- job_config.js (from ${CONFIG_PATH}) ---"
cat "${JOB_CFG}"
echo "--- end job_config.js ---"

EVENTS="${STEM}.hepmc3.root"
SUMMARY="${STEM}.summary.root"

echo "=== [1/2] marley generate  (${NEVENTS} events, seed ${SEED}) ==="
marley generate "${JOB_CFG}"

# -f is REQUIRED on a batch node: without it an existing output makes summarize
# prompt interactively (src/app/cmd_summarize.cc), which would hang the job.
echo "=== [2/2] marley summarize  (-> flat mst TTree) ==="
marley summarize -f -o "${SUMMARY}" "${EVENTS}"

ls -alh

# ── Copy outputs to PNFS ─────────────────────────────────────────────────────
# job_config.js rides along so the exact configuration that produced these
# events — seed included — sits next to them on PNFS.
DEST="${PNFS_OUTPUT_DIR%/}/${PROCESS_STR}"
echo "ifdh mkdir_p ${DEST}"
ifdh mkdir_p "${DEST}"
N_COPIED=0
for f in "${EVENTS}" "${SUMMARY}" "${JOB_CFG}"; do
  [ -e "$f" ] || { echo "MISSING expected output: $f" >&2; continue; }
  ifdh cp -D "$f" "${DEST}/"
  N_COPIED=$((N_COPIED + 1))
done
if [ "${N_COPIED}" -lt 2 ]; then
  echo "ERROR: expected 2 event outputs (events/summary), copied ${N_COPIED}" >&2
  exit 4
fi
echo "copied ${N_COPIED} file(s) to ${DEST}"

date
echo "DONE"
