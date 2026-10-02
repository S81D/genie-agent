#!/bin/bash
#
# smoke_chain.sh — end-to-end pipeline check in ONE grid job:
#   gmkspl  (build a small spline)
#     -> gevgen  (generate a few events off it)
#       -> gntpc  (GHEP -> GST)
#
# Proves the published GENIE tarball runs all three binaries with a real tune
# (FSI, nuclear model, de-excitation, form factors all get exercised on QEL
# events too). NOT a physics sample — small stats, single energy.
#
# Default genlist is CCQE only. Do NOT default to a MEC-inclusive genlist for
# targets without a native SuSAv2 hadron tensor (e.g. 40Ar, 1000180400):
# SuSAv2MECPXSec falls back to a C12-tensor-scaling correction
# (src/Physics/Multinucleon/XSection/SuSAv2MECPXSec.cxx) that is dramatically
# slower per energy knot than a native lookup — a few knots took hours in
# testing. Measure MEC cost separately (one knot, backgrounded, timed) before
# ever putting a MEC genlist in a grid job's -n /-e budget.
#
# Submit:
#   python3 $SKILL/scripts/jobsub.py submit --worker grid/workers/smoke_chain.sh \
#       -N 1 --runtype smoke --tar-label genie_v3_8_0_rcv380 \
#       --memory 2500MB --expected-lifetime 4h --disk 15GB --output-suffix .gst.root \
#       -- -R @TAR_DIR@ -O @PNFS_OUT@ \
#          -p 14,-12 -t 1000180400 -T AR23_20n_00_000 \
#          -L CCQE -E 5 -K 20 -g 14 -G 2.5 -m 500
#
# Conventions from worker_skeleton.sh (jobsub-lite monitor relies on them):
#   seed = CLUSTER*100000 + PROCESS ; outputs -> <PNFS>/<%04d>/ ; final line = DONE
set -e
date; hostname; uname -r

PAYLOAD_OVERRIDE=""; PNFS_OUTPUT_DIR=""
SPL_PROBES=""; TARGET=""; TUNE=""; GENLIST="CCQE"
SPL_MAXE="5"; SPL_KNOTS="20"
GEV_PROBE=""; GEV_ENERGY="2.5"; GEV_NEVT="500"
while getopts "R:O:p:t:T:L:E:K:g:G:m:" opt; do
  case $opt in
    R) PAYLOAD_OVERRIDE=$OPTARG ;;
    O) PNFS_OUTPUT_DIR=$OPTARG ;;
    p) SPL_PROBES=$OPTARG ;;    # gmkspl probe list (comma ok), e.g. 14,-12
    t) TARGET=$OPTARG ;;        # target PDG, e.g. 1000180400 (40Ar)
    T) TUNE=$OPTARG ;;          # e.g. AR23_20n_00_000
    L) GENLIST=$OPTARG ;;       # event-generator-list name (Default for full coverage)
    E) SPL_MAXE=$OPTARG ;;      # gmkspl max energy [GeV]
    K) SPL_KNOTS=$OPTARG ;;     # gmkspl knots
    g) GEV_PROBE=$OPTARG ;;     # gevgen single probe (default: first of -p)
    G) GEV_ENERGY=$OPTARG ;;    # gevgen mono-energetic beam [GeV]
    m) GEV_NEVT=$OPTARG ;;      # gevgen n events
    *) echo "bad flag: $opt" >&2; exit 2 ;;
  esac
done
[ -n "${PNFS_OUTPUT_DIR}" ] || { echo "-O <pnfs_output_dir> is required" >&2; exit 2; }
{ [ -n "${SPL_PROBES}" ] && [ -n "${TARGET}" ] && [ -n "${TUNE}" ]; } \
  || { echo "-p, -t and -T are required" >&2; exit 2; }
[ -n "${GEV_PROBE}" ] || GEV_PROBE="${SPL_PROBES%%,*}"   # first probe of the list

PROCESS_STR=$(printf "%04d" "${PROCESS:-0}")
SEED=$((CLUSTER * 100000 + PROCESS))
echo "CLUSTER=${CLUSTER} PROCESS=${PROCESS} SEED=${SEED}"

# ── ifdh, then payload env ───────────────────────────────────────────────────
# Timestamped markers throughout so a walltime hold is still diagnosable (the
# worker .out is often unfetchable for held jobs — read the queue's LastJobStatus
# progression and these lines if you can get any stdout back).
echo "[$(date +%T)] loading ifdh"
source /cvmfs/larsoft.opensciencegrid.org/setup-env.sh
spack load --first ifdhc

if [ -n "${PAYLOAD_OVERRIDE}" ]; then
  RCDS_DIR="${PAYLOAD_OVERRIDE%/}"
elif [ -n "${INPUT_TAR_FILE}" ]; then
  if [ -d "${INPUT_TAR_FILE}" ]; then RCDS_DIR="${INPUT_TAR_FILE%/}"
  else RCDS_DIR="$(dirname "${INPUT_TAR_FILE}")"; fi
else
  echo "no -R override and no INPUT_TAR_FILE — GENIE payload unavailable" >&2; exit 3
fi
echo "RCDS_DIR=${RCDS_DIR}"
[ -f "${RCDS_DIR}/setup_env.sh" ] || { echo "no setup_env.sh under ${RCDS_DIR}" >&2; exit 3; }

echo "[$(date +%T)] sourcing payload setup_env.sh"
export GENIEBASE="${RCDS_DIR}"
source "${RCDS_DIR}/setup_env.sh" || { echo "payload setup_env.sh failed" >&2; exit 5; }
export XSECSPLINEDIR="${PWD}/xsec"; mkdir -p "${XSECSPLINEDIR}"
for b in gmkspl gevgen gntpc ifdh; do
  command -v "$b" >/dev/null || { echo "$b not on PATH after env setup" >&2; exit 5; }
done
echo "[$(date +%T)] env ready. GENIE=${GENIE}"

STEM="smoke_${TUNE}_$(echo "${TARGET}" | tr ',' '-')_p${PROCESS_STR}_c${CLUSTER}"
XSEC="xsec_${STEM}.xml"
GHEP="${STEM}.ghep.root"
GST="${STEM}.gst.root"

t0=${SECONDS}
echo "=== [1/3] [$(date +%T)] gmkspl  (-p ${SPL_PROBES} -t ${TARGET} -L ${GENLIST} -e ${SPL_MAXE} -n ${SPL_KNOTS}) ==="
gmkspl -p "${SPL_PROBES}" -t "${TARGET}" --tune "${TUNE}" \
       --event-generator-list "${GENLIST}" -e "${SPL_MAXE}" -n "${SPL_KNOTS}" \
       --seed "${SEED}" -o "${XSEC}"
echo "=== [1/3] done in $((SECONDS - t0))s ==="

t0=${SECONDS}
echo "=== [2/3] [$(date +%T)] gevgen  (-p ${GEV_PROBE} -t ${TARGET} -e ${GEV_ENERGY} -n ${GEV_NEVT}) ==="
gevgen -p "${GEV_PROBE}" -t "${TARGET}" -e "${GEV_ENERGY}" -n "${GEV_NEVT}" \
       --cross-sections "${PWD}/${XSEC}" --tune "${TUNE}" \
       --event-generator-list "${GENLIST}" --seed "${SEED}" -o "${GHEP}"
echo "=== [2/3] done in $((SECONDS - t0))s ==="

t0=${SECONDS}
echo "=== [3/3] [$(date +%T)] gntpc  (GHEP -> GST) ==="
gntpc -i "${GHEP}" -f gst -o "${GST}"
echo "=== [3/3] done in $((SECONDS - t0))s ==="

ls -alh

# ── Copy all three artefacts to PNFS ────────────────────────────────────────
DEST="${PNFS_OUTPUT_DIR%/}/${PROCESS_STR}"
echo "ifdh mkdir_p ${DEST}"
ifdh mkdir_p "${DEST}"
N_COPIED=0
for f in "${XSEC}" "${GHEP}" "${GST}"; do
  [ -e "$f" ] || { echo "MISSING expected output: $f" >&2; continue; }
  ifdh cp -D "$f" "${DEST}/"
  N_COPIED=$((N_COPIED + 1))
done
if [ "${N_COPIED}" -lt 3 ]; then
  echo "ERROR: expected 3 outputs (xsec/ghep/gst), copied ${N_COPIED}" >&2
  exit 4
fi
echo "copied ${N_COPIED} file(s) to ${DEST}"

date
echo "DONE"
